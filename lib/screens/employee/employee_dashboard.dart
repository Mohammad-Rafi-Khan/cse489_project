import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/task_provider.dart';

/// Employee dashboard displaying personal lifetime points, badge status,
/// task counters, and role-specific quick action tiles.
class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile == null) return;
    await Future.wait([
      context.read<TaskProvider>().loadEmployeeAssignments(auth.profile!.id),
      context.read<NotificationProvider>().loadNotifications(),
      auth.reloadProfile(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RetailFlow',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          // Notification Bell with unread counter badge
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
              context.read<TaskProvider>().clearAll();
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final profile = authProvider.profile;

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
                                      : 'E',
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
                                      'Welcome, ${profile?.name ?? 'Employee'}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      profile?.branchName ?? 'Branch Member',
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

                        // Lifetime Points & Badge Tier Progression Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.emoji_events, color: Colors.amber.shade700, size: 24),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${profile?.badgeTierName ?? 'Bronze'} Badge',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${profile?.totalLifetimePoints ?? 0} pts',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: profile?.badgeProgress ?? 0.0,
                                    minHeight: 10,
                                    backgroundColor: colorScheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade700),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Progress to ${profile?.nextBadgeName ?? 'Silver'}',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                                    ),
                                    Text(
                                      'Goal: ${profile?.nextBadgeThreshold ?? 500} pts',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Task Statistics Row
                        Consumer<TaskProvider>(
                          builder: (context, taskProvider, _) {
                            final tasks = taskProvider.employeeAssignments;
                            final pending = tasks.where((t) => t.isPending).length;
                            final completed = tasks.where((t) => t.isCompleted).length;
                            final approved = tasks.where((t) => t.isApproved).length;

                            return Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Pending',
                                    value: '$pending',
                                    color: Colors.orange,
                                    icon: Icons.hourglass_empty,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Submitted',
                                    value: '$completed',
                                    color: Colors.blue,
                                    icon: Icons.send_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Approved',
                                    value: '$approved',
                                    color: Colors.green,
                                    icon: Icons.verified_outlined,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Quick Actions Section
                        Text(
                          'Quick Actions',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.assignment_outlined,
                          title: 'My Tasks',
                          subtitle: 'Complete tasks with photo proof & view history',
                          color: colorScheme.primary,
                          onTap: () => Navigator.pushNamed(context, '/my-tasks').then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.point_of_sale,
                          title: 'Record Sale',
                          subtitle: 'Enter product sales transactions for current shift',
                          color: const Color(0xFF2E7D32),
                          onTap: () => Navigator.pushNamed(context, '/sales-entry'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.leaderboard_outlined,
                          title: 'Branch Competitions',
                          subtitle: 'View active inter-branch challenge leaderboards',
                          color: Colors.deepOrange,
                          onTap: () => Navigator.pushNamed(context, '/competitions'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.analytics_outlined,
                          title: 'My Reports & Performance',
                          subtitle: 'View completion rate, badges, and points history',
                          color: Colors.indigo,
                          onTap: () => Navigator.pushNamed(context, '/reports'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'Product Catalog',
                          subtitle: 'Browse products and unit prices',
                          color: colorScheme.secondary,
                          onTap: () => Navigator.pushNamed(context, '/products'),
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
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
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
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
