import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_notification.dart';

/// Handles in-app notifications for employees, managers, and admins.
class NotificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches all notifications for the currently logged-in user.
  Future<List<AppNotification>> fetchMyNotifications() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => AppNotification.fromMap(e)).toList();
  }

  /// Marks a specific notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Marks all notifications for the user as read.
  Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Creates a new in-app notification.
  Future<AppNotification> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    final res = await _supabase
        .from('notifications')
        .insert({
          'user_id': userId,
          'type': type,
          'title': title,
          'message': message,
          'data': data,
          'is_read': false,
        })
        .select()
        .single();

    return AppNotification.fromMap(res);
  }
}
