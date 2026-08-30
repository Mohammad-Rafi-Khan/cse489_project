import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/leave_request.dart';
import '../../providers/auth_provider.dart';
import '../../providers/leave_provider.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLeaves());
  }

  Future<void> _loadLeaves() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;

    final leaveProvider = context.read<LeaveProvider>();
    if (profile.isEmployee) {
      await leaveProvider.loadMyLeaves(profile.id);
      return;
    }
    if (profile.isManager) {
      final branchId = profile.branchId;
      if (branchId != null) {
        await leaveProvider.loadBranchLeaves(branchId);
      }
      return;
    }
    if (profile.isAdmin) {
      await leaveProvider.loadCompanyLeaves();
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submitLeave() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null || !profile.isEmployee) return;
    if (!_formKey.currentState!.validate()) return;

    final branchId = profile.branchId;
    if (branchId == null || branchId.trim().isEmpty) {
      _showMessage('Your profile is missing a branch.');
      return;
    }

    try {
      await context.read<LeaveProvider>().createLeaveRequest(
        branchId: branchId,
        employeeId: profile.id,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      _reasonController.clear();
      _showMessage('Leave request submitted.');
      await _loadLeaves();
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to submit leave request.');
      }
    }
  }

  Future<void> _reviewLeave(LeaveRequest request, String status) async {
    final leaveProvider = context.read<LeaveProvider>();
    final commentController = TextEditingController();
    final isApproval = status == 'approved';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isApproval ? 'Approve Leave' : 'Reject Leave'),
          content: TextField(
            controller: commentController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Manager comment'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isApproval ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      commentController.dispose();
      return;
    }

    try {
      final comment = commentController.text.trim();
      await leaveProvider.updateLeaveStatus(
        id: request.id,
        status: status,
        managerComment: comment.isEmpty ? null : comment,
      );
      if (!mounted) return;
      _showMessage(isApproval ? 'Leave approved.' : 'Leave rejected.');
      await _loadLeaves();
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to update leave request.');
      }
    } finally {
      commentController.dispose();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = context.watch<AuthProvider>().profile;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final title = profile.isEmployee
        ? 'Request Leave'
        : profile.isManager
        ? 'Leave Approval'
        : 'Leave Requests';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<LeaveProvider>(
        builder: (context, provider, _) {
          final requests = provider.requests;
          if (provider.isLoading && requests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _loadLeaves,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (profile.isEmployee) ...[
                  _LeaveForm(
                    formKey: _formKey,
                    reasonController: _reasonController,
                    startDate: _startDate,
                    endDate: _endDate,
                    isSubmitting: provider.isLoading,
                    onPickStart: () => _pickDate(isStart: true),
                    onPickEnd: () => _pickDate(isStart: false),
                    onSubmit: _submitLeave,
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle(title: 'Leave History'),
                ] else ...[
                  _ReviewSummary(requests: requests),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    title: profile.isManager
                        ? 'Branch Employee Requests'
                        : 'All Leave Requests',
                  ),
                ],
                const SizedBox(height: 10),
                if (requests.isEmpty)
                  const _InlineEmptyState(message: 'No leave requests found.')
                else
                  ...requests.map(
                    (request) => _LeaveRequestCard(
                      request: request,
                      showEmployee: !profile.isEmployee,
                      showBranch: profile.isAdmin,
                      canReview: profile.isManager && request.isPending,
                      onApprove: () => _reviewLeave(request, 'approved'),
                      onReject: () => _reviewLeave(request, 'rejected'),
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

class _LeaveForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController reasonController;
  final DateTime startDate;
  final DateTime endDate;
  final bool isSubmitting;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onSubmit;

  const _LeaveForm({
    required this.formKey,
    required this.reasonController,
    required this.startDate,
    required this.endDate,
    required this.isSubmitting,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Request Leave',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onPickStart,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Start date'),
                  child: Text(_dateLabel(startDate)),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: onPickEnd,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'End date'),
                  child: Text(_dateLabel(endDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Please provide a reason'
                    : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Submit Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  final List<LeaveRequest> requests;

  const _ReviewSummary({required this.requests});

  @override
  Widget build(BuildContext context) {
    final pending = requests.where((request) => request.isPending).length;
    final approved = requests.where((request) => request.isApproved).length;
    final rejected = requests.where((request) => request.isRejected).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryChip(label: 'Pending', value: pending),
            _SummaryChip(label: 'Approved', value: approved),
            _SummaryChip(label: 'Rejected', value: rejected),
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

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

class _LeaveRequestCard extends StatelessWidget {
  final LeaveRequest request;
  final bool showEmployee;
  final bool showBranch;
  final bool canReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _LeaveRequestCard({
    required this.request,
    required this.showEmployee,
    required this.showBranch,
    required this.canReview,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = request.isApproved
        ? Colors.green
        : request.isRejected
        ? Colors.red
        : Colors.orange;

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
                        ? request.employeeName ?? 'Employee'
                        : request.reason,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 2,
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
                    request.statusLabel,
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
            if (showEmployee) ...[
              Text(
                request.reason,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              '${_dateLabel(request.startDate)} to ${_dateLabel(request.endDate)}',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            if (showBranch) ...[
              const SizedBox(height: 6),
              Text(
                'Branch: ${request.branchName ?? 'Branch'}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ],
            if (request.managerComment != null &&
                request.managerComment!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Manager comment: ${request.managerComment!.trim()}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.76),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (canReview) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
