/// Represents a retail attendance record for an employee.
class Attendance {
  final String id;
  final String employeeId;
  final String branchId;
  final DateTime date;
  final String? checkInTime;
  final String? checkOutTime;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String? employeeName;
  final String? branchName;

  const Attendance({
    required this.id,
    required this.employeeId,
    required this.branchId,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.employeeName,
    this.branchName,
  });

  factory Attendance.fromMap(Map<String, dynamic> map) {
    final employeeData =
        _nestedMap(map['profiles']) ?? _nestedMap(map['employee_profile']);
    final branchData = _nestedMap(map['branches']);
    final rawDate = map['attendance_date'] ?? map['date'];

    return Attendance(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      branchId: map['branch_id'] as String,
      date: DateTime.parse(rawDate as String),
      checkInTime: _timeLabel(map['check_in_time']),
      checkOutTime: _timeLabel(map['check_out_time']),
      status: (map['status'] as String?) ?? 'present',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(
        map['updated_at'] as String? ?? map['created_at'] as String,
      ),
      employeeName: employeeData?['name'] as String?,
      branchName: branchData?['name'] as String?,
    );
  }

  static Map<String, dynamic>? _nestedMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  static String? _timeLabel(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      final local = parsed.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  String get statusLabel {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'half_day':
        return 'Half Day';
      default:
        return 'Present';
    }
  }
}
