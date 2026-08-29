/// Represents a branch operations issue reported by staff.
class IssueReport {
  final String id;
  final String branchId;
  final String reportedBy;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;

  // Joined display values
  final String? branchName;
  final String? reporterName;

  const IssueReport({
    required this.id,
    required this.branchId,
    required this.reportedBy,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.resolutionNote,
    this.branchName,
    this.reporterName,
  });

  factory IssueReport.fromMap(Map<String, dynamic> map) {
    final branchData = _nestedMap(map['branches']);
    final reporterData = _nestedMap(map['profiles']) ?? _nestedMap(map['reported_by_profile']);

    return IssueReport(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      reportedBy: map['reported_by'] as String,
      title: map['title'] as String? ?? 'Issue',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'open',
      priority: map['priority'] as String? ?? 'medium',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String? ?? map['created_at'] as String),
      resolvedAt: map['resolved_at'] == null ? null : DateTime.tryParse(map['resolved_at'] as String),
      resolutionNote: map['resolution_note'] as String?,
      branchName: branchData?['name'] as String?,
      reporterName: reporterData?['name'] as String?,
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

  bool get isOpen => status == 'open';
  bool get isInProgress => status == 'in_progress';
  bool get isResolved => status == 'resolved' || status == 'closed';

  String get statusLabel {
    switch (status) {
      case 'open':
        return 'Open';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }
}
