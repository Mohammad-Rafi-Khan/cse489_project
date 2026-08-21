import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

/// Handles user and role management for Admins.
class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches all users across the organization.
  Future<List<UserProfile>> fetchAllUsers() async {
    final data = await _supabase
        .from('profiles')
        .select('*, branches(name), badges(name)')
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
    final updateData = <String, dynamic>{
      'role': role,
      'branch_id': branchId,
      'is_active': isActive,
    };
    if (name != null && name.trim().isNotEmpty) {
      updateData['name'] = name.trim();
    }

    final data = await _supabase
        .from('profiles')
        .update(updateData)
        .eq('id', id)
        .select('*, branches(name), badges(name)')
        .single();
    return UserProfile.fromMap(data);
  }
}
