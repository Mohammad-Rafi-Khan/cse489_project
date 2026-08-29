import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issue_provider.dart';
import '../../providers/leave_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/task_provider.dart';

/// Manager dashboard showing branch metrics, pending tasks queue,
/// and quick navigation for all branch management operations.
class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;

    await Future.wait([
      context.read<ProductProvider>().loadProducts(),
      context.read<NotificationProvider>().loadNotifications(),
      if (branchId != null) ...[
        context.read<TaskProvider>().loadTaskTemplates(branchId),
        context.read<TaskProvider>().loadManagerAssignments(branchId),
        context.read<IssueProvider>().loadBranchIssues(branchId),
        context.read<LeaveProvider>().loadBranchLeaves(branchId),
        context.read<SalesProvider>().loadTargets(
          branchId,
          DateTime.now(),
          DateTime.now(),
        ),
        context.read<SalesProvider>().loadPerformanceForRange(
          branchId,
          DateTime.now(),
          DateTime.now(),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactCurrency = NumberFormat.compactCurrency(
      symbol: 'BDT ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manager Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          // Notification Bell
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, _) {
              final unread = notifProvider.unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications',
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/notifications',
                      ).then((_) => notifProvider.loadNotifications());
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              context.read<ProductProvider>().clearAll();
              context.read<TaskProvider>().clearAll();
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Consumer4<AuthProvider, ProductProvider, TaskProvider, SalesProvider>(
        builder: (context, auth, productProvider, taskProvider, salesProvider, _) {
          final profile = auth.profile;
          final totalProducts = productProvider.products.length;
          final activeTemplates = taskProvider.taskTemplates.length;
          final pendingReviewCount = taskProvider.managerAssignments
              .where((a) => a.status == 'completed')
              .length;
          final totalAssignments = taskProvider.managerAssignments.length;
          final approvedAssignments = taskProvider.managerAssignments
              .where((a) => a.status == 'approved')
              .length;
          final completionRate = totalAssignments == 0
              ? 0
              : (approvedAssignments / totalAssignments * 100).round();
          final actualSales = salesProvider.rangePerformance.fold<double>(
            0,
            (sum, row) => sum + ((row['actual'] as num?)?.toDouble() ?? 0),
          );
          final targetSales = salesProvider.rangePerformance.fold<double>(
            0,
            (sum, row) => sum + ((row['target'] as num?)?.toDouble() ?? 0),
          );
          final salesAchievement = targetSales == 0
              ? 0
              : (actualSales / targetSales * 100).round();

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withValues(alpha: 0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: colorScheme.onPrimary
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  (profile?.name.isNotEmpty == true)
                                      ? profile!.name[0].toUpperCase()
                                      : 'M',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome, ${profile?.name ?? 'Manager'}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Managing ${profile?.branchName ?? 'Store Location'}',
                                      style: TextStyle(
                                        color: colorScheme.onPrimary.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'Business KPIs',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),

                        // Stats Grid
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.pending_actions_outlined,
                                label: 'Pending Review',
                                value: '$pendingReviewCount',
                                color: pendingReviewCount > 0
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.verified_outlined,
                                label: 'Approval Rate',
                                value: '$completionRate%',
                                color: const Color(0xFF00897B),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.trending_up_outlined,
                                label: 'Today Sales',
                                value: compactCurrency.format(actualSales),
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.track_changes_outlined,
                                label: 'Sales Goal',
                                value: '$salesAchievement%',
                                color: const Color(0xFFEF6C00),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.task_outlined,
                                label: 'Templates',
                                value: '$activeTemplates',
                                color: const Color(0xFF5C6BC0),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.inventory_2_outlined,
                                label: 'Products',
                                value: '$totalProducts',
                                color: colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Tasks & Operations Section
                        Text(
                          'Tasks & Scheduling',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.rate_review_outlined,
                          title: 'Assigned Tasks & Reviews',
                          subtitle:
                              'Review photo evidence, approve or reject completions',
                          color: colorScheme.primary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/assigned-tasks',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.assignment_add,
                          title: 'Assign Single Task',
                          subtitle: 'Assign tasks to branch employees',
                          color: const Color(0xFF00897B),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/assign-task',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.repeat,
                          title: 'Task Templates',
                          subtitle:
                              'Create and manage reusable task templates',
                          color: const Color(0xFF5C6BC0),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/task-templates',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.event_available_outlined,
                          title: 'Branch Attendance',
                          subtitle: 'Track check-ins, lateness, and attendance history',
                          color: Colors.green,
                          onTap: () => Navigator.pushNamed(context, '/attendance')
                              .then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.schedule_outlined,
                          title: 'Shift Management & Scheduling',
                          subtitle:
                              'Define shifts and assign staff to daily schedules',
                          color: const Color(0xFF26A69A),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/shift-management',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 24),

                        // Sales & Operations Section
                        Text(
                          'Branch Sales Analytics & Reports',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.insights_outlined,
                          title: 'Branch Sales Performance',
                          subtitle:
                              'View imported sales, target progress, and shift stats',
                          color: const Color(0xFF2E7D32),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/sales-performance',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.track_changes_outlined,
                          title: 'Branch Sales Targets',
                          subtitle:
                              'Set and review monthly sales targets for your branch',
                          color: const Color(0xFFEF6C00),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/sales-targets',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.analytics_outlined,
                          title: 'Branch Analytics & Reports',
                          subtitle:
                              'Shift performance, target trends, and staff task metrics',
                          color: Colors.indigo,
                          onTap: () => Navigator.pushNamed(context, '/reports'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.report_problem_outlined,
                          title: 'Branch Issue Review',
                          subtitle:
                              'Monitor staff-reported issues and update resolution status',
                          color: Colors.red,
                          onTap: () => Navigator.pushNamed(context, '/issues')
                              .then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.event_available_outlined,
                          title: 'Leave Management',
                          subtitle: 'Approve or reject employee leave requests',
                          color: Colors.green,
                          onTap: () => Navigator.pushNamed(context, '/leave-requests')
                              .then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.price_change_outlined,
                          title: 'Product Price Management',
                          subtitle:
                              'Maintain product pricing and review price history',
                          color: colorScheme.secondary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/products',
                          ).then((_) => _loadData()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        onTap: onTap,
      ),
    );
  }
}
