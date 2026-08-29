import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance.dart';

/// Handles employee attendance check-in/check-out and branch-level summaries.
class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Attendance>> fetchMyAttendance(String employeeId) async {
    final data = await _supabase
        .from('attendance')
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .eq('employee_id', employeeId)
        .order('date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<List<Attendance>> fetchBranchAttendance(String branchId) async {
    final data = await _supabase
        .from('attendance')
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .eq('branch_id', branchId)
        .order('date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<List<Attendance>> fetchCompanyAttendance() async {
    final data = await _supabase
        .from('attendance')
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .order('date', ascending: false);
    return (data as List).map((e) => Attendance.fromMap(e)).toList();
  }

  Future<Attendance> checkInToday({
    required String employeeId,
    required String branchId,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final dateStr = _dateStr(targetDate);
    final checkIn = _timeStr(DateTime.now());
    final status = _statusFromCheckIn(checkIn);

    final existing = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('date', dateStr)
        .maybeSingle();

    if (existing != null) {
      final data = await _supabase
          .from('attendance')
          .update({
            'check_in_time': checkIn,
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing['id'])
          .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
          .single();
      return Attendance.fromMap(data);
    }

    final data = await _supabase
        .from('attendance')
        .insert({
          'employee_id': employeeId,
          'branch_id': branchId,
          'date': dateStr,
          'check_in_time': checkIn,
          'status': status,
        })
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .single();

    return Attendance.fromMap(data);
  }

  Future<Attendance> checkOutToday({
    required String employeeId,
    required String branchId,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final dateStr = _dateStr(targetDate);
    final checkOut = _timeStr(DateTime.now());

    final existing = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('date', dateStr)
        .maybeSingle();

    if (existing == null) {
      throw Exception('No attendance record found for today. Please check in first.');
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
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .single();

    return Attendance.fromMap(data);
  }

  Future<Attendance> updateAttendanceStatus({
    required String id,
    required String status,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }

    final data = await _supabase
        .from('attendance')
        .update(payload)
        .eq('id', id)
        .select('*, profiles!attendance_employee_id_fkey(name), branches(name)')
        .single();

    return Attendance.fromMap(data);
  }

  String _statusFromCheckIn(String checkInTime) {
    final parts = checkInTime.split(':');
    if (parts.length < 2) return 'present';
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final totalMinutes = (hour * 60) + minute;
    return totalMinutes > 9 * 60 + 30 ? 'late' : 'present';
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _timeStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';
}
