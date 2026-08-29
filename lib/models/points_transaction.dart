/// Represents an immutable point-earning event in `points_transactions`.
class PointsTransaction {
  final String id;
  final String userId;
  final String taskCompletionId;
  final int points;
  final int basePoints;
  final int bonusPoints;
  final DateTime awardedAt;
  final String? taskTitle;
  final String? taskFrequency;
  final String? completionNote;
  final bool hasPhotoProof;

  const PointsTransaction({
    required this.id,
    required this.userId,
    required this.taskCompletionId,
    required this.points,
    required this.basePoints,
    required this.bonusPoints,
    required this.awardedAt,
    this.taskTitle,
    this.taskFrequency,
    this.completionNote,
    this.hasPhotoProof = false,
  });

  factory PointsTransaction.fromMap(Map<String, dynamic> map) {
    final completionData = _nestedMap(map['task_completions']);
    final assignmentData = _nestedMap(completionData?['task_assignments']);
    final taskData = _nestedMap(assignmentData?['tasks']);

    return PointsTransaction(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      taskCompletionId: map['task_completion_id'] as String,
      points: map['points'] as int? ?? 0,
      basePoints: map['base_points'] as int? ?? 0,
      bonusPoints: map['bonus_points'] as int? ?? 0,
      awardedAt: DateTime.parse(map['awarded_at'] as String),
      taskTitle: taskData?['title'] as String?,
      taskFrequency: taskData?['frequency'] as String?,
      completionNote: completionData?['completion_note'] as String?,
      hasPhotoProof: ((completionData?['photo_url'] as String?) ?? '')
          .trim()
          .isNotEmpty,
    );
  }

  String get sourceLabel => taskTitle == null
      ? 'Task completion reward'
      : 'Task approved: $taskTitle';

  String get detailLabel {
    final parts = <String>['Base $basePoints pts'];
    if (bonusPoints > 0) parts.add('Photo bonus $bonusPoints pts');
    if (taskFrequency != null) parts.add(taskFrequency!.toUpperCase());
    return parts.join(' | ');
  }
}

Map<String, dynamic>? _nestedMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}
