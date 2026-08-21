import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_assignment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/empty_state.dart';

/// Displays all tasks assigned to the employee, with multi-attempt submission history,
/// camera/gallery photo proof upload, and status progression.
class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile == null) return;
    await context
        .read<TaskProvider>()
        .loadEmployeeAssignments(auth.profile!.id);
  }

  void _openCompletionSheet(TaskAssignment assignment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskCompletionSheet(assignment: assignment),
    ).then((_) => _loadTasks());
  }

  void _showAttemptsHistoryDialog(TaskAssignment assignment) {
    showDialog(
      context: context,
      builder: (_) => _AttemptsHistoryDialog(assignment: assignment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Tasks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: _filter == 'all',
                    onSelected: () => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Pending',
                    isSelected: _filter == 'pending',
                    onSelected: () => setState(() => _filter = 'pending'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Completed',
                    isSelected: _filter == 'completed',
                    onSelected: () => setState(() => _filter = 'completed'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Approved',
                    isSelected: _filter == 'approved',
                    onSelected: () => setState(() => _filter = 'approved'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Rejected',
                    isSelected: _filter == 'rejected',
                    onSelected: () => setState(() => _filter = 'rejected'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<TaskProvider>(
              builder: (context, taskProvider, _) {
                if (taskProvider.isLoading &&
                    taskProvider.employeeAssignments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                var assignments = taskProvider.employeeAssignments;
                if (_filter != 'all') {
                  assignments =
                      assignments.where((a) => a.status == _filter).toList();
                }

                if (assignments.isEmpty) {
                  return EmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No Tasks',
                    subtitle: _filter == 'all'
                        ? 'Your manager hasn\'t assigned any tasks to you yet.'
                        : 'No $_filter tasks found.',
                    action: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      onPressed: _loadTasks,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadTasks,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: assignments.length,
                    itemBuilder: (context, index) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _TaskCard(
                            assignment: assignments[index],
                            onComplete: assignments[index].status == 'pending' ||
                                    assignments[index].status == 'rejected'
                                ? () => _openCompletionSheet(assignments[index])
                                : null,
                            onViewHistory: assignments[index].completions.isNotEmpty
                                ? () => _showAttemptsHistoryDialog(assignments[index])
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Task Card ────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final TaskAssignment assignment;
  final VoidCallback? onComplete;
  final VoidCallback? onViewHistory;

  const _TaskCard({
    required this.assignment,
    this.onComplete,
    this.onViewHistory,
  });

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'completed':
        return Colors.blue;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return cs.error;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'approved':
        return Icons.verified_outlined;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, assignment.status);
    final dateFormatter = DateFormat('dd MMM yyyy');
    final timeFormatter = DateFormat('h:mm a');

    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(assignment.status), size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            assignment.statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    assignment.taskTitle ?? 'Task',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                statusBadge,
              ],
            ),
            if (assignment.taskDescription != null &&
                assignment.taskDescription!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                assignment.taskDescription!,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_outline, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${assignment.basePoints} pts base',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
                if (assignment.photoBonusPoints > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 14, color: Colors.teal.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '+${assignment.photoBonusPoints} pts photo bonus',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                if (assignment.photoRequired)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 14, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Photo proof required',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Scheduled',
                  value: dateFormatter.format(assignment.scheduledDate),
                ),
                if (assignment.dueAt != null)
                  _InfoRow(
                    icon: Icons.access_time_outlined,
                    label: 'Due',
                    value: timeFormatter.format(assignment.dueAt!.toLocal()),
                  ),
              ],
            ),
            // Rejection reason on latest attempt
            if (assignment.status == 'rejected' &&
                assignment.reviewNote != null &&
                assignment.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: colorScheme.onErrorContainer),
                        const SizedBox(width: 6),
                        Text(
                          'Rejection Reason',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      assignment.reviewNote!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // View attempt history button if multiple attempts exist
            if (assignment.completions.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: onViewHistory,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'View ${assignment.completions.length} submission attempt(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (onComplete != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(assignment.status == 'rejected'
                      ? 'Resubmit Task with Revision'
                      : 'Mark as Complete & Submit Proof'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  onPressed: onComplete,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 125, maxWidth: 200),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: colorScheme.primary),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Task Completion Bottom Sheet with Camera & Gallery ───────

class _TaskCompletionSheet extends StatefulWidget {
  final TaskAssignment assignment;
  const _TaskCompletionSheet({required this.assignment});

  @override
  State<_TaskCompletionSheet> createState() => _TaskCompletionSheetState();
}

class _TaskCompletionSheetState extends State<_TaskCompletionSheet> {
  final _noteController = TextEditingController();
  XFile? _selectedImageFile;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final taskProvider = context.read<TaskProvider>();
    final file = await taskProvider.pickPhoto(source);
    if (file != null) {
      setState(() {
        _selectedImageFile = file;
      });
    }
  }

  Future<void> _submit() async {
    final photoRequired = widget.assignment.photoRequired;
    final hasPhoto = _selectedImageFile != null;

    if (photoRequired && !hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo proof is required for this task. Please take or choose a photo.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    if (auth.profile == null) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<TaskProvider>().submitCompletion(
            assignmentId: widget.assignment.id,
            completionNote: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            photoFile: _selectedImageFile,
            userId: auth.profile!.id,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task submitted for manager approval!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoRequired = widget.assignment.photoRequired;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  Text(
                    'Complete Task',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.assignment.taskTitle ?? 'Task',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Photo proof section
                  Text(
                    photoRequired ? 'Photo Proof * (Required)' : 'Photo Proof (Optional +Bonus Pts)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: photoRequired ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Image Preview or Picker Buttons
                  if (_selectedImageFile != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: kIsWeb
                                ? Image.network(
                                    _selectedImageFile!.path,
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(_selectedImageFile!.path),
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedImageFile!.name,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                label: const Text('Remove', style: TextStyle(color: Colors.red)),
                                onPressed: () => setState(() => _selectedImageFile = null),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Camera'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _pickImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Gallery'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _pickImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Completion Note (optional)',
                      hintText: 'Describe actions taken or observations...',
                      prefixIcon: const Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _isSubmitting ? 'Uploading & Submitting...' : 'Submit for Approval',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSubmitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Attempts History Dialog ──────────────────────────────────

class _AttemptsHistoryDialog extends StatelessWidget {
  final TaskAssignment assignment;
  const _AttemptsHistoryDialog({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final attempts = assignment.completions;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.history, color: cs.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Submission Attempts')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: attempts.length,
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (context, index) {
            final attempt = attempts[index];
            final statusColor = attempt.isApproved
                ? Colors.green
                : (attempt.isRejected ? cs.error : Colors.blue);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attempt #${attempt.attemptNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        attempt.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Submitted: ${DateFormat('dd MMM yyyy, h:mm a').format(attempt.submittedAt.toLocal())}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                ),
                if (attempt.completionNote != null && attempt.completionNote!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Note: ${attempt.completionNote!}', style: const TextStyle(fontSize: 13)),
                ],
                if (attempt.photoUrl != null && attempt.photoUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.photo_outlined, size: 14, color: cs.primary),
                      const SizedBox(width: 4),
                      Text('Photo attached', style: TextStyle(fontSize: 12, color: cs.primary)),
                    ],
                  ),
                ],
                if (attempt.reviewNote != null && attempt.reviewNote!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: attempt.isApproved ? Colors.green.withValues(alpha: 0.08) : cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Reviewer: ${attempt.reviewNote!}',
                      style: TextStyle(
                        fontSize: 12,
                        color: attempt.isApproved ? Colors.green.shade800 : cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
