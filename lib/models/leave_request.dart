/// Represents an employee leave request approved by the branch manager.
class LeaveRequest {
  final String id;
  final String branchId;
  final String employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? managerComment;

  // Joined display values
  final String? employeeName;
  final String? branchName;

  const LeaveRequest({
    required this.id,
    required this.branchId,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.managerComment,
    this.employeeName,
    this.branchName,
  });

  factory LeaveRequest.fromMap(Map<String, dynamic> map) {
    final branchData = _nestedMap(map['branches']);
    final employeeData = _nestedMap(map['profiles']) ?? _nestedMap(map['employee_profile']);

    return LeaveRequest(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      employeeId: map['employee_id'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      reason: map['reason'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String? ?? map['created_at'] as String),
      managerComment: map['manager_comment'] as String?,
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

  int get durationDays {
    final difference = endDate.difference(startDate).inDays;
    return difference + 1;
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }
}
