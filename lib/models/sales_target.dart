/// Represents a sales target for a branch/shift/date combination.
class SalesTarget {
  final String id;
  final String branchId;
  final String? shiftId;
  final DateTime targetDate;
  final double targetAmount;
  final String? createdBy;
  final DateTime createdAt;

  // Joined
  final String? shiftName;

  const SalesTarget({
    required this.id,
    required this.branchId,
    this.shiftId,
    required this.targetDate,
    required this.targetAmount,
    this.createdBy,
    required this.createdAt,
    this.shiftName,
  });

  factory SalesTarget.fromMap(Map<String, dynamic> map) {
    final shiftData = map['shifts'] as Map<String, dynamic>?;
    return SalesTarget(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      targetDate: DateTime.parse(map['target_date'] as String),
      targetAmount: (map['target_amount'] as num).toDouble(),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      shiftName: shiftData?['name'] as String?,
    );
  }
}
