import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task_assignment.dart';
import '../../models/task_completion.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/empty_state.dart';

/// Manager screen showing all task assignments for their branch,
/// supporting multi-attempt review, photo proof inspection, and atomic points approval.
class AssignedTasksScreen extends StatefulWidget {
  const AssignedTasksScreen({super.key});

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAssignments());
  }

  Future<void> _loadAssignments() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    await context.read<TaskProvider>().loadManagerAssignments(
      auth.profile!.branchId!,
    );
  }

  void _openReviewSheet(TaskAssignment assignment) {
    final latest = assignment.latestCompletion;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No submission attempt found to review.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(assignment: assignment, completion: latest),
    ).then((_) => _loadAssignments());
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
          'Assigned Tasks',
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
                  for (final f in [
                    ('all', 'All'),
                    ('pending', 'Pending'),
                    ('completed', 'Completed (Pending Review)'),
                    ('approved', 'Approved'),
                    ('rejected', 'Rejected'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: f.$2,
                        isSelected: _filter == f.$1,
                        onSelected: () => setState(() => _filter = f.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<TaskProvider>(
              builder: (context, taskProvider, _) {
                if (taskProvider.isLoading &&
                    taskProvider.managerAssignments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                var assignments = taskProvider.managerAssignments;
                if (_filter != 'all') {
                  assignments = assignments
                      .where((a) => a.status == _filter)
                      .toList();
                }

                if (assignments.isEmpty) {
                  return EmptyState(
                    icon: Icons.list_alt_outlined,
                    title: _filter == 'pending'
                        ? 'No Pending Tasks'
                        : 'No Assignments',
                    subtitle: 'Use "Assign Task" to create assignments.',
                    action: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      onPressed: _loadAssignments,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadAssignments,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: assignments.length,
                    itemBuilder: (context, index) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _AssignmentCard(
                            assignment: assignments[index],
                            onReview: assignments[index].status == 'completed'
                                ? () => _openReviewSheet(assignments[index])
                                : null,
                            onViewHistory:
                                assignments[index].completions.isNotEmpty
                                ? () => _showAttemptsHistoryDialog(
                                    assignments[index],
                                  )
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? cs.primary : cs.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? cs.onPrimary : cs.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Assignment Card ──────────────────────────────────────────

class _AssignmentCard extends StatelessWidget {
  final TaskAssignment assignment;
  final VoidCallback? onReview;
  final VoidCallback? onViewHistory;

  const _AssignmentCard({
    required this.assignment,
    this.onReview,
    this.onViewHistory,
  });

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'completed':
        return Colors.blue;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, assignment.status);
    final dateFormatter = DateFormat('dd MMM yyyy');
    final latest = assignment.latestCompletion;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    assignment.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    assignment.employeeName ?? 'Unknown Employee',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 5),
                Text(
                  dateFormatter.format(assignment.scheduledDate),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            // Latest attempt preview
            if (latest != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attempt #${latest.attemptNumber} Submission',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        if (latest.photoUrl != null &&
                            latest.photoUrl!.isNotEmpty)
                          InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => _PhotoPreviewDialog(
                                  photoUrl: latest.photoUrl!,
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Icon(Icons.image, size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'View Photo Proof',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (latest.completionNote != null &&
                        latest.completionNote!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        latest.completionNote!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            // View full attempts history
            if (assignment.completions.length > 1) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onViewHistory,
                child: Text(
                  'View all ${assignment.completions.length} attempts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
            if (onReview != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('Review Submission & Award Points'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  onPressed: onReview,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Photo Preview Dialog ─────────────────────────────────────

class _PhotoPreviewDialog extends StatelessWidget {
  final String photoUrl;
  const _PhotoPreviewDialog({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            title: const Text(
              'Photo Proof Evidence',
              style: TextStyle(fontSize: 16),
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Image.network(
            photoUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Failed to load image from storage.')),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Review Bottom Sheet ──────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final TaskAssignment assignment;
  final TaskCompletion completion;

  const _ReviewSheet({required this.assignment, required this.completion});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _noteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _act(bool approve) async {
    final note = _noteController.text.trim();
    if (!approve && note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please provide a rejection reason so the employee can revise.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final provider = context.read<TaskProvider>();
      if (approve) {
        await provider.approveAssignment(
          completionId: widget.completion.id,
          assignmentId: widget.assignment.id,
          reviewNote: note.isEmpty ? null : note,
          branchId: branchId,
        );
      } else {
        await provider.rejectAssignment(
          completionId: widget.completion.id,
          assignmentId: widget.assignment.id,
          reviewNote: note,
          branchId: branchId,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Task approved! Points successfully awarded.'
                  : 'Task rejected and returned for revision.',
            ),
            backgroundColor: approve ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Action failed: ${e.toString().replaceAll('Exception: ', '')}',
            ),
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
    final cs = Theme.of(context).colorScheme;
    final comp = widget.completion;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  Text(
                    'Review Task Submission',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.assignment.taskTitle ?? 'Task'} - Attempt #${comp.attemptNumber}',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (comp.photoUrl != null && comp.photoUrl!.isNotEmpty) ...[
                    Text(
                      'Photo Proof Evidence',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        comp.photoUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (comp.completionNote != null &&
                      comp.completionNote!.isNotEmpty) ...[
                    Text(
                      'Employee Note:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(comp.completionNote!),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Review Note (required for rejection)',
                      hintText: 'Add comments or reason for decision...',
                      prefixIcon: const Icon(Icons.comment_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text(
                            'Reject',
                            style: TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isSubmitting ? null : () => _act(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
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
                              : const Icon(Icons.check_circle),
                          label: Text(
                            _isSubmitting ? 'Saving...' : 'Approve & Award',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isSubmitting ? null : () => _act(true),
                        ),
                      ),
                    ],
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
          const Expanded(child: Text('Submission Attempts History')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: attempts.length,
          separatorBuilder: (_, _) => const Divider(height: 24),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (attempt.completionNote != null &&
                    attempt.completionNote!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${attempt.completionNote!}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
                if (attempt.reviewNote != null &&
                    attempt.reviewNote!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Review note: ${attempt.reviewNote!}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: attempt.isApproved
                          ? Colors.green.shade800
                          : cs.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
