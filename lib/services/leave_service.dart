import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/leave_request.dart';

/// Handles employee leave requests and manager approval decisions.
class LeaveService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<LeaveRequest>> fetchMyLeaves(String employeeId) async {
    final data = await _supabase
        .from('leave_requests')
        .select('*, branches(name), profiles!leave_requests_employee_id_fkey(name)')
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => LeaveRequest.fromMap(e)).toList();
  }

  Future<List<LeaveRequest>> fetchBranchLeaves(String branchId) async {
    final data = await _supabase
        .from('leave_requests')
        .select('*, branches(name), profiles!leave_requests_employee_id_fkey(name)')
        .eq('branch_id', branchId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => LeaveRequest.fromMap(e)).toList();
  }

  Future<List<LeaveRequest>> fetchCompanyLeaves() async {
    final data = await _supabase
        .from('leave_requests')
        .select('*, branches(name), profiles!leave_requests_employee_id_fkey(name)')
        .order('created_at', ascending: false);

    return (data as List).map((e) => LeaveRequest.fromMap(e)).toList();
  }

  Future<LeaveRequest> createLeaveRequest({
    required String branchId,
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final data = await _supabase
        .from('leave_requests')
        .insert({
          'branch_id': branchId,
          'employee_id': employeeId,
          'start_date': startDate.toIso8601String().split('T').first,
          'end_date': endDate.toIso8601String().split('T').first,
          'reason': reason,
          'status': 'pending',
        })
        .select('*, branches(name), profiles!leave_requests_employee_id_fkey(name)')
        .single();

    return LeaveRequest.fromMap(data);
  }

  Future<LeaveRequest> updateLeaveStatus({
    required String id,
    required String status,
    String? managerComment,
  }) async {
    await _supabase.rpc('review_leave_request', params: {
      'p_leave_id': id,
      'p_status': status,
      'p_manager_comment': managerComment,
    });

    final data = await _supabase
        .from('leave_requests')
        .select('*, branches(name), profiles!leave_requests_employee_id_fkey(name)')
        .eq('id', id)
        .single();

    return LeaveRequest.fromMap(data);
  }
}
