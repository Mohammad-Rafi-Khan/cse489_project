import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task.dart';
import '../models/task_assignment.dart';
import '../models/user_profile.dart';

/// Handles all Supabase queries for tasks and task assignments.
class TaskService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Task Templates ───────────────────────────────────────

  /// Returns active task templates for a given branch.
  Future<List<Task>> fetchTaskTemplates(String branchId) async {
    final data = await _supabase
        .from('tasks')
        .select()
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('title');
    return (data as List).map((e) => Task.fromMap(e)).toList();
  }

  // ─── Employees ────────────────────────────────────────────

  /// Returns active employees belonging to a specific branch.
  /// Used by managers when choosing who to assign a task to.
  Future<List<UserProfile>> fetchBranchEmployees(String branchId) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('branch_id', branchId)
        .eq('role', 'employee')
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }

  // ─── Task Assignment ──────────────────────────────────────

  /// Creates a new task assignment (manager assigns task to employee).
  Future<TaskAssignment> assignTask({
    required String taskId,
    required String userId,
    required DateTime scheduledDate,
    DateTime? dueAt,
  }) async {
    final data = await _supabase
        .from('task_assignments')
        .insert({
          'task_id': taskId,
          'user_id': userId,
          'scheduled_date':
              '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}',
          'due_at': dueAt?.toIso8601String(),
          'status': 'pending',
        })
        .select('*, tasks(title, description), profiles(name)')
        .single();
    return TaskAssignment.fromMap(data);
  }

  // ─── Manager Assignments ──────────────────────────────────

  /// Returns all assignments for employees in the manager's branch.
  /// Joins task title and employee name for display.
  Future<List<TaskAssignment>> fetchManagerAssignments(
      String branchId) async {
    // Fetch assignments where the assigned employee belongs to this branch
    final data = await _supabase
        .from('task_assignments')
        .select('*, tasks(title, description), profiles!task_assignments_user_id_fkey(name, branch_id)')
        .order('scheduled_date', ascending: false);

    final assignments = (data as List).map((e) => TaskAssignment.fromMap(e)).toList();

    // Filter client-side: only include employees from this branch
    // (RLS already filters by branch, but the join doesn't expose branch_id
    //  directly on the assignment — safer to double-check here)
    return assignments.where((a) {
      final profileData = data.firstWhere(
        (d) => d['id'] == a.id,
        orElse: () => <String, dynamic>{},
      );
      final profile = profileData['profiles'] as Map<String, dynamic>?;
      return profile?['branch_id'] == branchId;
    }).toList();
  }

  // ─── Employee My Tasks ────────────────────────────────────

  /// Returns all assignments for a specific employee.
  /// RLS ensures this only returns the authenticated employee's own assignments.
  Future<List<TaskAssignment>> fetchEmployeeAssignments(
      String userId) async {
    final data = await _supabase
        .from('task_assignments')
        .select('*, tasks(title, description)')
        .eq('user_id', userId)
        .order('scheduled_date', ascending: false);
    return (data as List).map((e) => TaskAssignment.fromMap(e)).toList();
  }
}
