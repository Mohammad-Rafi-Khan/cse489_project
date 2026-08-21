/// Represents one employee↔shift↔date assignment from `employee_shifts`.
/// Includes denormalized display fields from joined tables.
class EmployeeShift {
  final String id;
  final String employeeId;
  final String shiftId;
  final DateTime workDate;
  final DateTime createdAt;

  // Joined fields for display
  final String? employeeName;
  final String? shiftName;
  final String? shiftStartTime;
  final String? shiftEndTime;

  const EmployeeShift({
    required this.id,
    required this.employeeId,
    required this.shiftId,
    required this.workDate,
    required this.createdAt,
    this.employeeName,
    this.shiftName,
    this.shiftStartTime,
    this.shiftEndTime,
  });

  factory EmployeeShift.fromMap(Map<String, dynamic> map) {
    final profileData = map['profiles'] as Map<String, dynamic>?;
    final shiftData = map['shifts'] as Map<String, dynamic>?;

    return EmployeeShift(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      shiftId: map['shift_id'] as String,
      workDate: DateTime.parse(map['work_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      employeeName: profileData?['name'] as String?,
      shiftName: shiftData?['name'] as String?,
      shiftStartTime: shiftData?['start_time'] as String?,
      shiftEndTime: shiftData?['end_time'] as String?,
    );
  }
}
