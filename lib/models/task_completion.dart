/// Represents a single submission/review attempt for a task assignment.
class TaskCompletion {
  final String id;
  final String assignmentId;
  final int attemptNumber;
  final String submittedBy;
  final DateTime submittedAt;
  final String? completionNote;
  final String? photoUrl;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String status; // 'submitted' | 'approved' | 'rejected'
  final int pointsAwarded;

  // Joined display fields
  final String? submitterName;
  final String? reviewerName;

  const TaskCompletion({
    required this.id,
    required this.assignmentId,
    required this.attemptNumber,
    required this.submittedBy,
    required this.submittedAt,
    this.completionNote,
    this.photoUrl,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    required this.status,
    this.pointsAwarded = 0,
    this.submitterName,
    this.reviewerName,
  });

  factory TaskCompletion.fromMap(Map<String, dynamic> map) {
    final submitterData = map['submitter'] as Map<String, dynamic>?;
    final reviewerData = map['reviewer'] as Map<String, dynamic>?;

    return TaskCompletion(
      id: map['id'] as String,
      assignmentId: map['assignment_id'] as String,
      attemptNumber: map['attempt_number'] as int? ?? 1,
      submittedBy: map['submitted_by'] as String,
      submittedAt: DateTime.parse(map['submitted_at'] as String),
      completionNote: map['completion_note'] as String?,
      photoUrl: map['photo_url'] as String?,
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] != null
          ? DateTime.parse(map['reviewed_at'] as String)
          : null,
      reviewNote: map['review_note'] as String?,
      status: map['status'] as String? ?? 'submitted',
      pointsAwarded: map['points_awarded'] as int? ?? 0,
      submitterName: submitterData?['name'] as String?,
      reviewerName: reviewerData?['name'] as String?,
    );
  }

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isSubmitted => status == 'submitted';
}
