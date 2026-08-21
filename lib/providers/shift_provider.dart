import 'package:flutter/foundation.dart';
import '../models/shift.dart';
import '../models/employee_shift.dart';
import '../models/user_profile.dart';
import '../services/shift_service.dart';

/// Manages shift definitions and employee schedule state.
class ShiftProvider extends ChangeNotifier {
  final ShiftService _shiftService = ShiftService();

  List<Shift> _shifts = [];
  List<Shift> _allShifts = [];
  List<EmployeeShift> _scheduleForDate = [];
  List<EmployeeShift> _mySchedule = [];
  List<UserProfile> _branchEmployees = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Shift> get shifts => _shifts;
  List<Shift> get allShifts => _allShifts;
  List<EmployeeShift> get scheduleForDate => _scheduleForDate;
  List<EmployeeShift> get mySchedule => _mySchedule;
  List<UserProfile> get branchEmployees => _branchEmployees;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // ─── Shifts ───────────────────────────────────────────────

  Future<void> loadShifts(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _shifts = await _shiftService.fetchShifts(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load shifts.';
      debugPrint('Load shifts error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAllShifts(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _allShifts = await _shiftService.fetchAllShifts(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load shifts.';
      debugPrint('Load all shifts error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createShift({
    required String branchId,
    required String name,
    required String startTime,
    required String endTime,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final shift = await _shiftService.createShift(
        branchId: branchId,
        name: name,
        startTime: startTime,
        endTime: endTime,
      );
      _allShifts = [shift, ..._allShifts];
      if (shift.isActive) _shifts = [shift, ..._shifts];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create shift.';
      debugPrint('Create shift error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateShift({
    required String id,
    required String name,
    required String startTime,
    required String endTime,
    required bool isActive,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final updated = await _shiftService.updateShift(
        id: id,
        name: name,
        startTime: startTime,
        endTime: endTime,
        isActive: isActive,
      );
      _allShifts =
          _allShifts.map((s) => s.id == id ? updated : s).toList();
      _shifts = _allShifts.where((s) => s.isActive).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update shift.';
      debugPrint('Update shift error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Employee Schedule ────────────────────────────────────

  Future<void> loadBranchEmployees(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _branchEmployees =
          await _shiftService.fetchBranchEmployees(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load employees.';
      debugPrint('Load branch employees error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadScheduleForDate(String branchId, DateTime date) async {
    _setLoading(true);
    _clearError();
    try {
      _scheduleForDate =
          await _shiftService.fetchScheduleForDate(branchId, date);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load schedule.';
      debugPrint('Load schedule error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadMySchedule(String userId) async {
    _setLoading(true);
    _clearError();
    try {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day);
      final to = from.add(const Duration(days: 7));
      _mySchedule = await _shiftService.fetchMySchedule(userId, from, to);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load your schedule.';
      debugPrint('Load my schedule error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> assignEmployeeToShift({
    required String employeeId,
    required String shiftId,
    required DateTime workDate,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final es = await _shiftService.assignEmployeeToShift(
        employeeId: employeeId,
        shiftId: shiftId,
        workDate: workDate,
      );
      _scheduleForDate = [es, ..._scheduleForDate];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to assign employee to shift.';
      debugPrint('Assign shift error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removeEmployeeShift(String employeeShiftId) async {
    _setLoading(true);
    _clearError();
    try {
      await _shiftService.removeEmployeeShift(employeeShiftId);
      _scheduleForDate =
          _scheduleForDate.where((es) => es.id != employeeShiftId).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to remove shift assignment.';
      debugPrint('Remove shift error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Clear ────────────────────────────────────────────────

  void clearAll() {
    _shifts = [];
    _allShifts = [];
    _scheduleForDate = [];
    _mySchedule = [];
    _branchEmployees = [];
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
