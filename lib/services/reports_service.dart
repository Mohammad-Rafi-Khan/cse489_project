import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/badge.dart';
import 'badge_service.dart';

/// Aggregates role-specific analytics and reports across RetailFlow.
class ReportsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Employee Report ───────────────────────────────────────

  Future<Map<String, dynamic>> fetchEmployeeReport(String userId) async {
    // Fetch all task assignments
    final tasksData = await _supabase
        .from('task_assignments')
        .select(
          'status, scheduled_date, tasks(title, base_points, photo_bonus_points)',
        )
        .eq('user_id', userId);

    final taskList = tasksData as List;
    final totalAssigned = taskList.length;
    final approvedCount = taskList
        .where((t) => t['status'] == 'approved')
        .length;
    final completedCount = taskList
        .where((t) => t['status'] == 'completed')
        .length;
    final rejectedCount = taskList
        .where((t) => t['status'] == 'rejected')
        .length;
    final pendingCount = taskList.where((t) => t['status'] == 'pending').length;

    final completionRate = totalAssigned > 0
        ? (approvedCount / totalAssigned * 100)
        : 0.0;

    // Fetch user profile points and badge
    final profileData = await _supabase
        .from('profiles')
        .select('total_lifetime_points, badges(name)')
        .eq('id', userId)
        .single();

    final lifetimePoints = profileData['total_lifetime_points'] as int? ?? 0;
    final badgeName =
        (profileData['badges'] as Map<String, dynamic>?)?['name'] ?? 'No Badge';

    return {
      'total_assigned': totalAssigned,
      'approved_count': approvedCount,
      'completed_count': completedCount,
      'rejected_count': rejectedCount,
      'pending_count': pendingCount,
      'completion_rate': completionRate,
      'lifetime_points': lifetimePoints,
      'badge_name': badgeName,
      'tasks_history': taskList,
    };
  }

  // ─── Manager Report ────────────────────────────────────────

  Future<Map<String, dynamic>> fetchManagerReport(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr =
        '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';

    // Fetch branch sales imports from CSV source rows.
    final salesData = await _supabase
        .from('sales_imports')
        .select(
          'total_amount, sale_date, shifts(name), sales_import_items(quantity, products(name, category))',
        )
        .eq('branch_id', branchId)
        .gte('sale_date', fromStr)
        .lte('sale_date', toStr);

    final importList = salesData as List;
    final performanceData =
        await _supabase.rpc(
              'get_branch_shift_sales_performance',
              params: {
                'p_branch_id': branchId,
                'p_from': fromStr,
                'p_to': toStr,
              },
            )
            as List;
    final totalSales = performanceData.fold<double>(
      0.0,
      (sum, item) => sum + ((item['actual'] as num?)?.toDouble() ?? 0.0),
    );
    final totalTarget = performanceData.fold<double>(
      0.0,
      (sum, item) => sum + ((item['target'] as num?)?.toDouble() ?? 0.0),
    );
    final achievementRate = totalTarget > 0
        ? (totalSales / totalTarget * 100)
        : 0.0;

    // Shift breakdown
    final Map<String, double> shiftSales = {};
    for (final performance in performanceData) {
      final shiftName = performance['shift_name'] as String? ?? 'No Shift';
      final amount = (performance['actual'] as num?)?.toDouble() ?? 0.0;
      shiftSales[shiftName] = (shiftSales[shiftName] ?? 0.0) + amount;
    }

    // Product breakdown comes from optional imported item quantities.
    final Map<String, int> productQuantities = {};
    for (final imported in importList) {
      final items = imported['sales_import_items'] as List? ?? [];
      for (final item in items) {
        final prodName =
            (item['products'] as Map<String, dynamic>?)?['name'] ??
            'Unknown Product';
        final qty = item['quantity'] as int? ?? 0;
        productQuantities[prodName] = (productQuantities[prodName] ?? 0) + qty;
      }
    }

    // Branch employee task performance
    final tasksData = await _supabase
        .from('task_assignments')
        .select(
          'status, user_id, profiles!task_assignments_user_id_fkey(name, branch_id)',
        )
        .order('assigned_at', ascending: false);

    final branchTasks = (tasksData as List).where((t) {
      final profile = t['profiles'] as Map<String, dynamic>?;
      return profile?['branch_id'] == branchId;
    }).toList();

    final Map<String, Map<String, dynamic>> employeeStats = {};
    for (final t in branchTasks) {
      final p = t['profiles'] as Map<String, dynamic>?;
      final name = p?['name'] ?? 'Unknown';
      final status = t['status'] as String? ?? 'pending';

      if (!employeeStats.containsKey(name)) {
        employeeStats[name] = {
          'total': 0,
          'approved': 0,
          'pending': 0,
          'rejected': 0,
        };
      }
      employeeStats[name]!['total'] =
          (employeeStats[name]!['total'] as int) + 1;
      if (status == 'approved') {
        employeeStats[name]!['approved'] =
            (employeeStats[name]!['approved'] as int) + 1;
      } else if (status == 'rejected') {
        employeeStats[name]!['rejected'] =
            (employeeStats[name]!['rejected'] as int) + 1;
      } else {
        employeeStats[name]!['pending'] =
            (employeeStats[name]!['pending'] as int) + 1;
      }
    }

    return {
      'total_sales': totalSales,
      'total_target': totalTarget,
      'achievement_rate': achievementRate,
      'shift_sales': shiftSales,
      'product_quantities': productQuantities,
      'employee_stats': employeeStats,
      'total_imports': importList.length,
    };
  }

  // ─── Admin Report ──────────────────────────────────────────

  Future<Map<String, dynamic>> fetchAdminReport(
    DateTime from,
    DateTime to, {
    List<BadgeTier>? badgeTiers,
  }) async {
    final tiers = badgeTiers ?? await BadgeService().fetchBadgeTiers();
    final orderedTiers = [...tiers]
      ..sort((a, b) => a.minPoints.compareTo(b.minPoints));

    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr =
        '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';

    // Org-wide sales imports
    final salesData = await _supabase
        .from('sales_imports')
        .select(
          'total_amount, branch_id, branches(name), sales_import_items(quantity, products(name, category))',
        )
        .gte('sale_date', fromStr)
        .lte('sale_date', toStr);

    final importList = salesData as List;
    final totalOrgSales = importList.fold<double>(
      0.0,
      (sum, item) => sum + ((item['total_amount'] as num?)?.toDouble() ?? 0.0),
    );

    // Branch sales comparison
    final Map<String, double> branchSales = {};
    for (final imported in importList) {
      final bName =
          (imported['branches'] as Map<String, dynamic>?)?['name'] ??
          'Unknown Branch';
      final amount = (imported['total_amount'] as num?)?.toDouble() ?? 0.0;
      branchSales[bName] = (branchSales[bName] ?? 0.0) + amount;
    }

    // Product performance org-wide from imported item quantities.
    final Map<String, double> productQuantities = {};
    for (final imported in importList) {
      final items = imported['sales_import_items'] as List? ?? [];
      for (final item in items) {
        final pName =
            (item['products'] as Map<String, dynamic>?)?['name'] ??
            'Unknown Product';
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        productQuantities[pName] = (productQuantities[pName] ?? 0.0) + qty;
      }
    }

    // Badge distribution driven by the persisted badge tiers.
    final profilesData = await _supabase
        .from('profiles')
        .select('role, is_active, total_lifetime_points, badges(name)');

    final profileList = profilesData as List;
    final Map<String, int> badgeDistribution = {
      'No Badge': 0,
      ...{for (final tier in orderedTiers) tier.name: 0},
    };

    for (final p in profileList) {
      final pts = p['total_lifetime_points'] as int? ?? 0;
      String bucket = 'No Badge';

      for (final tier in orderedTiers.reversed) {
        if (pts >= tier.minPoints) {
          bucket = tier.name;
          break;
        }
      }

      badgeDistribution[bucket] = (badgeDistribution[bucket] ?? 0) + 1;
    }

    final topBranches = branchSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'total_org_sales': totalOrgSales,
      'total_imports': importList.length,
      'branch_sales': branchSales,
      'product_quantities': productQuantities,
      'total_users': profileList.length,
      'active_users': profileList.where((p) => p['is_active'] == true).length,
      'badge_distribution': badgeDistribution,
      'top_performing_branches': topBranches
          .map((entry) => {'branch_name': entry.key, 'sales': entry.value})
          .toList(),
    };
  }
}
