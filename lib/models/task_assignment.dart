import 'task_completion.dart';

/// Represents a single task assignment from the `task_assignments` table.
/// Includes joined task metadata, employee metadata, and attempt history.
class TaskAssignment {
  final String id;
  final String taskId;
  final String userId;
  final DateTime scheduledDate;
  final DateTime? dueAt;
  final String status; // 'pending' | 'completed' | 'approved' | 'rejected'
  final DateTime assignedAt;

  // Joined / denormalized task & employee fields
  final String? taskTitle;
  final String? taskDescription;
  final String? frequency;
  final int basePoints;
  final int photoBonusPoints;
  final bool photoRequired;
  final String? employeeName;

  // Completion attempt history
  final List<TaskCompletion> completions;
  final TaskCompletion? latestCompletion;

  // Legacy convenience getters mapped to latest completion for compatibility
  String? get completionNote => latestCompletion?.completionNote;
  String? get photoUrl => latestCompletion?.photoUrl;
  DateTime? get completedAt => latestCompletion?.submittedAt;
  String? get reviewNote => latestCompletion?.reviewNote;
  DateTime? get reviewedAt => latestCompletion?.reviewedAt;
  String? get reviewedBy => latestCompletion?.reviewedBy;

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
    this.frequency,
    this.basePoints = 10,
    this.photoBonusPoints = 5,
    this.photoRequired = false,
    this.employeeName,
    this.completions = const [],
    this.latestCompletion,
  });

  factory TaskAssignment.fromMap(Map<String, dynamic> map) {
    final taskData = map['tasks'] as Map<String, dynamic>?;
    final profileData = map['profiles'] as Map<String, dynamic>?;

    List<TaskCompletion> attempts = [];
    if (map['task_completions'] is List) {
      attempts = (map['task_completions'] as List)
          .map((e) => TaskCompletion.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.attemptNumber.compareTo(a.attemptNumber));
    }

    final latest = attempts.isNotEmpty ? attempts.first : null;

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
      frequency: taskData?['frequency'] as String?,
      basePoints: taskData?['base_points'] as int? ?? 10,
      photoBonusPoints: taskData?['photo_bonus_points'] as int? ?? 5,
      photoRequired: taskData?['photo_required'] as bool? ?? false,
      employeeName: profileData?['name'] as String?,
      completions: attempts,
      latestCompletion: latest,
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

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
