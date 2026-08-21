import 'package:supabase_flutter/supabase_flutter.dart';

/// Aggregates role-specific analytics and reports across RetailFlow.
class ReportsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Employee Report ───────────────────────────────────────

  Future<Map<String, dynamic>> fetchEmployeeReport(String userId) async {
    // Fetch all task assignments
    final tasksData = await _supabase
        .from('task_assignments')
        .select('status, scheduled_date, tasks(title, base_points, photo_bonus_points)')
        .eq('user_id', userId);

    final taskList = tasksData as List;
    final totalAssigned = taskList.length;
    final approvedCount = taskList.where((t) => t['status'] == 'approved').length;
    final completedCount = taskList.where((t) => t['status'] == 'completed').length;
    final rejectedCount = taskList.where((t) => t['status'] == 'rejected').length;
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

  Future<Map<String, dynamic>> fetchManagerReport(String branchId, DateTime from, DateTime to) async {
    final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr = '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';

    // Fetch branch sales entries
    final salesData = await _supabase
        .from('sales_entries')
        .select('total_amount, quantity, sale_date, products(name, category), shifts(name), profiles(name)')
        .eq('branch_id', branchId)
        .gte('sale_date', fromStr)
        .lte('sale_date', toStr);

    final salesList = salesData as List;
    final totalSales = salesList.fold<double>(
        0.0, (sum, item) => sum + ((item['total_amount'] as num?)?.toDouble() ?? 0.0));

    // Fetch branch sales targets
    final targetsData = await _supabase
        .from('sales_targets')
        .select('target_amount, shift_id, shifts(name)')
        .eq('branch_id', branchId)
        .gte('target_date', fromStr)
        .lte('target_date', toStr);

    final targetList = targetsData as List;
    final totalTarget = targetList.fold<double>(
        0.0, (sum, item) => sum + ((item['target_amount'] as num?)?.toDouble() ?? 0.0));

    final achievementRate = totalTarget > 0 ? (totalSales / totalTarget * 100) : 0.0;

    // Shift breakdown
    final Map<String, double> shiftSales = {};
    for (final sale in salesList) {
      final shiftName = (sale['shifts'] as Map<String, dynamic>?)?['name'] ?? 'No Shift';
      final amount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
      shiftSales[shiftName] = (shiftSales[shiftName] ?? 0.0) + amount;
    }

    // Product breakdown
    final Map<String, int> productQuantities = {};
    for (final sale in salesList) {
      final prodName = (sale['products'] as Map<String, dynamic>?)?['name'] ?? 'Unknown Product';
      final qty = sale['quantity'] as int? ?? 0;
      productQuantities[prodName] = (productQuantities[prodName] ?? 0) + qty;
    }

    // Branch employee task performance
    final tasksData = await _supabase
        .from('task_assignments')
        .select('status, user_id, profiles!task_assignments_user_id_fkey(name, branch_id)')
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
        employeeStats[name] = {'total': 0, 'approved': 0, 'pending': 0, 'rejected': 0};
      }
      employeeStats[name]!['total'] = (employeeStats[name]!['total'] as int) + 1;
      if (status == 'approved') {
        employeeStats[name]!['approved'] = (employeeStats[name]!['approved'] as int) + 1;
      } else if (status == 'rejected') {
        employeeStats[name]!['rejected'] = (employeeStats[name]!['rejected'] as int) + 1;
      } else {
        employeeStats[name]!['pending'] = (employeeStats[name]!['pending'] as int) + 1;
      }
    }

    return {
      'total_sales': totalSales,
      'total_target': totalTarget,
      'achievement_rate': achievementRate,
      'shift_sales': shiftSales,
      'product_quantities': productQuantities,
      'employee_stats': employeeStats,
      'total_transactions': salesList.length,
    };
  }

  // ─── Admin Report ──────────────────────────────────────────

  Future<Map<String, dynamic>> fetchAdminReport(DateTime from, DateTime to) async {
    final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr = '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';

    // Org-wide sales entries
    final salesData = await _supabase
        .from('sales_entries')
        .select('total_amount, quantity, branch_id, branches(name), products(name, category)')
        .gte('sale_date', fromStr)
        .lte('sale_date', toStr);

    final salesList = salesData as List;
    final totalOrgSales = salesList.fold<double>(
        0.0, (sum, item) => sum + ((item['total_amount'] as num?)?.toDouble() ?? 0.0));

    // Branch sales comparison
    final Map<String, double> branchSales = {};
    for (final sale in salesList) {
      final bName = (sale['branches'] as Map<String, dynamic>?)?['name'] ?? 'Unknown Branch';
      final amount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
      branchSales[bName] = (branchSales[bName] ?? 0.0) + amount;
    }

    // Product performance org-wide
    final Map<String, double> productSales = {};
    for (final sale in salesList) {
      final pName = (sale['products'] as Map<String, dynamic>?)?['name'] ?? 'Unknown Product';
      final amount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
      productSales[pName] = (productSales[pName] ?? 0.0) + amount;
    }

    // Badge distribution
    final profilesData = await _supabase
        .from('profiles')
        .select('role, is_active, total_lifetime_points, badges(name)');

    final profileList = profilesData as List;
    final Map<String, int> badgeDistribution = {
      'Platinum': 0,
      'Gold': 0,
      'Silver': 0,
      'Bronze': 0,
      'No Badge': 0,
    };

    for (final p in profileList) {
      final pts = p['total_lifetime_points'] as int? ?? 0;
      if (pts >= 5000) {
        badgeDistribution['Platinum'] = (badgeDistribution['Platinum'] ?? 0) + 1;
      } else if (pts >= 3000) {
        badgeDistribution['Gold'] = (badgeDistribution['Gold'] ?? 0) + 1;
      } else if (pts >= 1500) {
        badgeDistribution['Silver'] = (badgeDistribution['Silver'] ?? 0) + 1;
      } else if (pts >= 500) {
        badgeDistribution['Bronze'] = (badgeDistribution['Bronze'] ?? 0) + 1;
      } else {
        badgeDistribution['No Badge'] = (badgeDistribution['No Badge'] ?? 0) + 1;
      }
    }

    return {
      'total_org_sales': totalOrgSales,
      'total_transactions': salesList.length,
      'branch_sales': branchSales,
      'product_sales': productSales,
      'total_users': profileList.length,
      'active_users': profileList.where((p) => p['is_active'] == true).length,
      'badge_distribution': badgeDistribution,
    };
  }
}
