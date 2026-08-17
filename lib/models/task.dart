/// Represents a reusable task template stored in the `tasks` table.
/// A task template can be assigned to employees as [TaskAssignment] records.
class Task {
  final String id;
  final String title;
  final String? description;
  final String frequency; // 'daily' | 'weekly' | 'monthly'
  final String? branchId;
  final String? createdBy;
  final int basePoints;
  final bool photoRequired;
  final bool isActive;
  final DateTime createdAt;

  const Task({
    required this.id,
    required this.title,
    this.description,
    required this.frequency,
    this.branchId,
    this.createdBy,
    required this.basePoints,
    required this.photoRequired,
    required this.isActive,
    required this.createdAt,
  });

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      frequency: map['frequency'] as String? ?? 'daily',
      branchId: map['branch_id'] as String?,
      createdBy: map['created_by'] as String?,
      basePoints: map['base_points'] as int? ?? 0,
      photoRequired: map['photo_required'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
