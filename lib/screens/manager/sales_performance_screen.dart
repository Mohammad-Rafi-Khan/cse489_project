import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_provider.dart';

/// Manager screen for comparing actual sales against targets,
/// showing summary KPI cards, progress bars, and shift performance.
class SalesPerformanceScreen extends StatefulWidget {
  const SalesPerformanceScreen({super.key});

  @override
  State<SalesPerformanceScreen> createState() => _SalesPerformanceScreenState();
}

class _SalesPerformanceScreenState extends State<SalesPerformanceScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPerformance());
  }

  Future<void> _loadPerformance() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile?.branchId == null) return;
    final branchId = auth.profile!.branchId!;

    final salesProvider = context.read<SalesProvider>();
    await Future.wait([
      salesProvider.loadTargets(branchId, _startDate, _endDate),
      salesProvider.loadImportsForRange(branchId, _startDate, _endDate),
      salesProvider.loadPerformanceForRange(branchId, _startDate, _endDate),
    ]);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadPerformance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sales Performance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Filter Date Range',
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: Consumer<SalesProvider>(
        builder: (context, salesProvider, _) {
          if (salesProvider.isLoading &&
              salesProvider.rangeImports.isEmpty &&
              salesProvider.targets.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final totalActual = salesProvider.rangePerformance.fold<double>(
            0.0,
            (sum, row) => sum + ((row['actual'] as num?)?.toDouble() ?? 0),
          );
          final totalTarget = salesProvider.rangePerformance.fold<double>(
            0.0,
            (sum, row) => sum + ((row['target'] as num?)?.toDouble() ?? 0),
          );

          final progress = totalTarget > 0 ? (totalActual / totalTarget) : 0.0;
          final percent = (progress * 100).clamp(0, 999).toStringAsFixed(1);
          final shiftPerf = salesProvider.performanceByShift;

          return RefreshIndicator(
            onRefresh: _loadPerformance,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Date range chip banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${dateFormatter.format(_startDate)} - ${dateFormatter.format(_endDate)}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _pickDateRange,
                                child: const Text('Change'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Performance Target vs Actual Progress Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Target vs Actual Sales',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: progress >= 1.0
                                            ? Colors.green.withValues(
                                                alpha: 0.15,
                                              )
                                            : colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$percent% Target',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: progress >= 1.0
                                              ? Colors.green
                                              : colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: totalTarget > 0
                                        ? progress.clamp(0.0, 1.0)
                                        : 0.0,
                                    minHeight: 12,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress >= 1.0
                                          ? Colors.green
                                          : colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _KpiMetric(
                                        label: 'Actual Sales',
                                        value:
                                            'BDT ${currency.format(totalActual)}',
                                        color: colorScheme.primary,
                                        icon: Icons.trending_up_rounded,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 48,
                                      color: colorScheme.outline.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    Expanded(
                                      child: _KpiMetric(
                                        label: 'Target Goal',
                                        value:
                                            'BDT ${currency.format(totalTarget)}',
                                        color: Colors.deepOrange,
                                        icon: Icons.flag_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Shift Performance Breakdown
                        Text(
                          'Performance by Shift',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (shiftPerf.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'No imported sales data for this range.',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          ...shiftPerf.map((item) {
                            final shiftName = item['shift'] as String;
                            final amount = item['actual'] as double;
                            final shiftShare = totalActual > 0
                                ? (amount / totalActual)
                                : 0.0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.schedule_outlined,
                                                color: colorScheme.primary,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              shiftName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'BDT ${currency.format(amount)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: shiftShare.clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colorScheme.secondary,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${(shiftShare * 100).toStringAsFixed(1)}% of total sales',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),

                        const SizedBox(height: 20),

                        // Import Count & Summary
                        Text(
                          'Import Summary',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _SummaryStat(
                                  label: 'Imports',
                                  value: '${salesProvider.rangeImports.length}',
                                  icon: Icons.receipt_long_outlined,
                                ),
                                _SummaryStat(
                                  label: 'Avg Import',
                                  value: salesProvider.rangeImports.isNotEmpty
                                      ? 'BDT ${currency.format(totalActual / salesProvider.rangeImports.length)}'
                                      : 'BDT 0.00',
                                  icon: Icons.calculate_outlined,
                                ),
                                _SummaryStat(
                                  label: 'Targets Set',
                                  value: '${salesProvider.targets.length}',
                                  icon: Icons.track_changes_outlined,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _KpiMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _KpiMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
