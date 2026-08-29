import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';

/// Manager screen to create, view, and edit task templates.
/// Templates are reusable task definitions that a manager can later assign
/// to employees manually via the Assign Task screen.
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
    await context.read<TaskProvider>().loadAllTaskTemplates(
      auth.profile!.branchId!,
    );
  }

  void _openForm({Task? template}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateFormSheet(template: template),
    ).then((_) => _load());
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
          if (taskProvider.isLoading && taskProvider.allTaskTemplates.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final templates = taskProvider.allTaskTemplates;

          if (templates.isEmpty) {
            return EmptyState(
              icon: Icons.task_outlined,
              title: 'No Task Templates',
              subtitle:
                  'Create reusable task templates. Assign them to employees from the Assign Task screen.',
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

  const _TemplateCard({
    required this.template,
    required this.onEdit,
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
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                        horizontal: 8,
                        vertical: 4,
                      ),
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
                    label: '${template.ruleBasePoints} pts base',
                    color: Colors.amber.shade700,
                  ),
                  if (template.photoRequired)
                    _Badge(
                      icon: Icons.add_a_photo_outlined,
                      label: '+${template.rulePhotoBonusPoints} pts bonus',
                      color: Colors.teal.shade700,
                    ),
                  if (template.photoRequired)
                    _Badge(
                      icon: Icons.camera_alt_outlined,
                      label: 'Photo required',
                      color: cs.primary,
                    ),
                  if (template.deadlineHoursAfterAssignment != null)
                    _Badge(
                      icon: Icons.schedule_outlined,
                      label: 'Due in ${template.deadlineHoursAfterAssignment}h',
                      color: Colors.deepOrange.shade700,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Template'),
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
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
  final _deadlineHoursController = TextEditingController();
  String _frequency = 'daily';
  bool _photoRequired = false;
  bool _isActive = true;
  bool _isSubmitting = false;

  bool get _isEditing => widget.template != null;

  int _basePointsForFrequency(String frequency) {
    return switch (frequency) {
      'weekly' => 30,
      'monthly' => 60,
      _ => 10,
    };
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final t = widget.template!;
      _titleController.text = t.title;
      _descController.text = t.description ?? '';
      _pointsController.text = _basePointsForFrequency(t.frequency).toString();
      _bonusPointsController.text = '5';
      _deadlineHoursController.text =
          t.deadlineHoursAfterAssignment?.toString() ?? '';
      _frequency = t.frequency;
      _photoRequired = t.photoRequired;
      _isActive = t.isActive;
    } else {
      _pointsController.text = _basePointsForFrequency(_frequency).toString();
      _bonusPointsController.text = '5';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _pointsController.dispose();
    _bonusPointsController.dispose();
    _deadlineHoursController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title is required.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final points = _basePointsForFrequency(_frequency);
    const bonusPoints = 5;
    final deadlineText = _deadlineHoursController.text.trim();
    final deadlineHours = deadlineText.isEmpty
        ? null
        : int.tryParse(deadlineText);
    if (deadlineText.isNotEmpty &&
        (deadlineHours == null || deadlineHours <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deadline hours must be a positive number.'),
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
          deadlineHoursAfterAssignment: deadlineHours,
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
          deadlineHoursAfterAssignment: deadlineHours,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Template updated!' : 'Template created!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed. Please try again.'),
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
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Templates are reusable task definitions. Use the Assign Task screen to assign them to employees.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      prefixIcon: const Icon(Icons.title),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: InputDecoration(
                      labelText: 'Frequency (label only)',
                      prefixIcon: const Icon(Icons.repeat),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _frequency = v ?? 'daily';
                      _pointsController.text = _basePointsForFrequency(
                        _frequency,
                      ).toString();
                      _bonusPointsController.text = '5';
                    }),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _deadlineHoursController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Deadline Hours After Assignment',
                      hintText: 'Optional',
                      prefixIcon: const Icon(Icons.schedule_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pointsController,
                          readOnly: true,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Base Points (Auto)',
                            prefixIcon: const Icon(Icons.star_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bonusPointsController,
                          readOnly: true,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Photo Bonus (Auto)',
                            prefixIcon: const Icon(Icons.add_a_photo_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    title: const Text('Photo Proof Required'),
                    subtitle: const Text(
                      'Employee must submit a verified photo to mark complete',
                    ),
                    value: _photoRequired,
                    onChanged: (v) => setState(() => _photoRequired = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_isEditing)
                    SwitchListTile(
                      title: const Text('Active Template'),
                      subtitle: const Text(
                        'Inactive templates won\'t appear in the assignment form',
                      ),
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
