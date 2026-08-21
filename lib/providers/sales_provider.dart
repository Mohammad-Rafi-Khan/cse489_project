import 'package:flutter/foundation.dart';
import '../models/sales_target.dart';
import '../models/sales_entry.dart';
import '../services/sales_service.dart';

/// Manages sales targets, sales entries, and performance data state.
class SalesProvider extends ChangeNotifier {
  final SalesService _salesService = SalesService();

  List<SalesTarget> _targets = [];
  List<SalesEntry> _entries = [];
  List<SalesEntry> _rangeEntries = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<SalesTarget> get targets => _targets;
  List<SalesEntry> get entries => _entries;
  List<SalesEntry> get rangeEntries => _rangeEntries;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Total sales amount for the currently loaded entries.
  double get totalActual =>
      _entries.fold(0, (sum, e) => sum + e.totalAmount);

  /// Total target for the currently loaded targets.
  double get totalTarget =>
      _targets.fold(0, (sum, t) => sum + t.targetAmount);

  // ─── Targets ──────────────────────────────────────────────

  Future<void> loadTargets(
      String branchId, DateTime from, DateTime to) async {
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

  // ─── Entries ──────────────────────────────────────────────

  Future<void> loadEntriesForDate(String branchId, DateTime date) async {
    _setLoading(true);
    _clearError();
    try {
      _entries = await _salesService.fetchEntriesForDate(branchId, date);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load sales entries.';
      debugPrint('Load entries error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadEntriesForRange(
      String branchId, DateTime from, DateTime to) async {
    _setLoading(true);
    _clearError();
    try {
      _rangeEntries =
          await _salesService.fetchEntriesForRange(branchId, from, to);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load sales data.';
      debugPrint('Load range entries error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> recordSale({
    required String branchId,
    String? shiftId,
    required DateTime saleDate,
    required String employeeId,
    required String productId,
    required int quantity,
    required double unitPrice,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final entry = await _salesService.recordSale(
        branchId: branchId,
        shiftId: shiftId,
        saleDate: saleDate,
        employeeId: employeeId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
      );
      _entries = [entry, ..._entries];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to record sale.';
      debugPrint('Record sale error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Performance Helpers ──────────────────────────────────

  /// Groups range entries by shift name and returns totals.
  /// Returns a list of maps with 'shift', 'actual' keys.
  List<Map<String, dynamic>> get performanceByShift {
    final Map<String, double> totals = {};
    for (final entry in _rangeEntries) {
      final key = entry.shiftName ?? 'No Shift';
      totals[key] = (totals[key] ?? 0) + entry.totalAmount;
    }
    return totals.entries
        .map((e) => {'shift': e.key, 'actual': e.value})
        .toList()
      ..sort((a, b) =>
          (b['actual'] as double).compareTo(a['actual'] as double));
  }

  // ─── Clear ────────────────────────────────────────────────

  void clearAll() {
    _targets = [];
    _entries = [];
    _rangeEntries = [];
    _errorMessage = null;
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
