import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/empty_state.dart';

/// In-app notification center for all users.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  String _filter = 'all'; // 'all' | 'unread'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'task_assigned':
        return Icons.assignment_outlined;
      case 'task_approved':
        return Icons.verified_outlined;
      case 'task_rejected':
        return Icons.cancel_outlined;
      case 'shift_assigned':
        return Icons.schedule_outlined;
      case 'badge_unlocked':
        return Icons.emoji_events_outlined;
      case 'competition_update':
        return Icons.leaderboard_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(BuildContext context, String type) {
    final cs = Theme.of(context).colorScheme;
    switch (type) {
      case 'task_approved':
      case 'badge_unlocked':
        return Colors.green;
      case 'task_rejected':
        return cs.error;
      case 'shift_assigned':
        return Colors.teal;
      case 'competition_update':
        return Colors.orange;
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
            label: const Text('Mark All Read', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await context.read<NotificationProvider>().markAllAsRead();
              messenger.showSnackBar(
                const SnackBar(content: Text('All notifications marked as read.')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == 'all',
                    onSelected: (val) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Unread Only'),
                    selected: _filter == 'unread',
                    onSelected: (val) => setState(() => _filter = 'unread'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer<NotificationProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.notifications.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                var list = provider.notifications;
                if (_filter == 'unread') {
                  list = list.where((n) => !n.isRead).toList();
                }

                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: _filter == 'unread' ? 'No Unread Notifications' : 'No Notifications',
                    subtitle: 'You are all caught up on all alerts and tasks.',
                    action: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      onPressed: () => provider.loadNotifications(),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.loadNotifications(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final typeColor = _colorForType(context, item.type);
                      final timeStr = DateFormat('dd MMM, h:mm a').format(item.createdAt.toLocal());

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: item.isRead
                                ? colorScheme.surface
                                : colorScheme.primaryContainer.withValues(alpha: 0.25),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_iconForType(item.type), color: typeColor, size: 22),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (!item.isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    item.message,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (!item.isRead) {
                                  provider.markAsRead(item.id);
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
