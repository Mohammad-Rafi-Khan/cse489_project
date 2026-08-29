import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/user_profile.dart';

class UserManagementException implements Exception {
  final String message;

  const UserManagementException(this.message);

  @override
  String toString() => message;
}

class UserCreationResult {
  final String userId;
  final bool requiresEmailConfirmation;
  final bool usedEdgeFunction;

  const UserCreationResult({
    required this.userId,
    required this.requiresEmailConfirmation,
    required this.usedEdgeFunction,
  });

  String get successMessage {
    if (requiresEmailConfirmation) {
      return 'User created. They must confirm their email before signing in.';
    }
    return 'User created successfully.';
  }
}

/// Handles user and role management for Admins.
class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<UserCreationResult> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    final normalizedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    final normalizedBranchId = branchId?.trim();

    if (normalizedName.isEmpty) {
      throw const UserManagementException('Full name is required.');
    }
    if (!_looksLikeEmail(normalizedEmail)) {
      throw const UserManagementException('Enter a valid email address.');
    }
    if (password.length < 8) {
      throw const UserManagementException(
        'Temporary password must be at least 8 characters.',
      );
    }

    _validateRoleAndBranch(
      role: normalizedRole,
      branchId: normalizedBranchId,
    );

    if (normalizedRole != 'admin') {
      await _ensureActiveBranch(normalizedBranchId!);
    }
    await _ensureEmailNotUsed(normalizedEmail);

    // Preferred path: the hosted Edge Function creates a confirmed Auth user
    // with server-side privileges while preserving the current Admin session.
    try {
      return await _createViaEdgeFunction(
        name: normalizedName,
        email: normalizedEmail,
        password: password,
        role: normalizedRole,
        branchId: normalizedRole == 'admin' ? null : normalizedBranchId,
      );
    } on FunctionException catch (error) {
      final message = _functionErrorMessage(error);

      // A publishable-key project can reject a function at the gateway if the
      // deployed function still has legacy verify_jwt enabled, or the function
      // may simply not have been deployed yet. Keep the Admin workflow usable
      // with an isolated Auth client that never replaces the Admin session.
      if (_canUseIsolatedSignupFallback(error, message)) {
        return _createViaIsolatedSignup(
          name: normalizedName,
          email: normalizedEmail,
          password: password,
          role: normalizedRole,
          branchId: normalizedRole == 'admin' ? null : normalizedBranchId,
        );
      }
      throw UserManagementException(message);
    }
  }

  Future<UserCreationResult> _createViaEdgeFunction({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    final session = _supabase.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const UserManagementException(
        'You must be signed in as an admin to create users.',
      );
    }

    final response = await _supabase.functions.invoke(
      'create-user',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'branch_id': branchId,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw const UserManagementException(
        'The create-user function returned an invalid response.',
      );
    }
    if (data['error'] != null) {
      throw UserManagementException(data['error'].toString());
    }

    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const UserManagementException(
        'The account was not created correctly. No user ID was returned.',
      );
    }

    return UserCreationResult(
      userId: id,
      requiresEmailConfirmation: false,
      usedEdgeFunction: true,
    );
  }

  /// Safe fallback for hosted projects where the create-user function is not
  /// deployed/configured yet. A completely separate Supabase client performs
  /// signUp, so the currently authenticated Admin session is never replaced.
  /// The Admin client then promotes/attaches the generated profile through RLS.
  Future<UserCreationResult> _createViaIsolatedSignup({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) {
      throw const UserManagementException(
        'Your Admin session expired. Sign in again and retry.',
      );
    }

    // Confirm the current account still has active Admin privileges before
    // using the fallback path.
    final caller = await _supabase
        .from('profiles')
        .select('id, role, is_active')
        .eq('id', adminId)
        .maybeSingle();
    if (caller == null || caller['role'] != 'admin') {
      throw const UserManagementException(
        'Only an Admin account can create users.',
      );
    }
    if (caller['is_active'] != true) {
      throw const UserManagementException('This Admin account is inactive.');
    }

    final signupClient = SupabaseClient(
      SupabaseConfig.url,
      SupabaseConfig.anonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    AuthResponse response;
    try {
      response = await signupClient.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          // The trigger intentionally creates an employee-first profile. The
          // authenticated Admin client promotes it below after Auth succeeds.
          'branch_id': branchId,
        },
      );
    } on AuthException catch (error) {
      throw UserManagementException(_authSignupErrorMessage(error));
    }

    final newUser = response.user;
    if (newUser == null) {
      throw const UserManagementException(
        'Supabase Auth did not return the newly created user.',
      );
    }

    // The Auth trigger runs in the database. Give it a short moment to create
    // the profile before the Admin promotes the role/branch.
    Map<String, dynamic>? profile;
    for (var attempt = 0; attempt < 8; attempt++) {
      final row = await _supabase
          .from('profiles')
          .select('id, email, role, branch_id')
          .eq('id', newUser.id)
          .maybeSingle();
      if (row != null) {
        profile = Map<String, dynamic>.from(row);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (profile == null) {
      throw const UserManagementException(
        'The Auth account was created, but its RetailFlow profile was not. Run the hosted admin repair SQL, then edit this user from User Management.',
      );
    }

    try {
      await _supabase.from('profiles').update({
        'name': name,
        'email': email,
        'role': role,
        'branch_id': role == 'admin' ? null : branchId,
        'is_active': true,
      }).eq('id', newUser.id);

      await _syncBranchManager(
        userId: newUser.id,
        role: role,
        branchId: branchId,
      );
    } on PostgrestException catch (error) {
      throw UserManagementException(
        'The Auth account was created, but the Admin profile update failed: ${error.message}. Run the hosted admin repair SQL and then correct the user from User Management.',
      );
    } finally {
      // If Confirm email is disabled, the isolated client receives a session.
      // Signing out that isolated client never touches the main Admin client.
      if (response.session != null) {
        try {
          await signupClient.auth.signOut();
        } catch (_) {
          // The account itself is already created; local cleanup failure should
          // not turn a successful Admin operation into an error.
        }
      }
    }

    return UserCreationResult(
      userId: newUser.id,
      requiresEmailConfirmation: response.session == null,
      usedEdgeFunction: false,
    );
  }

  /// Fetches all users across the organization.
  Future<List<UserProfile>> fetchAllUsers() async {
    final data = await _supabase
        .from('profiles')
        .select(
          '*, branches!profiles_branch_id_fkey(name), badges!profiles_current_badge_id_fkey(name)',
        )
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }

  /// Updates user profile details, role, branch assignment, and active status.
  Future<UserProfile> updateUser({
    required String id,
    String? name,
    required String role,
    String? branchId,
    required bool isActive,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    final normalizedBranchId = branchId?.trim();
    final currentUserId = _supabase.auth.currentUser?.id;
    if (id == currentUserId && normalizedRole != 'admin') {
      throw const UserManagementException(
        'You cannot remove the Admin role from the account you are currently using.',
      );
    }
    if (id == currentUserId && !isActive) {
      throw const UserManagementException(
        'You cannot deactivate the Admin account you are currently using.',
      );
    }
    _validateRoleAndBranch(
      role: normalizedRole,
      branchId: normalizedBranchId,
    );
    if (normalizedRole != 'admin') {
      await _ensureActiveBranch(normalizedBranchId!);
    }

    final updateData = <String, dynamic>{
      'role': normalizedRole,
      'branch_id': normalizedRole == 'admin' ? null : normalizedBranchId,
      'is_active': isActive,
    };
    if (name != null && name.trim().isNotEmpty) {
      updateData['name'] = name.trim();
    }

    try {
      final data = await _supabase
          .from('profiles')
          .update(updateData)
          .eq('id', id)
          .select(
            '*, branches!profiles_branch_id_fkey(name), badges!profiles_current_badge_id_fkey(name)',
          )
          .single();
      final updated = UserProfile.fromMap(data);
      await _syncBranchManager(
        userId: id,
        role: normalizedRole,
        branchId: normalizedBranchId,
      );
      return updated;
    } on PostgrestException catch (error) {
      throw UserManagementException(_databaseErrorMessage(error));
    }
  }

  Future<void> _ensureEmailNotUsed(String email) async {
    final existing = await _supabase
        .from('profiles')
        .select('id')
        .eq('email', email)
        .limit(1);
    if ((existing as List).isNotEmpty) {
      throw const UserManagementException(
        'An account with this email already exists.',
      );
    }
  }

  Future<void> _ensureActiveBranch(String branchId) async {
    final branch = await _supabase
        .from('branches')
        .select('id')
        .eq('id', branchId)
        .eq('is_active', true)
        .maybeSingle();
    if (branch == null) {
      throw const UserManagementException(
        'Selected branch is inactive or missing.',
      );
    }
  }

  Future<void> _syncBranchManager({
    required String userId,
    required String role,
    String? branchId,
  }) async {
    // A profile can only be the primary manager of one branch in the current
    // RetailFlow model. Clear old primary-manager links before assigning one.
    await _supabase
        .from('branches')
        .update({'manager_id': null})
        .eq('manager_id', userId);

    if (role == 'manager' && branchId != null && branchId.trim().isNotEmpty) {
      final normalizedBranchId = branchId.trim();
      final selectedBranch = await _supabase
          .from('branches')
          .select('manager_id')
          .eq('id', normalizedBranchId)
          .maybeSingle();
      final previousManagerId = selectedBranch?['manager_id'] as String?;

      await _supabase
          .from('branches')
          .update({'manager_id': userId})
          .eq('id', normalizedBranchId);

      if (previousManagerId != null && previousManagerId != userId) {
        final managesAnotherBranch = await _supabase
            .from('branches')
            .select('id')
            .eq('manager_id', previousManagerId)
            .limit(1);
        if ((managesAnotherBranch as List).isEmpty) {
          await _supabase
              .from('profiles')
              .update({'branch_id': null})
              .eq('id', previousManagerId)
              .eq('branch_id', normalizedBranchId);
        }
      }
    }
  }

  void _validateRoleAndBranch({required String role, String? branchId}) {
    if (!{'employee', 'manager', 'admin'}.contains(role)) {
      throw const UserManagementException('Invalid user role.');
    }
    if (role != 'admin' && (branchId == null || branchId.trim().isEmpty)) {
      throw const UserManagementException(
        'A branch is required for employees and managers.',
      );
    }
  }

  bool _looksLikeEmail(String email) {
    final at = email.indexOf('@');
    final dot = email.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < email.length - 1;
  }

  bool _canUseIsolatedSignupFallback(
    FunctionException error,
    String message,
  ) {
    final lower = message.toLowerCase();
    return error.status == 404 ||
        (error.status == 401 && lower.contains('invalid jwt')) ||
        lower.contains('function not found') ||
        lower.contains('missing supabase environment') ||
        lower.contains('supabase_service_role_key') ||
        lower.contains('supabase_secret_keys');
  }

  String _functionErrorMessage(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final value = details['error'] ?? details['message'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    if (details is String && details.trim().isNotEmpty) {
      return details.trim();
    }

    if (error.status == 404) {
      return 'The hosted create-user Edge Function is not deployed.';
    }
    if (error.status == 401) {
      return 'The create-user function rejected the Admin session. Redeploy it with verify_jwt disabled for publishable-key projects.';
    }
    return error.reasonPhrase ??
        'The create-user Edge Function could not complete the request.';
  }

  String _authSignupErrorMessage(AuthException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('already') || lower.contains('registered')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('signup') && lower.contains('disabled')) {
      return 'Public Auth sign-up is disabled. Deploy the hosted create-user Edge Function from this project instead.';
    }
    if (lower.contains('password')) {
      return 'Supabase rejected the password: ${error.message}';
    }
    return 'Could not create the Auth account: ${error.message}';
  }

  String _databaseErrorMessage(PostgrestException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('row-level security') || lower.contains('permission')) {
      return 'Admin database permissions are not deployed correctly. Run supabase/admin_remote_repair.sql on the hosted project.';
    }
    if (lower.contains('foreign key')) {
      return 'The selected branch or related record no longer exists.';
    }
    return error.message;
  }
}
