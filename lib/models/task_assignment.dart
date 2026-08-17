/// Represents a single task assignment from the `task_assignments` table.
/// Includes joined fields (task title, employee name) for convenience.
class TaskAssignment {
  final String id;
  final String taskId;
  final String userId;
  final DateTime scheduledDate;
  final DateTime? dueAt;
  final String status; // 'pending' | 'completed' | 'approved' | 'rejected'
  final DateTime assignedAt;

  // Joined / denormalized fields for UI display
  final String? taskTitle;
  final String? taskDescription;
  final String? employeeName;

  const TaskAssignment({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.scheduledDate,
    this.dueAt,
    required this.status,
    required this.assignedAt,
    this.taskTitle,
    this.taskDescription,
    this.employeeName,
  });

  factory TaskAssignment.fromMap(Map<String, dynamic> map) {
    // Handle nested joins returned by Supabase's select with related tables
    final taskData = map['tasks'] as Map<String, dynamic>?;
    final profileData = map['profiles'] as Map<String, dynamic>?;

    return TaskAssignment(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      userId: map['user_id'] as String,
      scheduledDate: DateTime.parse(map['scheduled_date'] as String),
      dueAt: map['due_at'] != null
          ? DateTime.parse(map['due_at'] as String)
          : null,
      status: map['status'] as String? ?? 'pending',
      assignedAt: DateTime.parse(map['assigned_at'] as String),
      taskTitle: taskData?['title'] as String?,
      taskDescription: taskData?['description'] as String?,
      employeeName: profileData?['name'] as String?,
    );
  }

  /// Returns a user-friendly status label.
  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }
}
