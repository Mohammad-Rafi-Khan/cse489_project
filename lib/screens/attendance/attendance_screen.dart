import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/attendance.dart';
import '../../models/user_profile.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';

/// Simple attendance view for employee check-in/out and scoped history.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;

    final provider = context.read<AttendanceProvider>();
    if (profile.isEmployee) {
      await provider.loadMyAttendance(profile.id);
      return;
    }
    if (profile.isManager) {
      final branchId = profile.branchId;
      if (branchId != null) {
        await provider.loadBranchAttendance(branchId);
      }
      return;
    }
    await provider.loadAllAttendance();
  }

  Future<void> _checkIn(UserProfile profile) async {
    final branchId = profile.branchId;
    if (branchId == null || branchId.trim().isEmpty) {
      _showMessage('Your profile is missing a branch.');
      return;
    }

    try {
      await context.read<AttendanceProvider>().checkInToday(
        employeeId: profile.id,
        branchId: branchId,
      );
      if (!mounted) return;
      _showMessage('Checked in successfully.');
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Check in failed: $error');
    }
  }

  Future<void> _checkOut(UserProfile profile) async {
    final branchId = profile.branchId;
    if (branchId == null || branchId.trim().isEmpty) {
      _showMessage('Your profile is missing a branch.');
      return;
    }

    try {
      await context.read<AttendanceProvider>().checkOutToday(
        employeeId: profile.id,
        branchId: branchId,
      );
      if (!mounted) return;
      _showMessage('Checked out successfully.');
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Check out failed: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = context.watch<AuthProvider>().profile;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<AttendanceProvider>(
        builder: (context, provider, _) {
          final records = profile.isEmployee
              ? provider.myAttendance
              : profile.isManager
              ? provider.branchAttendance
              : provider.allAttendance;
          final today = DateTime.now();
          final todayRecords = records
              .where((record) => _sameDay(record.date, today))
              .toList();
          final historyRecords = profile.isEmployee
              ? records
              : records
                    .where((record) => !_sameDay(record.date, today))
                    .toList();
          final todayRecord = profile.isEmployee
              ? _todayRecord(records, profile.id, today)
              : null;

          if (provider.isLoading && records.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (profile.isEmployee) ...[
                  _EmployeeAttendanceActions(
                    todayRecord: todayRecord,
                    isLoading: provider.isLoading,
                    onCheckIn: () => _checkIn(profile),
                    onCheckOut: () => _checkOut(profile),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Attendance History',
                    subtitle: 'Your check-in and check-out records',
                  ),
                  const SizedBox(height: 10),
                  if (historyRecords.isEmpty)
                    const _InlineEmptyState(
                      message: 'No attendance records yet.',
                    )
                  else
                    ...historyRecords.map(
                      (attendance) => _AttendanceCard(
                        attendance: attendance,
                        showEmployee: false,
                        showBranch: false,
                      ),
                    ),
                ] else ...[
                  _AttendanceSummary(
                    records: todayRecords,
                    isAdmin: profile.isAdmin,
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: "Today's Attendance",
                    subtitle: 'Employees with check-in records today',
                  ),
                  const SizedBox(height: 10),
                  if (todayRecords.isEmpty)
                    const _InlineEmptyState(
                      message: 'No attendance records for today.',
                    )
                  else
                    ...todayRecords.map(
                      (attendance) => _AttendanceCard(
                        attendance: attendance,
                        showEmployee: true,
                        showBranch: profile.isAdmin,
                      ),
                    ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Attendance History',
                    subtitle: 'Previous attendance records',
                  ),
                  const SizedBox(height: 10),
                  if (historyRecords.isEmpty)
                    const _InlineEmptyState(
                      message: 'No historical attendance records.',
                    )
                  else
                    ...historyRecords.map(
                      (attendance) => _AttendanceCard(
                        attendance: attendance,
                        showEmployee: true,
                        showBranch: profile.isAdmin,
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Attendance? _todayRecord(
    List<Attendance> records,
    String employeeId,
    DateTime today,
  ) {
    for (final record in records) {
      if (record.employeeId == employeeId && _sameDay(record.date, today)) {
        return record;
      }
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _EmployeeAttendanceActions extends StatelessWidget {
  final Attendance? todayRecord;
  final bool isLoading;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _EmployeeAttendanceActions({
    required this.todayRecord,
    required this.isLoading,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final hasCheckedIn = todayRecord?.checkInTime != null;
    final hasCheckedOut = todayRecord?.checkOutTime != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Today',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 160,
                  child: FilledButton.icon(
                    onPressed: !isLoading && !hasCheckedIn ? onCheckIn : null,
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Check In'),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: OutlinedButton.icon(
                    onPressed: !isLoading && hasCheckedIn && !hasCheckedOut
                        ? onCheckOut
                        : null,
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Check Out'),
                  ),
                ),
              ],
            ),
            if (todayRecord != null) ...[
              const SizedBox(height: 12),
              Text(
                'Check In: ${todayRecord!.checkInTime ?? '-'}    Check Out: ${todayRecord!.checkOutTime ?? '-'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  final List<Attendance> records;
  final bool isAdmin;

  const _AttendanceSummary({required this.records, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final present = records
        .where((record) => record.status == 'present')
        .length;
    final late = records.where((record) => record.status == 'late').length;
    final checkedOut = records
        .where((record) => record.checkOutTime != null)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAdmin ? 'All Branches Today' : 'Branch Today',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryChip(label: 'Checked In', value: records.length),
                _SummaryChip(label: 'Present', value: present),
                _SummaryChip(label: 'Late', value: late),
                _SummaryChip(label: 'Checked Out', value: checkedOut),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String message;

  const _InlineEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.62)),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final Attendance attendance;
  final bool showEmployee;
  final bool showBranch;

  const _AttendanceCard({
    required this.attendance,
    required this.showEmployee,
    required this.showBranch,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (attendance.status) {
      'late' => Colors.orange,
      'absent' => Colors.red,
      'half_day' => Colors.amber,
      _ => Colors.green,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showEmployee
                        ? attendance.employeeName ?? 'Employee'
                        : 'Attendance Record',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    attendance.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _dateLabel(attendance.date),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(
                  'Check In: ${attendance.checkInTime ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Check Out: ${attendance.checkOutTime ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (showBranch) ...[
              const SizedBox(height: 6),
              Text(
                'Branch: ${attendance.branchName ?? 'Branch'}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
