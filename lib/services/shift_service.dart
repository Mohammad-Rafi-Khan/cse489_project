import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift.dart';
import '../models/employee_shift.dart';
import '../models/user_profile.dart';

/// Handles all Supabase queries for shifts and employee scheduling.
class ShiftService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Shifts ───────────────────────────────────────────────

  /// Returns all active shifts for a branch.
  Future<List<Shift>> fetchShifts(String branchId) async {
    final data = await _supabase
        .from('shifts')
        .select()
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('start_time');
    return (data as List).map((e) => Shift.fromMap(e)).toList();
  }

  /// Returns all shifts (including inactive) for management screen.
  Future<List<Shift>> fetchAllShifts(String branchId) async {
    final data = await _supabase
        .from('shifts')
        .select()
        .eq('branch_id', branchId)
        .order('start_time');
    return (data as List).map((e) => Shift.fromMap(e)).toList();
  }

  /// Creates a new shift definition.
  Future<Shift> createShift({
    required String branchId,
    required String name,
    required String startTime, // 'HH:MM'
    required String endTime,
  }) async {
    final data = await _supabase
        .from('shifts')
        .insert({
          'branch_id': branchId,
          'name': name,
          'start_time': startTime,
          'end_time': endTime,
          'is_active': true,
        })
        .select()
        .single();
    return Shift.fromMap(data);
  }

  /// Updates a shift definition.
  Future<Shift> updateShift({
    required String id,
    required String name,
    required String startTime,
    required String endTime,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('shifts')
        .update({
          'name': name,
          'start_time': startTime,
          'end_time': endTime,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Shift.fromMap(data);
  }

  // ─── Employee Schedule ────────────────────────────────────

  /// Returns all employee-shift assignments for a given branch and date.
  Future<List<EmployeeShift>> fetchScheduleForDate(
    String branchId,
    DateTime date,
  ) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final data = await _supabase
        .from('employee_shifts')
        .select(
          '*, profiles!employee_shifts_employee_id_fkey(name, branch_id), shifts(name, start_time, end_time)',
        )
        .eq('work_date', dateStr);

    final all = (data as List).map((e) => EmployeeShift.fromMap(e)).toList();

    // Filter to branch only (profile.branch_id must match)
    return all.where((es) {
      final row = data.firstWhere(
        (d) => d['id'] == es.id,
        orElse: () => <String, dynamic>{},
      );
      final profile = row['profiles'] as Map<String, dynamic>?;
      return profile?['branch_id'] == branchId;
    }).toList();
  }

  /// Returns the logged-in employee's schedule for a date range.
  Future<List<EmployeeShift>> fetchMySchedule(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr =
        '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    final data = await _supabase
        .from('employee_shifts')
        .select('*, shifts(name, start_time, end_time)')
        .eq('employee_id', userId)
        .gte('work_date', fromStr)
        .lte('work_date', toStr)
        .order('work_date');
    return (data as List).map((e) => EmployeeShift.fromMap(e)).toList();
  }

  /// Assigns an employee to a shift on a specific date.
  Future<EmployeeShift> assignEmployeeToShift({
    required String employeeId,
    required String shiftId,
    required DateTime workDate,
  }) async {
    final dateStr =
        '${workDate.year}-${workDate.month.toString().padLeft(2, '0')}-${workDate.day.toString().padLeft(2, '0')}';
    await _supabase.rpc(
      'assign_employee_to_shift',
      params: {
        'p_employee_id': employeeId,
        'p_shift_id': shiftId,
        'p_work_date': dateStr,
      },
    );
    final data = await _supabase
        .from('employee_shifts')
        .select(
          '*, profiles!employee_shifts_employee_id_fkey(name, branch_id), shifts(name, start_time, end_time)',
        )
        .eq('employee_id', employeeId)
        .eq('shift_id', shiftId)
        .eq('work_date', dateStr)
        .single();
    return EmployeeShift.fromMap(data);
  }

  /// Removes an employee-shift assignment.
  Future<void> removeEmployeeShift(String employeeShiftId) async {
    await _supabase.from('employee_shifts').delete().eq('id', employeeShiftId);
  }

  /// Returns all branch employees for the schedule picker.
  Future<List<UserProfile>> fetchBranchEmployees(String branchId) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('branch_id', branchId)
        .eq('role', 'employee')
        .eq('is_active', true)
        .order('name');
    return (data as List).map((e) => UserProfile.fromMap(e)).toList();
  }
}
