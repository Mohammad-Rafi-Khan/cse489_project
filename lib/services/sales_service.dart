import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sales_target.dart';
import '../models/sales_entry.dart';

/// Handles all Supabase queries for sales targets and sales entries.
class SalesService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Sales Targets ─────────────────────────────────────────

  /// Fetches all targets for a branch in a given date range.
  Future<List<SalesTarget>> fetchTargets(
      String branchId, DateTime from, DateTime to) async {
    final fromStr = _dateStr(from);
    final toStr = _dateStr(to);
    final data = await _supabase
        .from('sales_targets')
        .select('*, shifts(name)')
        .eq('branch_id', branchId)
        .gte('target_date', fromStr)
        .lte('target_date', toStr)
        .order('target_date');
    return (data as List).map((e) => SalesTarget.fromMap(e)).toList();
  }

  /// Sets (upserts) a sales target.
  Future<SalesTarget> upsertTarget({
    required String branchId,
    String? shiftId,
    required DateTime targetDate,
    required double targetAmount,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    final data = await _supabase
        .from('sales_targets')
        .upsert(
          {
            'branch_id': branchId,
            'shift_id': shiftId,
            'target_date': _dateStr(targetDate),
            'target_amount': targetAmount,
            'created_by': userId,
          },
          onConflict: 'branch_id,shift_id,target_date',
        )
        .select('*, shifts(name)')
        .single();
    return SalesTarget.fromMap(data);
  }

  // ─── Sales Entries ─────────────────────────────────────────

  /// Fetches all sales entries for a branch on a given date.
  Future<List<SalesEntry>> fetchEntriesForDate(
      String branchId, DateTime date) async {
    final data = await _supabase
        .from('sales_entries')
        .select(
            '*, products(name, category), profiles!sales_entries_employee_id_fkey(name), shifts(name)')
        .eq('branch_id', branchId)
        .eq('sale_date', _dateStr(date))
        .order('recorded_at', ascending: false);
    return (data as List).map((e) => SalesEntry.fromMap(e)).toList();
  }

  /// Fetches sales entries for a date range (for performance screen).
  Future<List<SalesEntry>> fetchEntriesForRange(
      String branchId, DateTime from, DateTime to) async {
    final data = await _supabase
        .from('sales_entries')
        .select(
            '*, products(name, category), profiles!sales_entries_employee_id_fkey(name), shifts(name)')
        .eq('branch_id', branchId)
        .gte('sale_date', _dateStr(from))
        .lte('sale_date', _dateStr(to))
        .order('sale_date', ascending: false);
    return (data as List).map((e) => SalesEntry.fromMap(e)).toList();
  }

  /// Records a new sales transaction.
  Future<SalesEntry> recordSale({
    required String branchId,
    String? shiftId,
    required DateTime saleDate,
    required String employeeId,
    required String productId,
    required int quantity,
    required double unitPrice,
  }) async {
    final result = await _supabase.rpc('record_sale', params: {
      'p_branch_id': branchId,
      'p_shift_id': shiftId,
      'p_sale_date': _dateStr(saleDate),
      'p_product_id': productId,
      'p_quantity': quantity,
    });
    final entryId = (result as Map<String, dynamic>)['id'] as String;
    final data = await _supabase
        .from('sales_entries')
        .select(
            '*, products(name, category), profiles!sales_entries_employee_id_fkey(name), shifts(name)')
        .eq('id', entryId)
        .single();
    return SalesEntry.fromMap(data);
  }

  // ─── Helpers ───────────────────────────────────────────────

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
