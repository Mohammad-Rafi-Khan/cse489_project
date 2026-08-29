import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/task.dart';
import '../models/task_assignment.dart';
import '../models/task_completion.dart';
import '../models/user_profile.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';

/// Manages task templates, assignments, attempt histories, and photo verification.
class TaskProvider extends ChangeNotifier {
  final TaskService _taskService = TaskService();
  final StorageService _storageService = StorageService();

  List<Task> _taskTemplates = [];
  List<Task> _allTaskTemplates = [];
  List<UserProfile> _branchEmployees = [];
  List<TaskAssignment> _managerAssignments = [];
  List<TaskAssignment> _employeeAssignments = [];

  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;

  // ─── Getters ──────────────────────────────────────────────

  List<Task> get taskTemplates => _taskTemplates;
  List<Task> get allTaskTemplates => _allTaskTemplates;
  List<UserProfile> get branchEmployees => _branchEmployees;
  List<TaskAssignment> get managerAssignments => _managerAssignments;
  List<TaskAssignment> get employeeAssignments => _employeeAssignments;
  bool get isLoading => _isLoading;
  bool get isUploadingPhoto => _isUploadingPhoto;
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

  Future<void> loadAllTaskTemplates(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _allTaskTemplates = await _taskService.fetchAllTaskTemplates(branchId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load all task templates.';
      debugPrint('Load all task templates error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createTaskTemplate({
    required String title,
    String? description,
    required String frequency,
    required String branchId,
    required int basePoints,
    required int photoBonusPoints,
    required bool photoRequired,
    int? deadlineHoursAfterAssignment,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final task = await _taskService.createTaskTemplate(
        title: title,
        description: description,
        frequency: frequency,
        branchId: branchId,
        basePoints: basePoints,
        photoBonusPoints: photoBonusPoints,
        photoRequired: photoRequired,
        deadlineHoursAfterAssignment: deadlineHoursAfterAssignment,
      );
      _allTaskTemplates = [task, ..._allTaskTemplates];
      if (task.isActive) _taskTemplates = [task, ..._taskTemplates];
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create task template.';
      debugPrint('Create task template error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateTaskTemplate({
    required String id,
    required String title,
    String? description,
    required String frequency,
    required int basePoints,
    required int photoBonusPoints,
    required bool photoRequired,
    required bool isActive,
    int? deadlineHoursAfterAssignment,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final updated = await _taskService.updateTaskTemplate(
        id: id,
        title: title,
        description: description,
        frequency: frequency,
        basePoints: basePoints,
        photoBonusPoints: photoBonusPoints,
        photoRequired: photoRequired,
        isActive: isActive,
        deadlineHoursAfterAssignment: deadlineHoursAfterAssignment,
      );
      _allTaskTemplates = _allTaskTemplates
          .map((t) => t.id == id ? updated : t)
          .toList();
      _taskTemplates = _allTaskTemplates.where((t) => t.isActive).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update task template.';
      debugPrint('Update task template error: $e');
      notifyListeners();
      rethrow;
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

  // ─── Task Assignment ──────────────────────────────────────

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
      _errorMessage = 'Failed to assign task.';
      debugPrint('Assign task error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Photo Proof Picking & Storage Upload ──────────────────

  Future<XFile?> pickPhoto(ImageSource source) async {
    try {
      return await _storageService.pickImage(source);
    } catch (e) {
      _errorMessage = 'Failed to pick photo.';
      notifyListeners();
      return null;
    }
  }

  Future<String?> uploadPhotoProof({
    required XFile file,
    required String assignmentId,
    required String userId,
  }) async {
    _isUploadingPhoto = true;
    notifyListeners();
    try {
      final url = await _storageService.uploadTaskPhoto(
        file: file,
        assignmentId: assignmentId,
        userId: userId,
      );
      return url;
    } catch (e) {
      _errorMessage = 'Failed to upload photo to storage.';
      debugPrint('Photo upload error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _isUploadingPhoto = false;
      notifyListeners();
    }
  }

  // ─── Task Completion History (Attempt Records) ────────────

  Future<TaskCompletion> submitCompletion({
    required String assignmentId,
    String? completionNote,
    String? photoUrl,
    XFile? photoFile,
    required String userId,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      String? finalPhotoUrl = photoUrl;

      // If a local image file was chosen, upload it to Supabase Storage first
      if (photoFile != null) {
        finalPhotoUrl = await uploadPhotoProof(
          file: photoFile,
          assignmentId: assignmentId,
          userId: userId,
        );
      }

      final completion = await _taskService.submitCompletion(
        assignmentId: assignmentId,
        completionNote: completionNote,
        photoUrl: finalPhotoUrl,
      );

      // Refresh employee assignments list to reflect new attempt & completed status
      await loadEmployeeAssignments(userId);
      return completion;
    } catch (e) {
      _errorMessage = 'Failed to submit task completion.';
      debugPrint('Submit completion error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Manager Approval & Rejection ─────────────────────────

  Future<void> approveAssignment({
    required String completionId,
    required String assignmentId,
    String? reviewNote,
    required String branchId,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      await _taskService.approveCompletion(
        completionId: completionId,
        assignmentId: assignmentId,
        reviewNote: reviewNote,
      );
      await loadManagerAssignments(branchId);
    } catch (e) {
      _errorMessage = 'Failed to approve assignment.';
      debugPrint('Approve assignment error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> rejectAssignment({
    required String completionId,
    required String assignmentId,
    required String reviewNote,
    required String branchId,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      await _taskService.rejectCompletion(
        completionId: completionId,
        assignmentId: assignmentId,
        reviewNote: reviewNote,
      );
      await loadManagerAssignments(branchId);
    } catch (e) {
      _errorMessage = 'Failed to reject assignment.';
      debugPrint('Reject assignment error: $e');
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Loading Assignment Lists ─────────────────────────────

  Future<void> loadManagerAssignments(String branchId) async {
    _setLoading(true);
    _clearError();
    try {
      _managerAssignments = await _taskService.fetchManagerAssignments(
        branchId,
      );
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load assignments.';
      debugPrint('Load manager assignments error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadEmployeeAssignments(String userId) async {
    _setLoading(true);
    _clearError();
    try {
      _employeeAssignments = await _taskService.fetchEmployeeAssignments(
        userId,
      );
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load tasks.';
      debugPrint('Load employee assignments error: $e');
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ─── Clear State ──────────────────────────────────────────

  void clearAll() {
    _taskTemplates = [];
    _allTaskTemplates = [];
    _branchEmployees = [];
    _managerAssignments = [];
    _employeeAssignments = [];
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
