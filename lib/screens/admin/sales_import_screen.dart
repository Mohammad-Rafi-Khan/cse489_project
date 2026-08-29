import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/branch.dart';
import '../../providers/branch_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/shift_provider.dart';
import '../../services/csv_sales_import_parser.dart';
import '../../widgets/loading_button.dart';

/// Admin-only CSV import workflow for branch-level sales data.
class SalesImportScreen extends StatefulWidget {
  const SalesImportScreen({super.key});

  @override
  State<SalesImportScreen> createState() => _SalesImportScreenState();
}

class _SalesImportScreenState extends State<SalesImportScreen> {
  final _csvController = TextEditingController();
  final _csvParser = CsvSalesImportParser();
  final List<CsvSalesImportRow> _validRows = [];
  final List<CsvSalesImportIssue> _failedRows = [];

  DateTime _saleDate = DateTime.now();
  String? _selectedBranchId;
  String? _selectedFileName;
  bool _hasValidated = false;
  bool _hasSaved = false;
  bool _isSubmitting = false;

  int get _totalRows => _validRows.length + _failedRows.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final branchProvider = context.read<BranchProvider>();
    await Future.wait([
      branchProvider.loadBranches(),
      context.read<ProductProvider>().loadProducts(),
    ]);
    if (!mounted) return;

    final activeBranches = branchProvider.activeBranches;
    final selectedIsActive = activeBranches.any(
      (branch) => branch.id == _selectedBranchId,
    );
    if (!selectedIsActive) {
      setState(() {
        _selectedBranchId = activeBranches.isNotEmpty
            ? activeBranches.first.id
            : null;
      });
    }
    await _loadBranchScopedData();
  }

  Future<void> _loadBranchScopedData() async {
    final branchId = _selectedBranchId;
    if (branchId == null) return;

    await Future.wait([
      context.read<ShiftProvider>().loadShifts(branchId),
      context.read<SalesProvider>().loadImportsForDate(branchId, _saleDate),
      context.read<SalesProvider>().loadImportFailuresForDate(
        branchId,
        _saleDate,
      ),
      context.read<SalesProvider>().loadTargets(branchId, _saleDate, _saleDate),
    ]);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _saleDate = picked;
      _clearValidation();
    });
    await _loadBranchScopedData();
  }

  Future<void> _pickCsvFile() async {
    const csvTypeGroup = XTypeGroup(
      label: 'CSV files',
      extensions: ['csv'],
      mimeTypes: ['text/csv', 'text/plain'],
    );

    try {
      final file = await openFile(acceptedTypeGroups: [csvTypeGroup]);
      if (file == null || !mounted) return;

      final contents = await file.readAsString();
      if (!mounted) return;

      setState(() {
        _csvController.text = contents;
        _selectedFileName = file.name;
        _clearValidation();
      });
      _showSnack('CSV file loaded.');
    } catch (_) {
      if (mounted) {
        _showSnack('Unable to read the selected CSV file.', isError: true);
      }
    }
  }

  void _validateCsv() {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      _showSnack('Select an active branch before validating.', isError: true);
      return;
    }

    final productsByName = {
      for (final product in context.read<ProductProvider>().activeProducts)
        product.name.toLowerCase(): product,
    };
    final shiftsByName = {
      for (final shift in context.read<ShiftProvider>().shifts)
        shift.name.toLowerCase(): shift,
    };

    final result = _csvParser.parse(
      _csvController.text,
      productsByName: productsByName,
      shiftsByName: shiftsByName,
    );

    setState(() {
      _validRows
        ..clear()
        ..addAll(result.validRows);
      _failedRows
        ..clear()
        ..addAll(result.failedRows);
      _hasValidated = true;
      _hasSaved = false;
    });
  }

  Future<void> _confirmImport() async {
    final branchId = _selectedBranchId;
    if (branchId == null || _validRows.isEmpty) {
      _showSnack(
        'Validate at least one valid row before importing.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    var savedCount = 0;
    final newFailures = <CsvSalesImportIssue>[];

    for (final row in _validRows) {
      try {
        await context.read<SalesProvider>().importSalesData(
          branchId: branchId,
          shiftId: row.shift?.id,
          saleDate: _saleDate,
          totalAmount: row.totalAmount,
          externalReference: row.reference,
          productId: row.product?.id,
          productQuantity: row.quantity,
        );
        savedCount++;
      } catch (error) {
        newFailures.add(
          CsvSalesImportIssue(
            rowNumber: row.rowNumber,
            rawLine: row.reference,
            reason: error.toString(),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _failedRows.addAll(newFailures);
      if (savedCount > 0) {
        _csvController.clear();
        _validRows.clear();
        _hasValidated = newFailures.isNotEmpty;
      }
      _hasSaved = savedCount > 0;
      _isSubmitting = false;
    });
    await _loadBranchScopedData();

    if (!mounted) return;
    _showSnack(
      savedCount == 1
          ? '1 CSV row imported.'
          : '$savedCount CSV rows imported.',
      isError: savedCount == 0,
    );
  }

  void _clearValidation() {
    _validRows.clear();
    _failedRows.clear();
    _hasValidated = false;
    _hasSaved = false;
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormatter = DateFormat('EEE, dd MMM yyyy');
    final currency = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sales Import',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      body: Consumer4<BranchProvider, ShiftProvider, ProductProvider, SalesProvider>(
        builder: (context, branchProvider, shiftProvider, productProvider, salesProvider, _) {
          final activeBranches = branchProvider.activeBranches;
          final selectedBranchValue =
              activeBranches.any((branch) => branch.id == _selectedBranchId)
              ? _selectedBranchId
              : null;

          return RefreshIndicator(
            onRefresh: _loadBranchScopedData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ImportSummary(
                          date: dateFormatter.format(_saleDate),
                          actual: salesProvider.totalActual,
                          target: salesProvider.totalTarget,
                        ),
                        const SizedBox(height: 16),
                        _WorkflowProgress(
                          hasCsv: _csvController.text.trim().isNotEmpty,
                          hasValidated: _hasValidated,
                          hasValidRows: _validRows.isNotEmpty,
                          isSaving: _isSubmitting,
                          hasSaved: _hasSaved,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CSV Batch',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBranchValue,
                          isExpanded: true,
                          decoration: _deco('Branch', Icons.store_outlined),
                          items: activeBranches
                              .map(
                                (Branch branch) => DropdownMenuItem<String>(
                                  value: branch.id,
                                  child: Text(branch.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            setState(() {
                              _selectedBranchId = value;
                              _clearValidation();
                            });
                            await _loadBranchScopedData();
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _deco(
                                    'Sales Date',
                                    Icons.calendar_month_outlined,
                                  ),
                                  child: Text(dateFormatter.format(_saleDate)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InputDecorator(
                                decoration: _deco(
                                  'Sales Source',
                                  Icons.upload_file_outlined,
                                ),
                                child: const Text('CSV Upload'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickCsvFile,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Choose CSV File'),
                        ),
                        if (_selectedFileName != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _selectedFileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _csvController,
                          minLines: 8,
                          maxLines: 12,
                          onChanged: (_) => setState(_clearValidation),
                          decoration:
                              _deco(
                                'CSV Data',
                                Icons.description_outlined,
                              ).copyWith(
                                alignLabelWithHint: true,
                                hintText:
                                    'batch_reference,total_amount,shift_name,product_name,quantity\n'
                                    'AUG-DHK-001,125000,Morning,Coca-Cola,48',
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${shiftProvider.shifts.length} shifts and '
                          '${productProvider.activeProducts.length} active analytics products available for validation.',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.62,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _validateCsv,
                          icon: const Icon(Icons.rule_folder_outlined),
                          label: const Text('Validate CSV'),
                        ),
                        if (_hasValidated) ...[
                          const SizedBox(height: 16),
                          _ValidationSummary(
                            totalRows: _totalRows,
                            validRows: _validRows.length,
                            failedRows: _failedRows.length,
                          ),
                          const SizedBox(height: 16),
                          _PreviewResults(
                            validRows: _validRows,
                            failedRows: _failedRows,
                          ),
                          const SizedBox(height: 16),
                          LoadingButton(
                            label: 'Confirm Import',
                            icon: Icons.cloud_upload_outlined,
                            isLoading: _isSubmitting,
                            onPressed: _validRows.isEmpty
                                ? null
                                : () => _confirmImport(),
                          ),
                        ],
                        const SizedBox(height: 28),
                        Text(
                          'Imported Sales',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        if (salesProvider.imports.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'No imported sales for this date.',
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
                          ...salesProvider.imports.map(
                            (import) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.cloud_done_outlined,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  'BDT ${currency.format(import.totalAmount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${import.shiftName ?? 'All shifts'} - ${import.externalReference ?? 'CSV Upload'}',
                                ),
                                trailing: Text(
                                  DateFormat(
                                    'h:mm a',
                                  ).format(import.importedAt.toLocal()),
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (salesProvider.importFailures.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Failed CSV Imports',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          ...salesProvider.importFailures.map(
                            (failure) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.error_outline,
                                    color: colorScheme.error,
                                  ),
                                ),
                                title: const Text(
                                  'CSV row rejected',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(failure.errorMessage),
                                trailing: Text(
                                  DateFormat(
                                    'h:mm a',
                                  ).format(failure.attemptedAt.toLocal()),
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _WorkflowProgress extends StatelessWidget {
  final bool hasCsv;
  final bool hasValidated;
  final bool hasValidRows;
  final bool isSaving;
  final bool hasSaved;

  const _WorkflowProgress({
    required this.hasCsv,
    required this.hasValidated,
    required this.hasValidRows,
    required this.isSaving,
    required this.hasSaved,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Upload CSV', hasCsv),
      ('Validate', hasValidated),
      ('Preview', hasValidated),
      ('Confirm Import', hasValidRows),
      ('Save', hasSaved || isSaving),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final step in steps)
          Chip(
            avatar: Icon(
              step.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
            ),
            label: Text(step.$1),
          ),
      ],
    );
  }
}

class _ValidationSummary extends StatelessWidget {
  final int totalRows;
  final int validRows;
  final int failedRows;

  const _ValidationSummary({
    required this.totalRows,
    required this.validRows,
    required this.failedRows,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCount(
            label: 'Total Rows',
            value: totalRows,
            icon: Icons.table_rows_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCount(
            label: 'Valid',
            value: validRows,
            icon: Icons.verified_outlined,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCount(
            label: 'Failed',
            value: failedRows,
            icon: Icons.report_gmailerrorred_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }
}

class _SummaryCount extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _SummaryCount({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewResults extends StatelessWidget {
  final List<CsvSalesImportRow> validRows;
  final List<CsvSalesImportIssue> failedRows;

  const _PreviewResults({required this.validRows, required this.failedRows});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (validRows.isNotEmpty) ...[
          Text(
            'Preview Results',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...validRows
              .take(8)
              .map(
                (row) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${row.rowNumber}')),
                    title: Text('BDT ${currency.format(row.totalAmount)}'),
                    subtitle: Text(
                      [
                        row.reference,
                        row.shift?.name ?? 'All shifts',
                        if (row.product != null)
                          '${row.product!.name}: ${row.quantity} units',
                      ].join(' - '),
                    ),
                  ),
                ),
              ),
          if (validRows.length > 8)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '+${validRows.length - 8} more valid rows',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ),
        ],
        if (failedRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Validation Issues',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...failedRows
              .take(8)
              .map(
                (issue) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                    ),
                    title: Text('Row ${issue.rowNumber}: ${issue.reason}'),
                    subtitle: Text(issue.rawLine),
                  ),
                ),
              ),
          if (failedRows.length > 8)
            Text(
              '+${failedRows.length - 8} more failed rows',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
        ],
      ],
    );
  }
}

class _ImportSummary extends StatelessWidget {
  final String date;
  final double actual;
  final double target;

  const _ImportSummary({
    required this.date,
    required this.actual,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = NumberFormat('#,##0.00');
    final progress = target > 0 ? (actual / target) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              date,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SummaryValue(
                    label: 'Imported Sales',
                    value: 'BDT ${currency.format(actual)}',
                    icon: Icons.trending_up_outlined,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryValue(
                    label: 'Target',
                    value: 'BDT ${currency.format(target)}',
                    icon: Icons.track_changes_outlined,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1 ? Colors.green : colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryValue({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
