import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';

/// Manages in-app notifications and unread badge counters.
class NotificationProvider extends ChangeNotifier {
  final NotificationService _notificationService = NotificationService();

  List<AppNotification> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get hasUnread => unreadCount > 0;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _notifications = await _notificationService.fetchMyNotifications();
    } catch (e) {
      _errorMessage = 'Failed to load notifications.';
      debugPrint('Load notifications error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      await _notificationService.markAsRead(id);
      _notifications = _notifications.map((n) {
        if (n.id == id) {
          return AppNotification(
            id: n.id,
            userId: n.userId,
            type: n.type,
            title: n.title,
            message: n.message,
            data: n.data,
            isRead: true,
            createdAt: n.createdAt,
          );
        }
        return n;
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Mark notification as read error: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _notificationService.markAllAsRead();
      _notifications = _notifications
          .map(
            (n) => AppNotification(
              id: n.id,
              userId: n.userId,
              type: n.type,
              title: n.title,
              message: n.message,
              data: n.data,
              isRead: true,
              createdAt: n.createdAt,
            ),
          )
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Mark all read error: $e');
    }
  }
}
