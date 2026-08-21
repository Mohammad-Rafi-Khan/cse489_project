import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/employee_shift.dart';
import '../../models/shift.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shift_provider.dart';
import '../../widgets/loading_button.dart';

/// Manager screen for defining shifts and scheduling employees.
class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    final branchId = auth.profile!.branchId!;
    await Future.wait([
      context.read<ShiftProvider>().loadAllShifts(branchId),
      context.read<ShiftProvider>().loadBranchEmployees(branchId),
    ]);
  }

  void _openShiftForm({Shift? shift}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShiftFormSheet(shift: shift),
    ).then((_) {
      // Pre-read context-dependent values before the async gap
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final branchId = auth.profile?.branchId;
      if (branchId != null) {
        context.read<ShiftProvider>().loadAllShifts(branchId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Shift Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onPrimary.withValues(alpha: 0.6),
          indicatorColor: colorScheme.onPrimary,
          tabs: const [
            Tab(icon: Icon(Icons.schedule), text: 'Shifts'),
            Tab(icon: Icon(Icons.people_outline), text: 'Schedule'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ShiftsTab(onAdd: () => _openShiftForm()),
          const _ScheduleTab(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) => _tabController.index == 0
            ? FloatingActionButton.extended(
                onPressed: () => _openShiftForm(),
                icon: const Icon(Icons.add),
                label: const Text('New Shift'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

// ─── Shifts Tab ───────────────────────────────────────────────

class _ShiftsTab extends StatelessWidget {
  final VoidCallback onAdd;
  const _ShiftsTab({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<ShiftProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.allShifts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.allShifts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule,
                    size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text('No Shifts Yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 6),
                Text('Create shifts like "Morning" or "Evening".',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('New Shift'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: provider.allShifts.length,
          itemBuilder: (context, index) {
            final shift = provider.allShifts[index];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _ShiftCard(shift: shift),
              ),
            );
          },
        );
      },
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final Shift shift;
  const _ShiftCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: shift.isActive ? 1 : 0.6,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.schedule, color: cs.primary),
          ),
          title: Text(
            shift.name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration:
                  shift.isActive ? null : TextDecoration.lineThrough,
            ),
          ),
          subtitle: Text(shift.timeRange),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!shift.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Inactive',
                    style: TextStyle(
                        color: cs.onErrorContainer, fontSize: 11),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit shift',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _ShiftFormSheet(shift: shift),
                  ).then((_) {
                    if (!context.mounted) return;
                    final branchId = context.read<AuthProvider>().profile?.branchId;
                    if (branchId != null) {
                      context.read<ShiftProvider>().loadAllShifts(branchId);
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Schedule Tab ─────────────────────────────────────────────

class _ScheduleTab extends StatefulWidget {
  const _ScheduleTab();

  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadSchedule());
  }

  Future<void> _loadSchedule() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    await context
        .read<ShiftProvider>()
        .loadScheduleForDate(auth.profile!.branchId!, _selectedDate);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadSchedule();
    }
  }

  void _openAssignSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignShiftSheet(workDate: _selectedDate),
    ).then((_) => _loadSchedule());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFormatter = DateFormat('EEE, dd MMM yyyy');

    return Column(
      children: [
        // Date selector bar
        Container(
          color: cs.surfaceContainerLowest,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: cs.outline.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month,
                            size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          dateFormatter.format(_selectedDate),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Assign'),
                onPressed: _openAssignSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Consumer<ShiftProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.scheduleForDate.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (provider.scheduleForDate.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available,
                          size: 56,
                          color: cs.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('No Schedule',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface.withValues(alpha: 0.5))),
                      const SizedBox(height: 4),
                      Text('No employees scheduled for this date.',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.4))),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _loadSchedule,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: provider.scheduleForDate.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 760),
                        child: _ScheduleCard(
                          es: provider.scheduleForDate[index],
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
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final EmployeeShift es;
  const _ScheduleCard({required this.es});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            (es.employeeName ?? '?')[0].toUpperCase(),
            style: TextStyle(
                color: cs.primary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(es.employeeName ?? 'Employee',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(es.shiftName ?? 'Unknown Shift'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (es.shiftStartTime != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _fmtTime(es.shiftStartTime!),
                  style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove Schedule'),
                    content: Text(
                        'Remove ${es.employeeName ?? 'employee'} from ${es.shiftName ?? 'shift'}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Remove',
                              style: TextStyle(color: cs.error))),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await context
                      .read<ShiftProvider>()
                      .removeEmployeeShift(es.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }
}

// ─── Shift Form Sheet ─────────────────────────────────────────

class _ShiftFormSheet extends StatefulWidget {
  final Shift? shift;
  const _ShiftFormSheet({this.shift});

  @override
  State<_ShiftFormSheet> createState() => _ShiftFormSheetState();
}

class _ShiftFormSheetState extends State<_ShiftFormSheet> {
  final _nameController = TextEditingController();
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 16, minute: 0);
  bool _isActive = true;
  bool _isSubmitting = false;

  bool get _isEditing => widget.shift != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final s = widget.shift!;
      _nameController.text = s.name;
      _isActive = s.isActive;
      _startTime = _parseTime(s.startTime);
      _endTime = _parseTime(s.endTime);
    }
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  String _timeToStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Shift name is required.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final provider = context.read<ShiftProvider>();
      if (_isEditing) {
        await provider.updateShift(
          id: widget.shift!.id,
          name: name,
          startTime: _timeToStr(_startTime),
          endTime: _timeToStr(_endTime),
          isActive: _isActive,
        );
      } else {
        await provider.createShift(
          branchId: branchId,
          name: name,
          startTime: _timeToStr(_startTime),
          endTime: _timeToStr(_endTime),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? 'Shift updated!' : 'Shift created!'),
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

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEditing ? 'Edit Shift' : 'New Shift',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.primary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Shift Name *',
                hintText: 'e.g. Morning, Evening',
                prefixIcon: const Icon(Icons.schedule),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TimePickerCard(
                    label: 'Start Time',
                    time: _startTime.format(context),
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimePickerCard(
                    label: 'End Time',
                    time: _endTime.format(context),
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            if (_isEditing) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: _isEditing ? 'Save Changes' : 'Create Shift',
              icon: _isEditing ? Icons.save : Icons.add,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimePickerCard(
      {required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.primary, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 4),
          Text(time,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    );
  }
}

// ─── Assign Shift Sheet ───────────────────────────────────────

class _AssignShiftSheet extends StatefulWidget {
  final DateTime workDate;
  const _AssignShiftSheet({required this.workDate});

  @override
  State<_AssignShiftSheet> createState() => _AssignShiftSheetState();
}

class _AssignShiftSheetState extends State<_AssignShiftSheet> {
  UserProfile? _selectedEmployee;
  Shift? _selectedShift;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_selectedEmployee == null || _selectedShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select both employee and shift.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await context.read<ShiftProvider>().assignEmployeeToShift(
            employeeId: _selectedEmployee!.id,
            shiftId: _selectedShift!.id,
            workDate: widget.workDate,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${_selectedEmployee!.name} assigned to ${_selectedShift!.name}!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase().contains('unique')
            ? 'This employee is already assigned to this shift on this date.'
            : 'Failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _dropDeco(BuildContext ctx, String label, IconData icon) {
    final cs = Theme.of(ctx).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
      ),
      filled: true,
      fillColor: cs.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<ShiftProvider>();
    final dateStr =
        DateFormat('EEE, dd MMM yyyy').format(widget.workDate);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Assign to Shift',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.primary),
            ),
            const SizedBox(height: 4),
            Text(dateStr,
                style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 20),
            DropdownButtonFormField<UserProfile>(
              initialValue: _selectedEmployee,
              isExpanded: true,
              menuMaxHeight: 300,
              decoration:
                  _dropDeco(context, 'Employee', Icons.person_outline),
              hint: const Text('Select employee'),
              items: provider.branchEmployees
                  .map((e) => DropdownMenuItem<UserProfile>(
                        value: e,
                        child: Text(e.name,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (e) => setState(() => _selectedEmployee = e),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<Shift>(
              initialValue: _selectedShift,
              isExpanded: true,
              menuMaxHeight: 300,
              decoration: _dropDeco(
                  context, 'Shift', Icons.schedule_outlined),
              hint: const Text('Select shift'),
              items: provider.shifts
                  .map((s) => DropdownMenuItem<Shift>(
                        value: s,
                        child: Text('${s.name} (${s.timeRange})',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (s) => setState(() => _selectedShift = s),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Assign',
              icon: Icons.assignment_ind_outlined,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
