import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/loading_button.dart';

/// Screen for managers to assign a task to a branch employee.
class AssignTaskScreen extends StatefulWidget {
  const AssignTaskScreen({super.key});

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  Task? _selectedTask;
  UserProfile? _selectedEmployee;
  DateTime? _scheduledDate;
  TimeOfDay? _dueTime;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    final branchId = auth.profile!.branchId!;

    await Future.wait([
      context.read<TaskProvider>().loadTaskTemplates(branchId),
      context.read<TaskProvider>().loadBranchEmployees(branchId),
    ]);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _scheduledDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _dueTime = picked);
    }
  }

  Future<void> _submit() async {
    if (_selectedTask == null) {
      _showError('Please select a task.');
      return;
    }
    if (_selectedEmployee == null) {
      _showError('Please select an employee.');
      return;
    }
    if (_scheduledDate == null) {
      _showError('Please select a scheduled date.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      DateTime? dueAt;
      if (_dueTime != null) {
        dueAt = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          _dueTime!.hour,
          _dueTime!.minute,
        );
      }

      await context.read<TaskProvider>().assignTask(
        taskId: _selectedTask!.id,
        userId: _selectedEmployee!.id,
        scheduledDate: _scheduledDate!,
        dueAt: dueAt,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Task "${_selectedTask!.title}" assigned to ${_selectedEmployee!.name}!',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() {
        _selectedTask = null;
        _selectedEmployee = null;
        _scheduledDate = null;
        _dueTime = null;
      });
    } catch (_) {
      if (mounted) {
        _showError('Failed to assign task. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormatter = DateFormat('EEE, dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Assign Task',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer<TaskProvider>(
        builder: (context, taskProvider, _) {
          if (taskProvider.isLoading && taskProvider.taskTemplates.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(
                        icon: Icons.task_outlined,
                        title: 'Select Task',
                      ),
                      const SizedBox(height: 8),
                      taskProvider.taskTemplates.isEmpty
                          ? _EmptyDropdownCard(
                              message:
                                  'No task templates found for your branch.',
                              onRetry: _loadData,
                            )
                          : DropdownButtonFormField<Task>(
                              initialValue: _selectedTask,
                              isExpanded: true,
                              itemHeight: 64,
                              menuMaxHeight: 340,
                              decoration: _dropdownDecoration(
                                context,
                                'Task Template',
                                Icons.task_outlined,
                              ),
                              hint: const Text(
                                'Choose a task',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selectedItemBuilder: (context) => taskProvider
                                  .taskTemplates
                                  .map(
                                    (t) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              items: taskProvider.taskTemplates
                                  .map(
                                    (t) => DropdownMenuItem<Task>(
                                      value: t,
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              t.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              t.frequency.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (task) =>
                                  setState(() => _selectedTask = task),
                            ),
                      const SizedBox(height: 24),
                      const _SectionHeader(
                        icon: Icons.person_outlined,
                        title: 'Select Employee',
                      ),
                      const SizedBox(height: 8),
                      taskProvider.branchEmployees.isEmpty
                          ? _EmptyDropdownCard(
                              message:
                                  'No active employees found in your branch.',
                              onRetry: _loadData,
                            )
                          : DropdownButtonFormField<UserProfile>(
                              initialValue: _selectedEmployee,
                              isExpanded: true,
                              menuMaxHeight: 340,
                              decoration: _dropdownDecoration(
                                context,
                                'Employee',
                                Icons.person_outlined,
                              ),
                              hint: const Text(
                                'Choose an employee',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              items: taskProvider.branchEmployees
                                  .map(
                                    (e) => DropdownMenuItem<UserProfile>(
                                      value: e,
                                      child: Text(
                                        e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (employee) =>
                                  setState(() => _selectedEmployee = employee),
                            ),
                      const SizedBox(height: 24),
                      const _SectionHeader(
                        icon: Icons.calendar_today_outlined,
                        title: 'Schedule',
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 430;
                          final dateCard = _PickerCard(
                            icon: Icons.calendar_month_outlined,
                            label: 'Scheduled Date',
                            value: _scheduledDate != null
                                ? dateFormatter.format(_scheduledDate!)
                                : 'Tap to select',
                            hasValue: _scheduledDate != null,
                            onTap: _pickDate,
                          );
                          final timeCard = _PickerCard(
                            icon: Icons.access_time_outlined,
                            label: 'Due Time',
                            value: _dueTime != null
                                ? _dueTime!.format(context)
                                : 'Optional',
                            hasValue: _dueTime != null,
                            onTap: _pickTime,
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: dateCard,
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: timeCard,
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: dateCard),
                              const SizedBox(width: 12),
                              Expanded(child: timeCard),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      if (_selectedTask != null &&
                          _selectedEmployee != null &&
                          _scheduledDate != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assignment Summary',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _SummaryRow(
                                label: 'Task',
                                value: _selectedTask!.title,
                              ),
                              _SummaryRow(
                                label: 'Employee',
                                value: _selectedEmployee!.name,
                              ),
                              _SummaryRow(
                                label: 'Date',
                                value: dateFormatter.format(_scheduledDate!),
                              ),
                              if (_dueTime != null)
                                _SummaryRow(
                                  label: 'Due Time',
                                  value: _dueTime!.format(context),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      LoadingButton(
                        label: 'Assign Task',
                        icon: Icons.assignment_turned_in_outlined,
                        isLoading: _isSubmitting,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _dropdownDecoration(
    BuildContext context,
    String label,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool hasValue;
  final VoidCallback onTap;

  const _PickerCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasValue
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.5),
            width: hasValue ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: hasValue
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                color: hasValue
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDropdownCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _EmptyDropdownCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
