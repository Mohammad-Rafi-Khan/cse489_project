/// Represents a reusable task template stored in the `tasks` table.
/// A task template can be assigned to employees as [TaskAssignment] records
/// using the Assign Task screen.
class Task {
  final String id;
  final String title;
  final String? description;
  final String frequency; // 'daily' | 'weekly' | 'monthly' (label only)
  final String? branchId;
  final String? createdBy;
  final int basePoints;
  final int photoBonusPoints;
  final bool photoRequired;
  final int? deadlineHoursAfterAssignment;
  final bool isActive;
  final DateTime createdAt;

  final String? assignedUserId;
  final String? assignedEmployeeName;
  final int? scheduleWeekday;
  final int? scheduleMonthDay;
  final DateTime? lastGeneratedDate;
  final DateTime? lastGeneratedAt;

  const Task({
    required this.id,
    required this.title,
    this.description,
    required this.frequency,
    this.branchId,
    this.createdBy,
    required this.basePoints,
    this.photoBonusPoints = 5,
    required this.photoRequired,
    this.deadlineHoursAfterAssignment,
    required this.isActive,
    required this.createdAt,
    this.assignedUserId,
    this.assignedEmployeeName,
    this.scheduleWeekday,
    this.scheduleMonthDay,
    this.lastGeneratedDate,
    this.lastGeneratedAt,
  });

  factory Task.fromMap(Map<String, dynamic> map) {
    final assignedEmployee = map['assigned_employee'] as Map<String, dynamic>?;
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      frequency: map['frequency'] as String? ?? 'daily',
      branchId: map['branch_id'] as String?,
      createdBy: map['created_by'] as String?,
      basePoints: map['base_points'] as int? ?? 10,
      photoBonusPoints: map['photo_bonus_points'] as int? ?? 5,
      photoRequired: map['photo_required'] as bool? ?? false,
      deadlineHoursAfterAssignment:
          map['deadline_hours_after_assignment'] as int?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      assignedUserId: map['assigned_user_id'] as String?,
      assignedEmployeeName: assignedEmployee?['name'] as String?,
      scheduleWeekday: map['schedule_weekday'] as int?,
      scheduleMonthDay: map['schedule_month_day'] as int?,
      lastGeneratedDate: map['last_generated_date'] != null
          ? DateTime.parse(map['last_generated_date'] as String)
          : null,
      lastGeneratedAt: map['last_generated_at'] != null
          ? DateTime.parse(map['last_generated_at'] as String)
          : null,
    );
  }

  String get scheduleLabel {
    if (scheduleWeekday == 5) {
      return 'Every Friday';
    }
    if (scheduleMonthDay != null) {
      return 'Day $scheduleMonthDay of month';
    }
    return 'Daily';
  }

  int get ruleBasePoints {
    return switch (frequency) {
      'weekly' => 30,
      'monthly' => 60,
      _ => 10,
    };
  }

  int get rulePhotoBonusPoints => 5;
}
