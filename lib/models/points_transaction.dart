/// Represents an immutable point-earning event in `points_transactions`.
class PointsTransaction {
  final String id;
  final String userId;
  final String taskCompletionId;
  final int points;
  final int basePoints;
  final int bonusPoints;
  final DateTime awardedAt;

  const PointsTransaction({
    required this.id,
    required this.userId,
    required this.taskCompletionId,
    required this.points,
    required this.basePoints,
    required this.bonusPoints,
    required this.awardedAt,
  });

  factory PointsTransaction.fromMap(Map<String, dynamic> map) {
    return PointsTransaction(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      taskCompletionId: map['task_completion_id'] as String,
      points: map['points'] as int? ?? 0,
      basePoints: map['base_points'] as int? ?? 0,
      bonusPoints: map['bonus_points'] as int? ?? 0,
      awardedAt: DateTime.parse(map['awarded_at'] as String),
    );
  }
}
