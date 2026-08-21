import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/shift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/shift_provider.dart';
import '../../widgets/loading_button.dart';

/// Manager screen for viewing and setting sales targets.
class SalesTargetScreen extends StatefulWidget {
  const SalesTargetScreen({super.key});

  @override
  State<SalesTargetScreen> createState() => _SalesTargetScreenState();
}

class _SalesTargetScreenState extends State<SalesTargetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  DateTime get _monthStart => _month;
  DateTime get _monthEnd =>
      DateTime(_month.year, _month.month + 1, 0);

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    final branchId = auth.profile!.branchId!;
    await Future.wait([
      context
          .read<SalesProvider>()
          .loadTargets(branchId, _monthStart, _monthEnd),
      context.read<ShiftProvider>().loadShifts(branchId),
    ]);
  }

  void _prevMonth() {
    setState(() =>
        _month = DateTime(_month.year, _month.month - 1));
    _loadData();
  }

  void _nextMonth() {
    setState(
        () => _month = DateTime(_month.year, _month.month + 1));
    _loadData();
  }

  void _openTargetForm({DateTime? forDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TargetFormSheet(initialDate: forDate ?? DateTime.now()),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monthFormatter = DateFormat('MMMM yyyy');
    final currency = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sales Targets',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer<SalesProvider>(
        builder: (context, salesProvider, _) {
          return RefreshIndicator(
            onRefresh: _loadData,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Month navigation
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: _prevMonth,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(
                              monthFormatter.format(_month),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                            IconButton(
                              onPressed: _nextMonth,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                      // Summary card
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.75),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Targets This Month',
                                style: TextStyle(
                                  color: colorScheme.onPrimary
                                      .withOpacity(0.8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '৳${currency.format(salesProvider.targets.fold(0.0, (s, t) => s + t.targetAmount))}',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${salesProvider.targets.length} target(s) set',
                                style: TextStyle(
                                  color: colorScheme.onPrimary
                                      .withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (salesProvider.isLoading &&
                    salesProvider.targets.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (salesProvider.targets.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.track_changes,
                              size: 56,
                              color: colorScheme.onSurface
                                  .withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text('No Targets Set',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface
                                      .withOpacity(0.5))),
                          const SizedBox(height: 4),
                          Text(
                              'Tap + to set a target for a date.',
                              style: TextStyle(
                                  color: colorScheme.onSurface
                                      .withOpacity(0.4))),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final target =
                              salesProvider.targets[index];
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: 760),
                              child: Card(
                                margin:
                                    const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8),
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color:
                                          colorScheme.primaryContainer,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                        Icons.track_changes,
                                        color: colorScheme.primary),
                                  ),
                                  title: Text(
                                    DateFormat('EEE, dd MMM yyyy')
                                        .format(target.targetDate),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                      target.shiftName ?? 'All shifts'),
                                  trailing: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '৳${currency.format(target.targetAmount)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                          fontSize: 15,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () =>
                                            _openTargetForm(
                                                forDate:
                                                    target.targetDate),
                                        child: Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontSize: 12,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: salesProvider.targets.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTargetForm(),
        icon: const Icon(Icons.add),
        label: const Text('Set Target'),
      ),
    );
  }
}

// ─── Target Form Sheet ────────────────────────────────────────

class _TargetFormSheet extends StatefulWidget {
  final DateTime initialDate;
  const _TargetFormSheet({required this.initialDate});

  @override
  State<_TargetFormSheet> createState() => _TargetFormSheetState();
}

class _TargetFormSheetState extends State<_TargetFormSheet> {
  late DateTime _date;
  Shift? _selectedShift;
  final _amountController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid target amount.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final auth = context.read<AuthProvider>();
    final branchId = auth.profile?.branchId;
    if (branchId == null) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<SalesProvider>().upsertTarget(
            branchId: branchId,
            shiftId: _selectedShift?.id,
            targetDate: _date,
            targetAmount: amount,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Target saved!'),
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

  InputDecoration _deco(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shifts = context.watch<ShiftProvider>().shifts;

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
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Set Sales Target',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.primary),
            ),
            const SizedBox(height: 20),
            // Date picker
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now()
                      .subtract(const Duration(days: 30)),
                  lastDate:
                      DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cs.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('EEE, dd MMM yyyy').format(_date),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (shifts.isNotEmpty)
              DropdownButtonFormField<Shift?>(
                value: _selectedShift,
                isExpanded: true,
                decoration:
                    _deco('Shift (optional)', Icons.schedule_outlined),
                hint: const Text('All shifts'),
                items: [
                  const DropdownMenuItem<Shift?>(
                      value: null, child: Text('All shifts')),
                  ...shifts.map((s) => DropdownMenuItem<Shift?>(
                        value: s,
                        child: Text(s.name,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (s) => setState(() => _selectedShift = s),
              ),
            if (shifts.isNotEmpty) const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco(
                  'Target Amount (৳)', Icons.attach_money_outlined),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Save Target',
              icon: Icons.save,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
