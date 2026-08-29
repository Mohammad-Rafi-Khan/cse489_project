import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/attendance.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';

/// A simple operational attendance screen for employee, manager, and admin views.
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
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;

    final provider = context.read<AttendanceProvider>();
    if (profile.isEmployee) {
      await provider.loadMyAttendance(profile.id);
    } else if (profile.isManager) {
      final branchId = profile.branchId;
      if (branchId != null) {
        await provider.loadBranchAttendance(branchId);
      }
    } else {
      await provider.loadAllAttendance();
    }
  }

  Future<void> _showStatusEditor(BuildContext context, Attendance attendance) async {
    final provider = context.read<AttendanceProvider>();
    String selectedStatus = attendance.status;
    final notesController = TextEditingController(text: attendance.notes ?? '');

    final didUpdate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Update attendance status'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'present', child: Text('Present')),
                      DropdownMenuItem(value: 'late', child: Text('Late')),
                      DropdownMenuItem(value: 'absent', child: Text('Absent')),
                      DropdownMenuItem(value: 'half_day', child: Text('Half Day')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Add a reason or override note',
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final note = notesController.text.trim();
                await provider.updateAttendanceStatus(
                  id: attendance.id,
                  status: selectedStatus,
                  notes: note.isEmpty ? null : note,
                );
                if (context.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (didUpdate == true && mounted) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<AttendanceProvider>(
        builder: (context, provider, _) {
          final list = profile.isEmployee
              ? provider.myAttendance
              : profile.isManager
                  ? provider.branchAttendance
                  : provider.allAttendance;

          if (provider.isLoading && list.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_outlined, size: 56, color: colorScheme.primary.withValues(alpha: 0.55)),
                    const SizedBox(height: 12),
                    const Text('No attendance records yet', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      profile.isEmployee
                          ? 'Check in to start your attendance history.'
                          : 'No records are available for this scope yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final attendance = list[index];
                final canEdit = !profile.isEmployee && (profile.isManager || profile.isAdmin);
                return _AttendanceCard(
                  attendance: attendance,
                  isEmployee: profile.isEmployee,
                  canEdit: canEdit,
                  onEdit: canEdit ? () => _showStatusEditor(context, attendance) : null,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: profile.isEmployee
          ? FloatingActionButton.extended(
              onPressed: () async {
                final provider = context.read<AttendanceProvider>();
                try {
                  final today = DateTime.now();
                  final existing = provider.myAttendance.firstWhere(
                    (item) => item.date.year == today.year && item.date.month == today.month && item.date.day == today.day,
                    orElse: () => Attendance(
                      id: '',
                      employeeId: profile.id,
                      branchId: profile.branchId ?? '',
                      date: today,
                      status: 'present',
                      createdAt: today,
                      updatedAt: today,
                    ),
                  );

                  if (existing.id.isEmpty || existing.checkInTime == null) {
                    await provider.checkInToday(
                      employeeId: profile.id,
                      branchId: profile.branchId ?? '',
                    );
                  } else if (existing.checkOutTime == null) {
                    await provider.checkOutToday(
                      employeeId: profile.id,
                      branchId: profile.branchId ?? '',
                    );
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Attendance updated successfully.')),
                  );
                  await _loadData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Attendance update failed: $e')),
                  );
                }
              },
              icon: const Icon(Icons.fingerprint),
              label: const Text('Check In / Out'),
            )
          : null,
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final Attendance attendance;
  final bool isEmployee;
  final bool canEdit;
  final VoidCallback? onEdit;

  const _AttendanceCard({
    required this.attendance,
    required this.isEmployee,
    this.canEdit = false,
    this.onEdit,
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
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEmployee ? 'Attendance Record' : (attendance.employeeName ?? 'Employee'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    attendance.statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${attendance.date.day}/${attendance.date.month}/${attendance.date.year}',
              style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Check In: ${attendance.checkInTime ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Check Out: ${attendance.checkOutTime ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            if (!isEmployee) ...[
              const SizedBox(height: 6),
              Text(
                'Branch: ${attendance.branchName ?? 'Branch'}',
                style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ],
            if (attendance.notes != null && attendance.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Note: ${attendance.notes!.trim()}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (canEdit) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_note_outlined),
                  tooltip: 'Edit attendance status',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
