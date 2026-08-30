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
      _upsertRecord(record);
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
      _upsertRecord(record);
      notifyListeners();
      return record;
    } catch (e) {
      _errorMessage = 'Failed to check out.';
      debugPrint('Check out error: $e');
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

  void _upsertRecord(Attendance record) {
    _myAttendance = _upsertInList(_myAttendance, record);
    _branchAttendance = _upsertInList(_branchAttendance, record);
    _allAttendance = _upsertInList(_allAttendance, record);
  }

  List<Attendance> _upsertInList(List<Attendance> list, Attendance record) {
    final updated = [
      record,
      ...list.where(
        (item) =>
            item.id != record.id &&
            !(item.employeeId == record.employeeId &&
                _sameDay(item.date, record.date)),
      ),
    ];
    updated.sort((a, b) => b.date.compareTo(a.date));
    return updated;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
