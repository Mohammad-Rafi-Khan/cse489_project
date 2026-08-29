import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/branch.dart';
import '../models/user_profile.dart';

class BranchManagementException implements Exception {
  final String message;

  const BranchManagementException(this.message);

  @override
  String toString() => message;
}

/// Handles CRUD operations and manager assignment for branches.
class BranchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all branches (active and inactive for admins).
  Future<List<Branch>> fetchAllBranches() async {
    final data = await _supabase.from('branches').select().order('name');
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

  /// Create a new branch and keep its primary manager's profile branch in sync.
  Future<Branch> createBranch({
    required String name,
    String? location,
    String? managerId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const BranchManagementException('Branch name is required.');
    }
    final normalizedManagerId = _cleanId(managerId);
    if (normalizedManagerId != null) {
      await _ensureEligibleManager(normalizedManagerId);
    }

    try {
      final data = await _supabase
          .from('branches')
          .insert({
            'name': normalizedName,
            'location': _cleanText(location),
            'manager_id': normalizedManagerId,
            'is_active': true,
          })
          .select()
          .single();
      final branch = Branch.fromMap(data);

      if (normalizedManagerId != null) {
        await _attachManagerToBranch(
          managerId: normalizedManagerId,
          branchId: branch.id,
        );
      }
      return branch;
    } on PostgrestException catch (error) {
      throw BranchManagementException(_databaseMessage(error));
    }
  }

  /// Update branch details and keep manager/profile branch assignment aligned.
  Future<Branch> updateBranch({
    required String id,
    required String name,
    String? location,
    String? managerId,
    required bool isActive,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const BranchManagementException('Branch name is required.');
    }
    final normalizedManagerId = _cleanId(managerId);
    if (normalizedManagerId != null) {
      await _ensureEligibleManager(normalizedManagerId);
    }

    final current = await _supabase
        .from('branches')
        .select('id, manager_id')
        .eq('id', id)
        .maybeSingle();
    if (current == null) {
      throw const BranchManagementException('Branch no longer exists.');
    }
    final previousManagerId = current['manager_id'] as String?;

    try {
      final data = await _supabase
          .from('branches')
          .update({
            'name': normalizedName,
            'location': _cleanText(location),
            'manager_id': normalizedManagerId,
            'is_active': isActive,
          })
          .eq('id', id)
          .select()
          .single();

      if (normalizedManagerId != null) {
        await _attachManagerToBranch(
          managerId: normalizedManagerId,
          branchId: id,
        );
      }
      if (previousManagerId != null &&
          previousManagerId != normalizedManagerId) {
        await _detachOldManagerIfNeeded(
          managerId: previousManagerId,
          branchId: id,
        );
      }

      return Branch.fromMap(data);
    } on PostgrestException catch (error) {
      throw BranchManagementException(_databaseMessage(error));
    }
  }

  /// Fetch active Manager profiles eligible for primary branch assignment.
  /// Admin accounts are deliberately excluded: Admin is company-wide and has
  /// no branch_id in the RetailFlow data model.
  Future<List<UserProfile>> fetchEligibleManagers() async {
    final data = await _supabase
        .from('profiles')
        .select(
          '*, branches!profiles_branch_id_fkey(name), badges!profiles_current_badge_id_fkey(name)',
        )
        .eq('role', 'manager')
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }

  Future<void> _ensureEligibleManager(String managerId) async {
    final manager = await _supabase
        .from('profiles')
        .select('id, role, is_active')
        .eq('id', managerId)
        .maybeSingle();
    if (manager == null ||
        manager['role'] != 'manager' ||
        manager['is_active'] != true) {
      throw const BranchManagementException(
        'Select an active Manager account for this branch.',
      );
    }
  }

  Future<void> _attachManagerToBranch({
    required String managerId,
    required String branchId,
  }) async {
    // A primary manager belongs to one branch in the current profile model.
    await _supabase
        .from('branches')
        .update({'manager_id': null})
        .eq('manager_id', managerId)
        .neq('id', branchId);

    await _supabase.from('profiles').update({
      'branch_id': branchId,
    }).eq('id', managerId);
  }

  Future<void> _detachOldManagerIfNeeded({
    required String managerId,
    required String branchId,
  }) async {
    final stillPrimaryElsewhere = await _supabase
        .from('branches')
        .select('id')
        .eq('manager_id', managerId)
        .neq('id', branchId)
        .limit(1);

    if ((stillPrimaryElsewhere as List).isEmpty) {
      await _supabase
          .from('profiles')
          .update({'branch_id': null})
          .eq('id', managerId)
          .eq('branch_id', branchId);
    }
  }

  String? _cleanId(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  String? _cleanText(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  String _databaseMessage(PostgrestException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('row-level security') || lower.contains('permission')) {
      return 'Admin branch permissions are not deployed correctly. Run supabase/admin_remote_repair.sql on the hosted project.';
    }
    if (lower.contains('foreign key')) {
      return 'The selected manager or related branch record is invalid.';
    }
    return error.message;
  }
}
