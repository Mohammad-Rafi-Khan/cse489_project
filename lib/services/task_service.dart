import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task.dart';
import '../models/task_assignment.dart';
import '../models/task_completion.dart';
import '../models/user_profile.dart';

/// Handles task templates, assignments, and multi-attempt completion workflows.
class TaskService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Task Templates ───────────────────────────────────────

  /// Returns active task templates for a given branch or org-wide.
  Future<List<Task>> fetchTaskTemplates(String branchId) async {
    final data = await _supabase
        .from('tasks')
        .select()
        .or('branch_id.eq.$branchId,branch_id.is.null')
        .eq('is_active', true)
        .order('title');
    return (data as List).map((e) => Task.fromMap(e)).toList();
  }

  /// Returns ALL task templates (active + inactive) for management screen.
  Future<List<Task>> fetchAllTaskTemplates(String branchId) async {
    final data = await _supabase
        .from('tasks')
        .select()
        .or('branch_id.eq.$branchId,branch_id.is.null')
        .order('title');
    return (data as List).map((e) => Task.fromMap(e)).toList();
  }

  /// Creates a new task template.
  Future<Task> createTaskTemplate({
    required String title,
    String? description,
    required String frequency,
    required String branchId,
    required int basePoints,
    required int photoBonusPoints,
    required bool photoRequired,
    int? deadlineHoursAfterAssignment,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    final data = await _supabase
        .from('tasks')
        .insert({
          'title': title,
          'description': description,
          'frequency': frequency,
          'branch_id': branchId,
          'created_by': userId,
          'base_points': basePoints,
          'photo_bonus_points': photoBonusPoints,
          'photo_required': photoRequired,
          'deadline_hours_after_assignment': deadlineHoursAfterAssignment,
          'is_active': true,
        })
        .select()
        .single();
    return Task.fromMap(data);
  }

  /// Updates an existing task template.
  Future<Task> updateTaskTemplate({
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
    final data = await _supabase
        .from('tasks')
        .update({
          'title': title,
          'description': description,
          'frequency': frequency,
          'base_points': basePoints,
          'photo_bonus_points': photoBonusPoints,
          'photo_required': photoRequired,
          'deadline_hours_after_assignment': deadlineHoursAfterAssignment,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Task.fromMap(data);
  }

  // ─── Employees ────────────────────────────────────────────

  Future<List<UserProfile>> fetchBranchEmployees(String branchId) async {
    final data = await _supabase
        .from('profiles')
        .select(
          '*, branches!profiles_branch_id_fkey(name), badges!profiles_current_badge_id_fkey(name)',
        )
        .eq('branch_id', branchId)
        .eq('role', 'employee')
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }

  // ─── Task Assignment ──────────────────────────────────────

  /// Creates a new single task assignment.
  Future<TaskAssignment> assignTask({
    required String taskId,
    required String userId,
    required DateTime scheduledDate,
    DateTime? dueAt,
  }) async {
    final dateStr =
        '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}';

    final result = await _supabase.rpc(
      'assign_task',
      params: {
        'p_task_id': taskId,
        'p_user_id': userId,
        'p_scheduled_date': dateStr,
        'p_due_at': dueAt?.toUtc().toIso8601String(),
      },
    );
    final data = await _supabase
        .from('task_assignments')
        .select(
          '*, tasks(title, description, frequency, base_points, photo_bonus_points, photo_required), profiles(name), task_completions(*)',
        )
        .eq('id', (result as Map<String, dynamic>)['id'] as String)
        .single();

    return TaskAssignment.fromMap(data);
  }

  // ─── Task Completion History (Separate Attempts) ──────────

  /// Employee submits or resubmits a completion attempt.
  Future<TaskCompletion> submitCompletion({
    required String assignmentId,
    String? completionNote,
    String? photoUrl,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _supabase.rpc(
      'submit_task_completion',
      params: {
        'p_assignment_id': assignmentId,
        'p_completion_note': completionNote,
        'p_photo_url': photoUrl,
      },
    );
    final compData = await _supabase
        .from('task_completions')
        .select(
          '*, submitter:profiles!task_completions_submitted_by_fkey(name)',
        )
        .eq('id', (result as Map<String, dynamic>)['id'] as String)
        .single();

    return TaskCompletion.fromMap(compData);
  }

  /// Manager approves a task completion attempt through the workflow RPC.
  ///
  /// The database function verifies caller authorization and branch scoping, then
  /// delegates reward side effects to points, badge, and notification logic.
  ///
  /// SECURITY: There is intentionally NO client-side fallback here.
  /// If the RPC fails (permission denied, already approved, etc.) the error is
  /// surfaced to the UI. Never bypass the RPC; it is the sole authorization gate.
  Future<void> approveCompletion({
    required String completionId,
    required String assignmentId,
    String? reviewNote,
  }) async {
    final callerId = _supabase.auth.currentUser?.id;
    if (callerId == null) throw Exception('Not authenticated');

    await _supabase.rpc(
      'approve_task_completion',
      params: {'p_completion_id': completionId, 'p_review_note': reviewNote},
    );
  }

  /// Manager rejects a task completion attempt with reason.
  Future<void> rejectCompletion({
    required String completionId,
    required String assignmentId,
    required String reviewNote,
  }) async {
    await _supabase.rpc(
      'reject_task_completion',
      params: {'p_completion_id': completionId, 'p_review_note': reviewNote},
    );
  }

  // ─── Query Assignments with Full Attempt Histories ─────────

  /// Fetch all assignments for manager's branch with joined attempt histories.
  Future<List<TaskAssignment>> fetchManagerAssignments(String branchId) async {
    final data = await _supabase
        .from('task_assignments')
        .select(
          '*, tasks(title, description, frequency, base_points, photo_bonus_points, photo_required), profiles!task_assignments_user_id_fkey(name, branch_id), task_completions(*, submitter:profiles!task_completions_submitted_by_fkey(name), reviewer:profiles!task_completions_reviewed_by_fkey(name))',
        )
        .order('scheduled_date', ascending: false);

    final assignments = (data as List)
        .map((e) => TaskAssignment.fromMap(e))
        .toList();

    return assignments.where((a) {
      final profileData = data.firstWhere(
        (d) => d['id'] == a.id,
        orElse: () => <String, dynamic>{},
      );
      final profile = profileData['profiles'] as Map<String, dynamic>?;
      return profile?['branch_id'] == branchId;
    }).toList();
  }

  /// Fetch all assignments for an employee with full attempt history.
  Future<List<TaskAssignment>> fetchEmployeeAssignments(String userId) async {
    final data = await _supabase
        .from('task_assignments')
        .select(
          '*, tasks(title, description, frequency, base_points, photo_bonus_points, photo_required), task_completions(*, submitter:profiles!task_completions_submitted_by_fkey(name), reviewer:profiles!task_completions_reviewed_by_fkey(name))',
        )
        .eq('user_id', userId)
        .order('scheduled_date', ascending: false);

    return (data as List).map((e) => TaskAssignment.fromMap(e)).toList();
  }
}
