import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
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
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                      Navigator.pushNamed(context, '/notifications')
                          .then((_) => notifProvider.loadNotifications());
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
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
      body: Consumer3<AuthProvider, ProductProvider, TaskProvider>(
        builder: (context, auth, productProvider, taskProvider, _) {
          final profile = auth.profile;
          final totalProducts = productProvider.products.length;
          final activeTemplates = taskProvider.taskTemplates.length;
          final pendingReviewCount = taskProvider.managerAssignments
              .where((a) => a.status == 'completed')
              .length;

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
                                backgroundColor: colorScheme.onPrimary.withValues(alpha: 0.2),
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
                                        color: colorScheme.onPrimary.withValues(alpha: 0.85),
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

                        // Stats Grid
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.pending_actions_outlined,
                                label: 'Pending Review',
                                value: '$pendingReviewCount',
                                color: pendingReviewCount > 0 ? Colors.orange : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.task_outlined,
                                label: 'Task Templates',
                                value: '$activeTemplates',
                                color: const Color(0xFF00897B),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SummaryCard(
                                icon: Icons.inventory_2_outlined,
                                label: 'Active Products',
                                value: '$totalProducts',
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Tasks & Operations Section
                        Text(
                          'Tasks & Scheduling',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.rate_review_outlined,
                          title: 'Assigned Tasks & Reviews',
                          subtitle: 'Review photo evidence, approve or reject completions',
                          color: colorScheme.primary,
                          onTap: () => Navigator.pushNamed(context, '/assigned-tasks').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.assignment_add,
                          title: 'Assign Single Task',
                          subtitle: 'Assign tasks to branch employees',
                          color: const Color(0xFF00897B),
                          onTap: () => Navigator.pushNamed(context, '/assign-task').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.repeat,
                          title: 'Task Templates & Automation',
                          subtitle: 'Create templates and generate recurring assignments',
                          color: const Color(0xFF5C6BC0),
                          onTap: () => Navigator.pushNamed(context, '/task-templates').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.schedule_outlined,
                          title: 'Shift Management & Scheduling',
                          subtitle: 'Define shifts and assign staff to daily schedules',
                          color: const Color(0xFF26A69A),
                          onTap: () => Navigator.pushNamed(context, '/shift-management').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 24),

                        // Sales & Competitions Section
                        Text(
                          'Sales, Competitions & Reports',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.track_changes_outlined,
                          title: 'Sales Targets',
                          subtitle: 'Set and update daily branch/shift sales goals',
                          color: const Color(0xFFEF6C00),
                          onTap: () => Navigator.pushNamed(context, '/sales-targets').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.insights_outlined,
                          title: 'Sales Performance',
                          subtitle: 'Compare actual sales against targets & shift stats',
                          color: const Color(0xFF2E7D32),
                          onTap: () => Navigator.pushNamed(context, '/sales-performance').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.leaderboard_outlined,
                          title: 'Inter-Branch Competitions',
                          subtitle: 'View live competition standings and product points',
                          color: Colors.deepOrange,
                          onTap: () => Navigator.pushNamed(context, '/competitions'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.analytics_outlined,
                          title: 'Branch Analytics & Reports',
                          subtitle: 'Shift performance, target trends, and staff task metrics',
                          color: Colors.indigo,
                          onTap: () => Navigator.pushNamed(context, '/reports'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'Product Catalog',
                          subtitle: 'Manage products and pricing',
                          color: colorScheme.secondary,
                          onTap: () => Navigator.pushNamed(context, '/products').then((_) => _loadData()),
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
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        onTap: onTap,
      ),
    );
  }
}
