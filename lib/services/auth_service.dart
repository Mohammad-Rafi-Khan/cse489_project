import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../models/branch.dart';

/// Result of a public employee registration.
///
/// If email confirmation is disabled in Supabase, [profile] is available and
/// the user is already signed in. If confirmation is enabled, [profile] is
/// null and the user must confirm their email before signing in.
class RegistrationResult {
  final UserProfile? profile;

  const RegistrationResult({this.profile});

  bool get hasSession => profile != null;
}

class AuthProfileException implements Exception {
  final String message;

  const AuthProfileException(this.message);

  @override
  String toString() => message;
}

/// Handles all Supabase Auth operations and profile management.
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Registration ─────────────────────────────────────────

  /// Registers a new employee account.
  ///
  /// The database trigger in `supabase/setup.sql` creates the corresponding
  /// `profiles` row from the auth user's metadata. This remains reliable even
  /// when Supabase email confirmation is enabled and signUp does not create an
  /// authenticated session immediately.
  Future<RegistrationResult> signUp({
    required String name,
    required String email,
    required String password,
    required String branchId,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'name': name.trim(), 'branch_id': branchId.trim()},
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Registration failed. Please try again.');
    }

    // With email confirmation enabled, Supabase intentionally returns no
    // authenticated session. The DB trigger still creates the profile row.
    if (response.session == null) {
      return const RegistrationResult();
    }

    return RegistrationResult(profile: await fetchProfile(user.id));
  }

  // ─── Login ────────────────────────────────────────────────

  /// Signs in and returns the user's profile.
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Invalid email or password.');
    }

    try {
      return await fetchProfile(user.id);
    } catch (_) {
      await _supabase.auth.signOut();
      rethrow;
    }
  }

  // ─── Session ──────────────────────────────────────────────

  /// Returns the profile for an existing session, or null if no session.
  Future<UserProfile?> getSessionProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    return fetchProfile(user.id);
  }

  // ─── Profile ──────────────────────────────────────────────

  /// Fetches a single profile by user ID.
  Future<UserProfile> fetchProfile(String userId) async {
    final data = await _supabase
        .from('profiles')
        .select(
          '*, branches!profiles_branch_id_fkey(name), badges!profiles_current_badge_id_fkey(name)',
        )
        .eq('id', userId)
        .maybeSingle();
    if (data == null) {
      throw const AuthProfileException(
        'Login succeeded, but this account has no RetailFlow profile. Run the profile backfill SQL or ask an admin to create the profile.',
      );
    }
    return UserProfile.fromMap(data);
  }

  // ─── Branches ─────────────────────────────────────────────

  /// Returns all active branches (used in registration dropdown).
  /// `branches` has a public read policy for active rows because this screen
  /// is shown before the user has authenticated.
  Future<List<Branch>> fetchBranches() async {
    final data = await _supabase
        .from('branches')
        .select()
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => Branch.fromMap(e)).toList();
  }

  // ─── Sign Out ─────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
