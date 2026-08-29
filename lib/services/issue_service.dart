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

    return IssueReport.fromMap(data);
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
