import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reports_provider.dart';

/// Comprehensive role-adaptive reporting and analytics screen.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
  }

  Future<void> _loadReport() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;

    final provider = context.read<ReportsProvider>();
    if (profile.isAdmin) {
      await provider.loadAdminReport(_startDate, _endDate);
    } else if (profile.isManager && profile.branchId != null) {
      await provider.loadManagerReport(profile.branchId!, _startDate, _endDate);
    } else {
      await provider.loadEmployeeReport(profile.id);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;

    String title = 'Analytics & Reports';
    if (profile?.isAdmin == true) {
      title = 'Organization Analytics';
    } else if (profile?.isManager == true) {
      title = 'Branch Sales & Staff Report';
    } else {
      title = 'My Performance Report';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        actions: [
          if (profile?.isEmployee != true)
            IconButton(
              icon: const Icon(Icons.date_range_outlined),
              tooltip: 'Filter Date Range',
              onPressed: _pickDateRange,
            ),
        ],
      ),
      body: Consumer<ReportsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profile?.isAdmin == true) {
            return _AdminReportView(
              data: provider.adminReport,
              startDate: _startDate,
              endDate: _endDate,
              onRefresh: _loadReport,
              onPickDate: _pickDateRange,
            );
          } else if (profile?.isManager == true) {
            return _ManagerReportView(
              data: provider.managerReport,
              startDate: _startDate,
              endDate: _endDate,
              onRefresh: _loadReport,
              onPickDate: _pickDateRange,
            );
          } else {
            return _EmployeeReportView(
              data: provider.employeeReport,
              onRefresh: _loadReport,
            );
          }
        },
      ),
    );
  }
}

// ─── Employee Report View ─────────────────────────────────────

class _EmployeeReportView extends StatelessWidget {
  final Map<String, dynamic>? data;
  final Future<void> Function() onRefresh;

  const _EmployeeReportView({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data == null) {
      return const Center(child: Text('No report data available.'));
    }

    final total = data!['total_assigned'] as int? ?? 0;
    final approved = data!['approved_count'] as int? ?? 0;
    final rejected = data!['rejected_count'] as int? ?? 0;
    final pending = data!['pending_count'] as int? ?? 0;
    final completionRate = (data!['completion_rate'] as num?)?.toDouble() ?? 0.0;
    final points = data!['lifetime_points'] as int? ?? 0;
    final badge = data!['badge_name'] as String? ?? 'No Badge';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge and Points Summary
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.emoji_events, color: Colors.amber.shade800, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$badge Badge Tier', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                                const SizedBox(height: 2),
                                Text('$points Total Lifetime Points Earned', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Task Completion Rate Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Task Completion Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(
                                '${completionRate.toStringAsFixed(1)}%',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (completionRate / 100).clamp(0.0, 1.0),
                              minHeight: 10,
                              backgroundColor: cs.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Task Count Metrics
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(label: 'Assigned', value: '$total', color: Colors.blueGrey, icon: Icons.assignment_outlined),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatBox(label: 'Approved', value: '$approved', color: Colors.green, icon: Icons.verified_outlined),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatBox(label: 'Rejected', value: '$rejected', color: Colors.red, icon: Icons.cancel_outlined),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatBox(label: 'Pending', value: '$pending', color: Colors.orange, icon: Icons.hourglass_empty),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Manager Report View ──────────────────────────────────────

class _ManagerReportView extends StatelessWidget {
  final Map<String, dynamic>? data;
  final DateTime startDate;
  final DateTime endDate;
  final Future<void> Function() onRefresh;
  final VoidCallback onPickDate;

  const _ManagerReportView({
    required this.data,
    required this.startDate,
    required this.endDate,
    required this.onRefresh,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd MMM yyyy');

    if (data == null) {
      return const Center(child: Text('No report data available.'));
    }

    final totalSales = (data!['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalTarget = (data!['total_target'] as num?)?.toDouble() ?? 0.0;
    final achievement = (data!['achievement_rate'] as num?)?.toDouble() ?? 0.0;
    final shiftSales = (data!['shift_sales'] as Map<String, dynamic>?) ?? {};
    final employeeStats = (data!['employee_stats'] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date range selector bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${dateFormatter.format(startDate)} – ${dateFormatter.format(endDate)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        TextButton(onPressed: onPickDate, child: const Text('Change Dates')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Branch Sales vs Target Card
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Branch Sales vs Target', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: achievement >= 100 ? Colors.green.withValues(alpha: 0.15) : cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${achievement.toStringAsFixed(1)}% Achieved',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: achievement >= 100 ? Colors.green : cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Actual Revenue', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                                    const SizedBox(height: 2),
                                    Text('৳${currency.format(totalSales)}',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Target Goal', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                                    const SizedBox(height: 2),
                                    Text('৳${currency.format(totalTarget)}',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Shift Performance Breakdown
                  const Text('Sales by Shift', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (shiftSales.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No shift sales in this range.')))
                  else
                    ...shiftSales.entries.map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.schedule, color: cs.primary),
                            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Text(
                              '৳${currency.format(e.value)}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.primary),
                            ),
                          ),
                        )),
                  const SizedBox(height: 20),

                  // Employee Task Completion Leaderboard
                  const Text('Staff Task Completion Metrics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (employeeStats.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No staff assignments found.')))
                  else
                    ...employeeStats.entries.map((e) {
                      final stats = e.value as Map<String, dynamic>;
                      final approved = stats['approved'] as int? ?? 0;
                      final total = stats['total'] as int? ?? 0;
                      final rate = total > 0 ? (approved / total * 100).toStringAsFixed(0) : '0';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Text(e.key.isNotEmpty ? e.key[0].toUpperCase() : 'E'),
                          ),
                          title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('$approved approved out of $total assigned'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Text('$rate% Done', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Admin Report View ────────────────────────────────────────

class _AdminReportView extends StatelessWidget {
  final Map<String, dynamic>? data;
  final DateTime startDate;
  final DateTime endDate;
  final Future<void> Function() onRefresh;
  final VoidCallback onPickDate;

  const _AdminReportView({
    required this.data,
    required this.startDate,
    required this.endDate,
    required this.onRefresh,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd MMM yyyy');

    if (data == null) {
      return const Center(child: Text('No organization report data available.'));
    }

    final totalOrgSales = (data!['total_org_sales'] as num?)?.toDouble() ?? 0.0;
    final totalTx = data!['total_transactions'] as int? ?? 0;
    final totalUsers = data!['total_users'] as int? ?? 0;
    final activeUsers = data!['active_users'] as int? ?? 0;
    final branchSales = (data!['branch_sales'] as Map<String, dynamic>?) ?? {};
    final badgeDistribution = (data!['badge_distribution'] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date range selector bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${dateFormatter.format(startDate)} – ${dateFormatter.format(endDate)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        TextButton(onPressed: onPickDate, child: const Text('Change Dates')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Organization Totals
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Org Sales', style: TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  '৳${currency.format(totalOrgSales)}',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary),
                                ),
                                Text('$totalTx total transactions', style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Staff & Users', style: TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  '$activeUsers / $totalUsers',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                                ),
                                const Text('active accounts', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Branch Sales Comparison
                  const Text('Branch Revenue Comparison', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (branchSales.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No sales recorded in this timeframe.')))
                  else
                    ...branchSales.entries.map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.store, color: cs.primary),
                            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Text(
                              '৳${currency.format(e.value)}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.primary),
                            ),
                          ),
                        )),
                  const SizedBox(height: 20),

                  // Badge Distribution
                  const Text('Employee Badge Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _BadgeCount(name: 'Platinum', count: badgeDistribution['Platinum'] ?? 0, color: Colors.blueGrey),
                          _BadgeCount(name: 'Gold', count: badgeDistribution['Gold'] ?? 0, color: const Color(0xFFFFD700)),
                          _BadgeCount(name: 'Silver', count: badgeDistribution['Silver'] ?? 0, color: const Color(0xFFC0C0C0)),
                          _BadgeCount(name: 'Bronze', count: badgeDistribution['Bronze'] ?? 0, color: const Color(0xFFCD7F32)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatBox({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _BadgeCount extends StatelessWidget {
  final String name;
  final int count;
  final Color color;

  const _BadgeCount({required this.name, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.emoji_events, color: color, size: 24),
        const SizedBox(height: 4),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(name, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
