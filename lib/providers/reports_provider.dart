import 'package:flutter/foundation.dart';
import '../services/reports_service.dart';

/// Manages analytics and report views for Employee, Manager, and Admin users.
class ReportsProvider extends ChangeNotifier {
  final ReportsService _reportsService = ReportsService();

  Map<String, dynamic>? _employeeReport;
  Map<String, dynamic>? _managerReport;
  Map<String, dynamic>? _adminReport;

  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? get employeeReport => _employeeReport;
  Map<String, dynamic>? get managerReport => _managerReport;
  Map<String, dynamic>? get adminReport => _adminReport;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadEmployeeReport(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _employeeReport = await _reportsService.fetchEmployeeReport(userId);
    } catch (e) {
      _errorMessage = 'Failed to load employee report.';
      debugPrint('Employee report error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadManagerReport(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _managerReport = await _reportsService.fetchManagerReport(
        branchId,
        from,
        to,
      );
    } catch (e) {
      _errorMessage = 'Failed to load branch report.';
      debugPrint('Manager report error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAdminReport(DateTime from, DateTime to) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _adminReport = await _reportsService.fetchAdminReport(from, to);
    } catch (e) {
      _errorMessage = 'Failed to load organization report.';
      debugPrint('Admin report error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
