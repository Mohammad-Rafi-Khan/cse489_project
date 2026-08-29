import 'package:flutter/foundation.dart';
import '../models/leave_request.dart';
import '../services/leave_service.dart';

/// Manages leave requests for employees and managers.
class LeaveProvider extends ChangeNotifier {
  final LeaveService _service = LeaveService();

  List<LeaveRequest> _requests = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<LeaveRequest> get requests => _requests;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyLeaves(String employeeId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _requests = await _service.fetchMyLeaves(employeeId);
    } catch (e) {
      _errorMessage = 'Failed to load leave requests.';
      debugPrint('Load leave requests error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBranchLeaves(String branchId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _requests = await _service.fetchBranchLeaves(branchId);
    } catch (e) {
      _errorMessage = 'Failed to load branch leave requests.';
      debugPrint('Load branch leave requests error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCompanyLeaves() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _requests = await _service.fetchCompanyLeaves();
    } catch (e) {
      _errorMessage = 'Failed to load company leave requests.';
      debugPrint('Load company leave requests error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createLeaveRequest({
    required String branchId,
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    try {
      final request = await _service.createLeaveRequest(
        branchId: branchId,
        employeeId: employeeId,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
      );
      _requests = [request, ..._requests];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to submit leave request.';
      debugPrint('Create leave request error: $e');
      rethrow;
    }
  }

  Future<void> updateLeaveStatus({
    required String id,
    required String status,
    String? managerComment,
  }) async {
    try {
      final request = await _service.updateLeaveStatus(
        id: id,
        status: status,
        managerComment: managerComment,
      );
      _requests = _requests.map((item) => item.id == id ? request : item).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update leave request.';
      debugPrint('Update leave request error: $e');
      rethrow;
    }
  }

  void clearAll() {
    _requests = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
