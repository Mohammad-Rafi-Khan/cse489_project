/// Represents an in-app notification stored in the `notifications` table.
class AppNotification {
  final String id;
  final String userId;
  final String type; // 'task_assigned' | 'task_approved' | 'task_rejected' | 'shift_assigned' | 'target_achieved' | 'badge_unlocked' | 'competition_update'
  final String title;
  final String message;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: map['type'] as String? ?? 'general',
      title: map['title'] as String,
      message: map['message'] as String,
      data: map['data'] as Map<String, dynamic>?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
