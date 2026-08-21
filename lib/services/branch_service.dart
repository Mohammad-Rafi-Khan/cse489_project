import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/branch.dart';
import '../models/user_profile.dart';

/// Handles CRUD operations and manager assignment for branches.
class BranchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all branches (active and inactive for admins).
  Future<List<Branch>> fetchAllBranches() async {
    final data = await _supabase
        .from('branches')
        .select()
        .order('name');
    return (data as List).map((e) => Branch.fromMap(e)).toList();
  }

  /// Fetch active branches.
  Future<List<Branch>> fetchActiveBranches() async {
    final data = await _supabase
        .from('branches')
        .select()
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => Branch.fromMap(e)).toList();
  }

  /// Create a new branch.
  Future<Branch> createBranch({
    required String name,
    String? location,
    String? managerId,
  }) async {
    final data = await _supabase
        .from('branches')
        .insert({
          'name': name,
          'location': location,
          'manager_id': managerId,
          'is_active': true,
        })
        .select()
        .single();
    return Branch.fromMap(data);
  }

  /// Update branch details and manager.
  Future<Branch> updateBranch({
    required String id,
    required String name,
    String? location,
    String? managerId,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('branches')
        .update({
          'name': name,
          'location': location,
          'manager_id': managerId,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Branch.fromMap(data);
  }

  /// Fetch eligible managers for assignment to branches.
  Future<List<UserProfile>> fetchEligibleManagers() async {
    final data = await _supabase
        .from('profiles')
        .select('*, branches(name), badges(name)')
        .inFilter('role', ['manager', 'admin'])
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }
}
