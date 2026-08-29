import 'package:flutter/foundation.dart';
import '../models/attendance.dart';
import '../services/attendance_service.dart';

/// Manages employee, branch, and admin attendance state.
class AttendanceProvider extends ChangeNotifier {
  final AttendanceService _service = AttendanceService();

  List<Attendance> _myAttendance = [];
  List<Attendance> _branchAttendance = [];
  List<Attendance> _allAttendance = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Attendance> get myAttendance => _myAttendance;
  List<Attendance> get branchAttendance => _branchAttendance;
  List<Attendance> get allAttendance => _allAttendance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyAttendance(String employeeId) async {
    _setLoading(true);
    _clearError();
    try {
      _myAttendance = await _service.fetchMyAttendance(employeeId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load attendance history.';
      debugPrint('Load my attendance error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadBranchAttendance(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _branchAttendance = await _service.fetchBranchAttendance(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load branch attendance.';
      debugPrint('Load branch attendance error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAllAttendance() async {
    _setLoading(true);
    _clearError();
    try {
      _allAttendance = await _service.fetchCompanyAttendance();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load company attendance.';
      debugPrint('Load company attendance error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<Attendance> checkInToday({
    required String employeeId,
    required String branchId,
  }) async {
    try {
      final record = await _service.checkInToday(
        employeeId: employeeId,
        branchId: branchId,
      );
      _myAttendance = [record, ..._myAttendance.where((item) => item.date != record.date)];
      _branchAttendance = [record, ..._branchAttendance.where((item) => item.date != record.date)];
      _allAttendance = [record, ..._allAttendance.where((item) => item.date != record.date)];
      notifyListeners();
      return record;
    } catch (e) {
      _errorMessage = 'Failed to check in.';
      debugPrint('Check in error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<Attendance> checkOutToday({
    required String employeeId,
    required String branchId,
  }) async {
    try {
      final record = await _service.checkOutToday(
        employeeId: employeeId,
        branchId: branchId,
      );
      _myAttendance = [record, ..._myAttendance.where((item) => item.date != record.date)];
      _branchAttendance = [record, ..._branchAttendance.where((item) => item.date != record.date)];
      _allAttendance = [record, ..._allAttendance.where((item) => item.date != record.date)];
      notifyListeners();
      return record;
    } catch (e) {
      _errorMessage = 'Failed to check out.';
      debugPrint('Check out error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<Attendance> updateAttendanceStatus({
    required String id,
    required String status,
    String? notes,
  }) async {
    try {
      final record = await _service.updateAttendanceStatus(
        id: id,
        status: status,
        notes: notes,
      );

      _myAttendance = _myAttendance.map((item) => item.id == id ? record : item).toList();
      _branchAttendance = _branchAttendance.map((item) => item.id == id ? record : item).toList();
      _allAttendance = _allAttendance.map((item) => item.id == id ? record : item).toList();
      notifyListeners();
      return record;
    } catch (e) {
      _errorMessage = 'Failed to update attendance status.';
      debugPrint('Update attendance status error: $e');
      notifyListeners();
      rethrow;
    }
  }

  void clearAll() {
    _myAttendance = [];
    _branchAttendance = [];
    _allAttendance = [];
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
