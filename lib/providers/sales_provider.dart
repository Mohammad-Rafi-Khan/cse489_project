import 'package:flutter/foundation.dart';
import '../models/sales_import_failure.dart';
import '../models/sales_import.dart';
import '../models/sales_target.dart';
import '../services/sales_service.dart';

/// Manages sales targets, imported sales data, and performance state.
class SalesProvider extends ChangeNotifier {
  final SalesService _salesService = SalesService();

  List<SalesTarget> _targets = [];
  List<SalesImport> _imports = [];
  List<SalesImportFailure> _importFailures = [];
  List<SalesImport> _rangeImports = [];
  List<Map<String, dynamic>> _rangePerformance = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<SalesTarget> get targets => _targets;
  List<SalesImport> get imports => _imports;
  List<SalesImportFailure> get importFailures => _importFailures;
  List<SalesImport> get rangeImports => _rangeImports;
  List<Map<String, dynamic>> get rangePerformance => _rangePerformance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get totalActual => _imports.fold(0, (sum, e) => sum + e.totalAmount);

  double get totalTarget => _targets.fold(0, (sum, t) => sum + t.targetAmount);

  Future<void> loadTargets(String branchId, DateTime from, DateTime to) async {
    _setLoading(true);
    _clearError();
    try {
      _targets = await _salesService.fetchTargets(branchId, from, to);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load sales targets.';
      debugPrint('Load targets error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> upsertTarget({
    required String branchId,
    String? shiftId,
    required DateTime targetDate,
    required double targetAmount,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final target = await _salesService.upsertTarget(
        branchId: branchId,
        shiftId: shiftId,
        targetDate: targetDate,
        targetAmount: targetAmount,
      );
      final idx = _targets.indexWhere((t) => t.id == target.id);
      if (idx >= 0) {
        _targets[idx] = target;
      } else {
        _targets = [target, ..._targets];
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save target.';
      debugPrint('Upsert target error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadImportsForDate(String branchId, DateTime date) async {
    _setLoading(true);
    _clearError();
    try {
      _imports = await _salesService.fetchImportsForDate(branchId, date);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load imported sales data.';
      debugPrint('Load sales imports error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadImportFailuresForDate(String branchId, DateTime date) async {
    try {
      _importFailures = await _salesService.fetchImportFailuresForDate(
        branchId,
        date,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Load import failures error: $e');
    }
  }

  Future<void> loadImportsForRange(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    _setLoading(true);
    _clearError();
    try {
      _rangeImports = await _salesService.fetchImportsForRange(
        branchId,
        from,
        to,
      );
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load imported sales data.';
      debugPrint('Load range imports error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadPerformanceForRange(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      _rangePerformance = await _salesService.fetchPerformanceForRange(
        branchId,
        from,
        to,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Load performance error: $e');
    }
  }

  Future<void> importSalesData({
    required String branchId,
    String? shiftId,
    required DateTime saleDate,
    required double totalAmount,
    String? externalReference,
    String? productId,
    int? productQuantity,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final imported = await _salesService.importSalesData(
        branchId: branchId,
        shiftId: shiftId,
        saleDate: saleDate,
        totalAmount: totalAmount,
        externalReference: externalReference,
        productId: productId,
        productQuantity: productQuantity,
      );
      _imports = [imported, ..._imports];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to import sales data.';
      debugPrint('Import sales error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  List<Map<String, dynamic>> get performanceByShift {
    final Map<String, double> totals = {};
    for (final row in _rangePerformance) {
      final key = row['shift_name'] as String? ?? 'No Shift';
      totals[key] =
          (totals[key] ?? 0) + ((row['actual'] as num?)?.toDouble() ?? 0);
    }
    return totals.entries
        .map((e) => {'shift': e.key, 'actual': e.value})
        .toList()
      ..sort(
        (a, b) => (b['actual'] as double).compareTo(a['actual'] as double),
      );
  }

  void clearAll() {
    _targets = [];
    _imports = [];
    _importFailures = [];
    _rangeImports = [];
    _rangePerformance = [];
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
