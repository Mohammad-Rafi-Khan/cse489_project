import 'package:flutter/foundation.dart';
import '../models/task.dart';
import '../models/task_assignment.dart';
import '../models/user_profile.dart';
import '../services/task_service.dart';

/// Manages task templates, branch employees, and task assignment state.
class TaskProvider extends ChangeNotifier {
  final TaskService _taskService = TaskService();

  List<Task> _taskTemplates = [];
  List<UserProfile> _branchEmployees = [];
  List<TaskAssignment> _managerAssignments = [];
  List<TaskAssignment> _employeeAssignments = [];
  bool _isLoading = false;
  String? _errorMessage;

  // ─── Getters ──────────────────────────────────────────────

  List<Task> get taskTemplates => _taskTemplates;
  List<UserProfile> get branchEmployees => _branchEmployees;
  List<TaskAssignment> get managerAssignments => _managerAssignments;
  List<TaskAssignment> get employeeAssignments => _employeeAssignments;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // ─── Task Templates ───────────────────────────────────────

  Future<void> loadTaskTemplates(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _taskTemplates = await _taskService.fetchTaskTemplates(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load task templates.';
      debugPrint('Load task templates error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ─── Branch Employees ─────────────────────────────────────

  Future<void> loadBranchEmployees(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _branchEmployees = await _taskService.fetchBranchEmployees(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load employees.';
      debugPrint('Load employees error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ─── Assign Task ──────────────────────────────────────────

  Future<void> assignTask({
    required String taskId,
    required String userId,
    required DateTime scheduledDate,
    DateTime? dueAt,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final assignment = await _taskService.assignTask(
        taskId: taskId,
        userId: userId,
        scheduledDate: scheduledDate,
        dueAt: dueAt,
      );
      _managerAssignments = [assignment, ..._managerAssignments];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to assign task. Please try again.';
      debugPrint('Assign task error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Manager Assignments ──────────────────────────────────

  Future<void> loadManagerAssignments(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _managerAssignments =
          await _taskService.fetchManagerAssignments(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load assignments.';
      debugPrint('Load manager assignments error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ─── Employee Assignments ─────────────────────────────────

  Future<void> loadEmployeeAssignments(String userId) async {
    _setLoading(true);
    _clearError();
    try {
      _employeeAssignments =
          await _taskService.fetchEmployeeAssignments(userId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load your tasks.';
      debugPrint('Load employee assignments error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ─── Clear ────────────────────────────────────────────────

  void clearAll() {
    _taskTemplates = [];
    _branchEmployees = [];
    _managerAssignments = [];
    _employeeAssignments = [];
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Helpers ──────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
