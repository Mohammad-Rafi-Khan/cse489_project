import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';

/// Manager screen to create, view, and edit task templates.
/// Also provides the ability to auto-generate recurring assignments.
class TaskTemplateScreen extends StatefulWidget {
  const TaskTemplateScreen({super.key});

  @override
  State<TaskTemplateScreen> createState() => _TaskTemplateScreenState();
}

class _TaskTemplateScreenState extends State<TaskTemplateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    await context
        .read<TaskProvider>()
        .loadAllTaskTemplates(auth.profile!.branchId!);
  }

  void _openForm({Task? template}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateFormSheet(template: template),
    ).then((_) => _load());
  }

  void _openRecurringSheet(Task template) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringSheet(template: template),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Task Templates',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer<TaskProvider>(
        builder: (context, taskProvider, _) {
          if (taskProvider.isLoading &&
              taskProvider.allTaskTemplates.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final templates = taskProvider.allTaskTemplates;

          if (templates.isEmpty) {
            return EmptyState(
              icon: Icons.task_outlined,
              title: 'No Task Templates',
              subtitle: 'Create task templates to assign to employees.',
              action: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New Template'),
                onPressed: () => _openForm(),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _TemplateCard(
                      template: templates[index],
                      onEdit: () => _openForm(template: templates[index]),
                      onGenerate: () =>
                          _openRecurringSheet(templates[index]),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
    );
  }
}

// ─── Template Card ────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final Task template;
  final VoidCallback onEdit;
  final VoidCallback onGenerate;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onGenerate,
  });

  Color _freqColor(String freq) {
    switch (freq) {
      case 'weekly':
        return Colors.teal;
      case 'monthly':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final freqColor = _freqColor(template.frequency);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: template.isActive ? 1.0 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        decoration: template.isActive
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: freqColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      template.frequency.toUpperCase(),
                      style: TextStyle(
                        color: freqColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (!template.isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'INACTIVE',
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (template.description != null &&
                  template.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  template.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Badge(
                    icon: Icons.star_outline,
                    label: '${template.basePoints} pts base',
                    color: Colors.amber.shade700,
                  ),
                  if (template.photoBonusPoints > 0)
                    _Badge(
                      icon: Icons.add_a_photo_outlined,
                      label: '+${template.photoBonusPoints} pts bonus',
                      color: Colors.teal.shade700,
                    ),
                  if (template.photoRequired)
                    _Badge(
                      icon: Icons.camera_alt_outlined,
                      label: 'Photo required',
                      color: cs.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit Template'),
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.repeat, size: 16),
                      label: const Text('Auto-Generate'),
                      onPressed: template.isActive ? onGenerate : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Template Form Sheet ──────────────────────────────────────

class _TemplateFormSheet extends StatefulWidget {
  final Task? template;
  const _TemplateFormSheet({this.template});

  @override
  State<_TemplateFormSheet> createState() => _TemplateFormSheetState();
}

class _TemplateFormSheetState extends State<_TemplateFormSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _pointsController = TextEditingController();
  final _bonusPointsController = TextEditingController();
  String _frequency = 'daily';
  bool _photoRequired = false;
  bool _isActive = true;
  bool _isSubmitting = false;

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final t = widget.template!;
      _titleController.text = t.title;
      _descController.text = t.description ?? '';
      _pointsController.text = t.basePoints.toString();
      _bonusPointsController.text = t.photoBonusPoints.toString();
      _frequency = t.frequency;
      _photoRequired = t.photoRequired;
      _isActive = t.isActive;
    } else {
      _pointsController.text = '10';
      _bonusPointsController.text = '5';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _pointsController.dispose();
    _bonusPointsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Title is required.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final points = int.tryParse(_pointsController.text.trim()) ?? 10;
    final bonusPoints = int.tryParse(_bonusPointsController.text.trim()) ?? 5;

    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final provider = context.read<TaskProvider>();
      if (_isEditing) {
        await provider.updateTaskTemplate(
          id: widget.template!.id,
          title: title,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          frequency: _frequency,
          basePoints: points,
          photoBonusPoints: bonusPoints,
          photoRequired: _photoRequired,
          isActive: _isActive,
        );
      } else {
        await provider.createTaskTemplate(
          title: title,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          frequency: _frequency,
          branchId: branchId,
          basePoints: points,
          photoBonusPoints: bonusPoints,
          photoRequired: _photoRequired,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing
              ? 'Template updated!'
              : 'Template created!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
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
                    _isEditing ? 'Edit Template' : 'New Task Template',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.primary),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      prefixIcon: const Icon(Icons.title),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      prefixIcon: const Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: InputDecoration(
                      labelText: 'Frequency',
                      prefixIcon: const Icon(Icons.repeat),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(
                          value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                          value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (v) =>
                        setState(() => _frequency = v ?? 'daily'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pointsController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Base Points',
                            prefixIcon: const Icon(Icons.star_outline),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bonusPointsController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Photo Bonus',
                            prefixIcon: const Icon(Icons.add_a_photo_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    title: const Text('Photo Proof Required'),
                    subtitle: const Text(
                        'Employee must submit a verified photo to mark complete'),
                    value: _photoRequired,
                    onChanged: (v) => setState(() => _photoRequired = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_isEditing)
                    SwitchListTile(
                      title: const Text('Active Template'),
                      subtitle: const Text(
                          'Inactive templates won\'t appear in assignment forms'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 24),
                  LoadingButton(
                    label: _isEditing ? 'Save Changes' : 'Create Template',
                    icon: _isEditing ? Icons.save : Icons.add,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
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

// ─── Recurring Generation Sheet ───────────────────────────────

class _RecurringSheet extends StatefulWidget {
  final Task template;
  const _RecurringSheet({required this.template});

  @override
  State<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<_RecurringSheet> {
  DateTime? _fromDate = DateTime.now();
  DateTime? _toDate = DateTime.now().add(const Duration(days: 7));
  final Set<String> _selectedEmployeeIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmployees());
  }

  Future<void> _loadEmployees() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    await context
        .read<TaskProvider>()
        .loadBranchEmployees(auth.profile!.branchId!);
  }

  List<DateTime> _buildDateList() {
    if (_fromDate == null || _toDate == null) return [];
    final dates = <DateTime>[];
    var d = _fromDate!;
    while (!d.isAfter(_toDate!)) {
      dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    return dates;
  }

  Future<void> _submit() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a date range.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_selectedEmployeeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one employee.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final dates = _buildDateList();
    setState(() => _isSubmitting = true);
    try {
      final createdCount = await context.read<TaskProvider>().generateRecurringAssignments(
            taskId: widget.template.id,
            userIds: _selectedEmployeeIds.toList(),
            dates: dates,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$createdCount assignment(s) created! (Duplicates skipped automatically)'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final employees = context.watch<TaskProvider>().branchEmployees;
    final dates = _buildDateList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
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
                    'Auto-Generate Recurring Tasks',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.template.title,
                    style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 24),
                  // Date range
                  const Text('Date Range',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerCard(
                          label: 'From Date',
                          date: _fromDate,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _fromDate ?? DateTime.now(),
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 30)),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                            );
                            if (d != null) setState(() => _fromDate = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DatePickerCard(
                          label: 'To Date',
                          date: _toDate,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _toDate ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: _fromDate ?? DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                            );
                            if (d != null) setState(() => _toDate = d);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (dates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${dates.length} day(s) selected',
                        style: TextStyle(
                            fontSize: 12, color: cs.primary),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Employees
                  const Text('Select Employees to Schedule',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (employees.isEmpty)
                    const Text('No branch employees found.')
                  else
                    ...employees.map((e) => CheckboxListTile(
                          title: Text(e.name),
                          subtitle: Text(e.email),
                          value: _selectedEmployeeIds.contains(e.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedEmployeeIds.add(e.id);
                              } else {
                                _selectedEmployeeIds.remove(e.id);
                              }
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        )),
                  const SizedBox(height: 20),
                  if (_selectedEmployeeIds.isNotEmpty && dates.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Will schedule ${dates.length * _selectedEmployeeIds.length} occurrences '
                        '(${_selectedEmployeeIds.length} employees × ${dates.length} days)',
                        style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 24),
                  LoadingButton(
                    label: 'Generate Assignments',
                    icon: Icons.auto_awesome,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
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

class _DatePickerCard extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DatePickerCard(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: date != null
                ? cs.primary
                : cs.outline.withValues(alpha: 0.5),
            width: date != null ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 4),
            Text(
              date != null
                  ? '${date!.day}/${date!.month}/${date!.year}'
                  : 'Tap to pick',
              style: TextStyle(
                  fontWeight:
                      date != null ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
