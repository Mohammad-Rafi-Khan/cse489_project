import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/app_notification.dart';
import '../../models/task_assignment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issue_provider.dart';
import '../../providers/leave_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/task_provider.dart';

/// Employee dashboard displaying personal lifetime points, badge status,
/// task counters, and role-specific quick action tiles.
class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.profile == null) return;
    await Future.wait([
      context.read<TaskProvider>().loadEmployeeAssignments(auth.profile!.id),
      context.read<NotificationProvider>().loadNotifications(),
      context.read<IssueProvider>().loadMyIssues(auth.profile!.id),
      context.read<LeaveProvider>().loadMyLeaves(auth.profile!.id),
      auth.reloadProfile(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RetailFlow',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          // Notification Bell with unread counter badge
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, _) {
              final unread = notifProvider.unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications',
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/notifications',
                      ).then((_) => notifProvider.loadNotifications());
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              context.read<TaskProvider>().clearAll();
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final profile = authProvider.profile;

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withValues(alpha: 0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: colorScheme.onPrimary
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  (profile?.name.isNotEmpty == true)
                                      ? profile!.name[0].toUpperCase()
                                      : 'E',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome, ${profile?.name ?? 'Employee'}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      profile?.branchName ?? 'Branch Member',
                                      style: TextStyle(
                                        color: colorScheme.onPrimary.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Lifetime Points & Badge Tier Progression Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/points-history',
                            ).then((_) => _loadData()),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Builder(
                                    builder: (context) {
                                      final badgeName =
                                          profile?.badgeTierName ?? 'No Badge';
                                      final badgeLabel = badgeName == 'No Badge'
                                          ? badgeName
                                          : '$badgeName Badge';
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.emoji_events,
                                                  color: Colors.amber.shade700,
                                                  size: 24,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    badgeLabel,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${profile?.totalLifetimePoints ?? 0} pts',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            color: colorScheme.primary,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: profile?.badgeProgress ?? 0.0,
                                      minHeight: 10,
                                      backgroundColor:
                                          colorScheme.surfaceContainerHighest,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.amber.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Progress to ${profile?.nextBadgeName ?? 'Silver'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      Text(
                                        'Goal: ${profile?.nextBadgeThreshold ?? 500} pts',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Task Statistics Row
                        Consumer<TaskProvider>(
                          builder: (context, taskProvider, _) {
                            final tasks = taskProvider.employeeAssignments;
                            final pending = tasks
                                .where((t) => t.isPending)
                                .length;
                            final completed = tasks
                                .where((t) => t.isCompleted)
                                .length;
                            final approved = tasks
                                .where((t) => t.isApproved)
                                .length;

                            return Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Pending',
                                    value: '$pending',
                                    color: Colors.orange,
                                    icon: Icons.hourglass_empty,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Submitted',
                                    value: '$completed',
                                    color: Colors.blue,
                                    icon: Icons.send_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Approved',
                                    value: '$approved',
                                    color: Colors.green,
                                    icon: Icons.verified_outlined,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const _TodaysTasksPanel(),
                        const SizedBox(height: 24),

                        // Quick Actions Section
                        Text(
                          'Quick Actions',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _DashboardTile(
                          icon: Icons.assignment_outlined,
                          title: 'My Tasks',
                          subtitle:
                              'Complete tasks with photo proof & view history',
                          color: colorScheme.primary,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/my-tasks',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.calendar_month_outlined,
                          title: 'My Schedule',
                          subtitle: 'View your upcoming shift assignments',
                          color: Colors.purple,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/my-schedule',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.event_available_outlined,
                          title: 'My Attendance',
                          subtitle:
                              'Check in, check out, and review your attendance history',
                          color: Colors.green,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/attendance',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.analytics_outlined,
                          title: 'My Reports & Performance',
                          subtitle:
                              'View completion rate, badges, and points history',
                          color: Colors.indigo,
                          onTap: () => Navigator.pushNamed(context, '/reports'),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.report_problem_outlined,
                          title: 'Issue Reporting',
                          subtitle:
                              'Log operational issues and track status updates',
                          color: Colors.red,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/issues',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 10),
                        _DashboardTile(
                          icon: Icons.event_available_outlined,
                          title: 'Leave Requests',
                          subtitle:
                              'Submit leave requests and review your history',
                          color: Colors.green,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/leave-requests',
                          ).then((_) => _loadData()),
                        ),
                        const SizedBox(height: 24),
                        const _EmployeeActivityTimeline(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TodaysTasksPanel extends StatelessWidget {
  const _TodaysTasksPanel();

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<TaskProvider>(
      builder: (context, taskProvider, _) {
        final today = DateTime.now();
        final tasks =
            taskProvider.employeeAssignments
                .where(
                  (assignment) => _isSameDay(assignment.scheduledDate, today),
                )
                .toList()
              ..sort((a, b) => a.status.compareTo(b.status));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s Tasks',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (tasks.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No tasks scheduled for today.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              )
            else
              ...tasks
                  .take(4)
                  .map(
                    (task) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          task.isApproved
                              ? Icons.verified_outlined
                              : task.isCompleted
                              ? Icons.hourglass_top_outlined
                              : task.isRejected
                              ? Icons.error_outline
                              : Icons.assignment_outlined,
                          color: task.isApproved
                              ? Colors.green
                              : task.isRejected
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        title: Text(
                          task.taskTitle ?? 'Task',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(task.statusLabel),
                        trailing: Text(
                          '${task.potentialPoints} pts',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _EmployeeActivityTimeline extends StatelessWidget {
  const _EmployeeActivityTimeline();

  @override
  Widget build(BuildContext context) {
    return Consumer2<TaskProvider, NotificationProvider>(
      builder: (context, taskProvider, notificationProvider, _) {
        final events = <_TimelineEvent>[
          ..._taskEvents(taskProvider.employeeAssignments),
          ..._notificationEvents(notificationProvider.notifications),
        ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final visibleEvents = events.take(8).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity Timeline',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (visibleEvents.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No activity yet. Completed tasks, approvals, points, and badges will appear here.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              )
            else
              ...visibleEvents.map((event) => _TimelineTile(event: event)),
          ],
        );
      },
    );
  }

  List<_TimelineEvent> _taskEvents(List<TaskAssignment> assignments) {
    final events = <_TimelineEvent>[];
    for (final assignment in assignments) {
      final title = assignment.taskTitle ?? 'Task';
      for (final completion in assignment.completions) {
        events.add(
          _TimelineEvent(
            icon: completion.photoUrl == null
                ? Icons.check_circle_outline
                : Icons.add_a_photo_outlined,
            color: Colors.blue,
            title: 'Submitted $title',
            subtitle: completion.photoUrl == null
                ? 'Completion attempt ${completion.attemptNumber} submitted'
                : 'Photo proof uploaded for attempt ${completion.attemptNumber}',
            timestamp: completion.submittedAt,
          ),
        );
        if (completion.isApproved && completion.reviewedAt != null) {
          events.add(
            _TimelineEvent(
              icon: Icons.verified_outlined,
              color: Colors.green,
              title: 'Approved $title',
              subtitle: completion.pointsAwarded > 0
                  ? '+${completion.pointsAwarded} points earned'
                  : 'Approved by manager',
              timestamp: completion.reviewedAt!,
            ),
          );
        }
        if (completion.isRejected && completion.reviewedAt != null) {
          events.add(
            _TimelineEvent(
              icon: Icons.highlight_off_outlined,
              color: Colors.red,
              title: 'Rejected $title',
              subtitle: completion.reviewNote ?? 'Manager requested changes',
              timestamp: completion.reviewedAt!,
            ),
          );
        }
      }
    }
    return events;
  }

  List<_TimelineEvent> _notificationEvents(
    List<AppNotification> notifications,
  ) {
    const includedTypes = {
      'task_assigned',
      'badge_unlocked',
      'deadline_reminder',
    };

    return notifications
        .where((notification) => includedTypes.contains(notification.type))
        .map(
          (notification) => _TimelineEvent(
            icon: _iconForNotification(notification.type),
            color: _colorForNotification(notification.type),
            title: notification.title,
            subtitle: notification.message,
            timestamp: notification.createdAt,
          ),
        )
        .toList();
  }

  IconData _iconForNotification(String type) {
    return switch (type) {
      'badge_unlocked' => Icons.emoji_events_outlined,
      'deadline_reminder' => Icons.alarm_outlined,
      _ => Icons.assignment_outlined,
    };
  }

  Color _colorForNotification(String type) {
    return switch (type) {
      'badge_unlocked' => Colors.amber,
      'deadline_reminder' => Colors.deepOrange,
      _ => Colors.indigo,
    };
  }
}

class _TimelineTile extends StatelessWidget {
  final _TimelineEvent event;

  const _TimelineTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final formatter = DateFormat('dd MMM, h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: event.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(event.icon, color: event.color, size: 20),
        ),
        title: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          event.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          formatter.format(event.timestamp.toLocal()),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _TimelineEvent {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final DateTime timestamp;

  const _TimelineEvent({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.timestamp,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        onTap: onTap,
      ),
    );
  }
}
