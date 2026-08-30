import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/branch_provider.dart';
import '../../providers/issue_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/user_management_provider.dart';

/// Full operational Admin Dashboard for multi-branch network control,
/// user governance, analytics products, and org-wide reporting.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    await Future.wait([
      context.read<BranchProvider>().loadBranches(),
      context.read<UserManagementProvider>().loadUsers(),
      context.read<ProductProvider>().loadProducts(),
      context.read<NotificationProvider>().loadNotifications(),
      context.read<IssueProvider>().loadCompanyIssues(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Command Center',
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
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Consumer3<BranchProvider, UserManagementProvider, ProductProvider>(
        builder: (context, branchProvider, userProvider, prodProvider, _) {
          final totalBranches = branchProvider.branches.length;
          final activeBranches = branchProvider.activeBranches.length;
          final totalUsers = userProvider.users.length;
          final activeUsers = userProvider.users
              .where((user) => user.isActive)
              .length;
          final staffedBranches = branchProvider.branches
              .where((branch) => branch.managerId != null)
              .length;
          final managerCoverage = totalBranches == 0
              ? 0
              : (staffedBranches / totalBranches * 100).round();

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
                        // Admin Greeting Banner
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
                                child: Icon(
                                  Icons.admin_panel_settings,
                                  size: 30,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Organization Overview',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Managing all branches, staff, pricing, and branch operations',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
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

                        // Stats Grid Row
                        Row(
                          children: [
                            Expanded(
                              child: _AdminStatCard(
                                icon: Icons.store,
                                label: 'Active Branches',
                                value: '$activeBranches/$totalBranches',
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AdminStatCard(
                                icon: Icons.people_alt_outlined,
                                label: 'Active Staff',
                                value: '$activeUsers/$totalUsers',
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AdminStatCard(
                                icon: Icons.emoji_events_outlined,
                                label: 'Manager Coverage',
                                value: '$managerCoverage%',
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Management Modules
                        Text(
                          'Administration & Governance',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.store_outlined,
                          title: 'Multi-Branch Management',
                          subtitle:
                              'Create store locations, set managers, and toggle status',
                          color: colorScheme.primary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/branch-management',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.manage_accounts_outlined,
                          title: 'User & Role Management',
                          subtitle:
                              'Assign Employee, Manager, Admin roles and branch assignments',
                          color: Colors.teal,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/user-management',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.cloud_upload_outlined,
                          title: 'Sales Data Import',
                          subtitle:
                              'Admin-only CSV ingestion with duplicate controls',
                          color: const Color(0xFF00838F),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/sales-import',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.track_changes_outlined,
                          title: 'Sales Target Governance',
                          subtitle:
                              'Set branch and shift goals used in performance KPIs',
                          color: const Color(0xFFEF6C00),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/sales-targets',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.analytics_outlined,
                          title: 'Organization Analytics & Reports',
                          subtitle:
                              'Branch revenue comparisons, product performance, and badge counts',
                          color: Colors.indigo,
                          onTap: () => Navigator.pushNamed(context, '/reports'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.price_change_outlined,
                          title: 'Product Price Management',
                          subtitle:
                              'Maintain pricing and review historical price changes',
                          color: colorScheme.secondary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/products',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        Consumer<IssueProvider>(
                          builder: (context, issueProvider, _) {
                            final openCount = issueProvider.issues
                                .where((i) => i.isOpen || i.isInProgress)
                                .length;
                            return _DashboardTile(
                              icon: Icons.report_problem_outlined,
                              title: 'Issue Reports',
                              subtitle: openCount > 0
                                  ? '$openCount open issue${openCount == 1 ? '' : 's'} — tap to review and resolve'
                                  : 'Review branch issues and manager escalations',
                              color: openCount > 0 ? Colors.red : Colors.grey,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/issues',
                              ).then((_) => _loadData()),
                            );
                          },
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

class _AdminStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _AdminStatCard({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
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
