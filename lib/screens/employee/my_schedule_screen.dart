import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/employee_shift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shift_provider.dart';
import '../../widgets/empty_state.dart';

/// Displays the logged-in employee's upcoming shifts within the next 7 days.
class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSchedule());
  }

  Future<void> _loadSchedule() async {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;

    await context.read<ShiftProvider>().loadMySchedule(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Schedule',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer<ShiftProvider>(
        builder: (context, shiftProvider, _) {
          final schedule = shiftProvider.mySchedule;

          if (shiftProvider.isLoading && schedule.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (shiftProvider.errorMessage != null && schedule.isEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Unable to load schedule',
              subtitle: shiftProvider.errorMessage,
              action: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadSchedule,
              ),
            );
          }

          if (schedule.isEmpty) {
            return EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No shifts scheduled',
              subtitle:
                  'You do not have any upcoming shifts in the next 7 days.',
              action: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                onPressed: _loadSchedule,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadSchedule,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: schedule.length,
              itemBuilder: (context, index) {
                final shift = schedule[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _ScheduleCard(shift: shift),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final EmployeeShift shift;

  const _ScheduleCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateLabel = DateFormat('EEE, MMM d').format(shift.workDate);
    final start = shift.shiftStartTime ?? '--:--';
    final end = shift.shiftEndTime ?? '--:--';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.schedule_outlined, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shift.shiftName ?? 'Shift',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$start - $end',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Scheduled',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
