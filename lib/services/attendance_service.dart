import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance.dart';

/// Handles employee attendance check-in/check-out and branch-level summaries.
class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _attendanceSelect =
      '*, profiles!attendance_employee_id_fkey(name), branches(name)';

  Future<List<Attendance>> fetchMyAttendance(String employeeId) async {
    final data = await _supabase
        .from('attendance')
        .select(_attendanceSelect)
        .eq('employee_id', employeeId)
        .order('attendance_date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<List<Attendance>> fetchBranchAttendance(String branchId) async {
    final data = await _supabase
        .from('attendance')
        .select(_attendanceSelect)
        .eq('branch_id', branchId)
        .order('attendance_date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<List<Attendance>> fetchCompanyAttendance() async {
    final data = await _supabase
        .from('attendance')
        .select(_attendanceSelect)
        .order('attendance_date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<Attendance> checkInToday({
    required String employeeId,
    required String branchId,
    DateTime? date,
  }) async {
    if (branchId.trim().isEmpty) {
      throw Exception('A branch is required to check in.');
    }
    final targetDate = date ?? DateTime.now();
    final dateStr = _dateStr(targetDate);
    final now = DateTime.now();
    final checkIn = now.toUtc().toIso8601String();
    final status = await _statusFromCheckIn(
      employeeId: employeeId,
      date: targetDate,
      checkInTime: now,
    );

    final existing = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('branch_id', branchId)
        .eq('attendance_date', dateStr)
        .maybeSingle();

    if (existing != null) {
      if (existing['check_in_time'] != null) {
        return _fetchAttendanceById(existing['id'] as String);
      }

      final data = await _supabase
          .from('attendance')
          .update({
            'check_in_time': checkIn,
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing['id'])
          .select(_attendanceSelect)
          .single();
      return Attendance.fromMap(data);
    }

    final data = await _supabase
        .from('attendance')
        .insert({
          'employee_id': employeeId,
          'branch_id': branchId,
          'attendance_date': dateStr,
          'check_in_time': checkIn,
          'status': status,
        })
        .select(_attendanceSelect)
        .single();

    return Attendance.fromMap(data);
  }

  Future<Attendance> checkOutToday({
    required String employeeId,
    required String branchId,
    DateTime? date,
  }) async {
    if (branchId.trim().isEmpty) {
      throw Exception('A branch is required to check out.');
    }
    final targetDate = date ?? DateTime.now();
    final dateStr = _dateStr(targetDate);
    final checkOut = DateTime.now().toUtc().toIso8601String();

    final existing = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('branch_id', branchId)
        .eq('attendance_date', dateStr)
        .maybeSingle();

    if (existing == null) {
      throw Exception(
        'No attendance record found for today. Please check in first.',
      );
    }
    if (existing['check_in_time'] == null) {
      throw Exception('Please check in before checking out.');
    }
    if (existing['check_out_time'] != null) {
      return _fetchAttendanceById(existing['id'] as String);
    }

    final currentStatus = (existing['status'] as String?) ?? 'present';
    final status = currentStatus == 'late' ? 'late' : 'present';

    final data = await _supabase
        .from('attendance')
        .update({
          'check_out_time': checkOut,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', existing['id'])
        .select(_attendanceSelect)
        .single();

    return Attendance.fromMap(data);
  }

  Future<Attendance> _fetchAttendanceById(String id) async {
    final data = await _supabase
        .from('attendance')
        .select(_attendanceSelect)
        .eq('id', id)
        .single();

    return Attendance.fromMap(data);
  }

  Future<String> _statusFromCheckIn({
    required String employeeId,
    required DateTime date,
    required DateTime checkInTime,
  }) async {
    final shiftStart = await _assignedShiftStartMinutes(
      employeeId: employeeId,
      date: date,
    );
    if (shiftStart == null) return 'present';

    final localCheckIn = checkInTime.toLocal();
    final checkInMinutes = (localCheckIn.hour * 60) + localCheckIn.minute;
    return checkInMinutes > shiftStart ? 'late' : 'present';
  }

  Future<int?> _assignedShiftStartMinutes({
    required String employeeId,
    required DateTime date,
  }) async {
    try {
      final data = await _supabase
          .from('employee_shifts')
          .select('shifts(start_time, is_active)')
          .eq('employee_id', employeeId)
          .eq('work_date', _dateStr(date));

      int? earliest;
      for (final row in data as List) {
        final shift = row['shifts'];
        if (shift is! Map || shift['is_active'] == false) continue;
        final minutes = _minutesFromTime(shift['start_time']?.toString());
        if (minutes == null) continue;
        earliest = earliest == null
            ? minutes
            : (minutes < earliest ? minutes : earliest);
      }
      return earliest;
    } catch (_) {
      return null;
    }
  }

  int? _minutesFromTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return (hour * 60) + minute;
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
