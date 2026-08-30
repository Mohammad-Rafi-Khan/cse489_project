import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/issue_report.dart';

/// Handles employee and manager issue reporting workflow.
class IssueService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<IssueReport>> fetchMyIssues(String userId) async {
    final data = await _supabase
        .from('issue_reports')
        .select('*, branches(name), profiles!issue_reports_reported_by_fkey(name)')
        .eq('reported_by', userId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => IssueReport.fromMap(e)).toList();
  }

  Future<List<IssueReport>> fetchBranchIssues(String branchId) async {
    final data = await _supabase
        .from('issue_reports')
        .select('*, branches(name), profiles!issue_reports_reported_by_fkey(name)')
        .eq('branch_id', branchId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => IssueReport.fromMap(e)).toList();
  }

  Future<List<IssueReport>> fetchCompanyIssues() async {
    final data = await _supabase
        .from('issue_reports')
        .select('*, branches(name), profiles!issue_reports_reported_by_fkey(name)')
        .order('created_at', ascending: false);

    return (data as List).map((e) => IssueReport.fromMap(e)).toList();
  }

  Future<IssueReport> createIssue({
    required String branchId,
    required String reportedBy,
    required String reporterName,
    required String reporterRole,
    required String title,
    required String description,
    required String priority,
  }) async {
    final data = await _supabase
        .from('issue_reports')
        .insert({
          'branch_id': branchId,
          'reported_by': reportedBy,
          'title': title,
          'description': description,
          'priority': priority,
          'status': 'open',
        })
        .select('*, branches(name), profiles!issue_reports_reported_by_fkey(name)')
        .single();

    final issue = IssueReport.fromMap(data);

    // Dispatch notifications based on who filed the issue.
    try {
      await _notifyRecipients(
        issue: issue,
        reporterName: reporterName,
        reporterRole: reporterRole,
        branchId: branchId,
      );
    } catch (e) {
      // Notification failure must never block issue creation.
      // ignore: avoid_print
      print('[IssueService] Notification dispatch failed: $e');
    }

    return issue;
  }

  /// Sends in-app notifications to the appropriate audience:
  /// - Employee files issue  → notify the branch manager
  /// - Manager files issue   → notify all admins
  Future<void> _notifyRecipients({
    required IssueReport issue,
    required String reporterName,
    required String reporterRole,
    required String branchId,
  }) async {
    final priorityLabel = issue.priority[0].toUpperCase() +
        issue.priority.substring(1);

    List<String> recipientIds = [];

    if (reporterRole == 'employee') {
      // Fetch the manager of this branch.
      final rows = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', 'manager')
          .eq('branch_id', branchId)
          .eq('is_active', true);
      recipientIds =
          (rows as List).map((r) => r['id'] as String).toList();
    } else if (reporterRole == 'manager') {
      // Fetch all active admins (admins have no branch).
      final rows = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', 'admin')
          .eq('is_active', true);
      recipientIds =
          (rows as List).map((r) => r['id'] as String).toList();
    }

    if (recipientIds.isEmpty) return;

    final String notifTitle = reporterRole == 'employee'
        ? 'New Issue Reported'
        : 'Manager Issue Escalation';

    final String notifMessage = reporterRole == 'employee'
        ? '$reporterName reported a $priorityLabel-priority issue: "${issue.title}"'
        : '$reporterName escalated a $priorityLabel-priority issue to admin: "${issue.title}"';

    final notifications = recipientIds.map((uid) => {
          'user_id': uid,
          'type': 'issue_reported',
          'title': notifTitle,
          'message': notifMessage,
          'data': {
            'issue_id': issue.id,
            'branch_id': branchId,
            'priority': issue.priority,
          },
          'is_read': false,
        }).toList();

    await _supabase.from('notifications').insert(notifications);
  }

  Future<IssueReport> updateIssueStatus({
    required String id,
    required String status,
    String? resolutionNote,
  }) async {
    await _supabase.rpc('update_issue_status', params: {
      'p_issue_id': id,
      'p_status': status,
      'p_resolution_note': resolutionNote,
    });

    final data = await _supabase
        .from('issue_reports')
        .select('*, branches(name), profiles!issue_reports_reported_by_fkey(name)')
        .eq('id', id)
        .single();

    return IssueReport.fromMap(data);
  }
}
