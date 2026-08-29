import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sales_import_failure.dart';
import '../models/sales_import.dart';
import '../models/sales_target.dart';

/// Handles Supabase queries for branch sales targets and imported sales data.
class SalesService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<SalesTarget>> fetchTargets(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    final data = await _supabase
        .from('sales_targets')
        .select('*, shifts(name)')
        .eq('branch_id', branchId)
        .gte('target_date', _dateStr(from))
        .lte('target_date', _dateStr(to))
        .order('target_date');
    return (data as List).map((e) => SalesTarget.fromMap(e)).toList();
  }

  Future<SalesTarget> upsertTarget({
    required String branchId,
    String? shiftId,
    required DateTime targetDate,
    required double targetAmount,
  }) async {
    if (targetAmount < 0) {
      throw Exception('Sales target cannot be negative.');
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Admin session expired. Please sign in again.');
    }

    final date = _dateStr(targetDate);
    final row = <String, dynamic>{
      'branch_id': branchId,
      'shift_id': shiftId,
      'target_date': date,
      'target_amount': targetAmount,
      'created_by': userId,
    };

    // PostgreSQL's normal UNIQUE constraint treats NULL shift_id values as
    // distinct. Handle the all-shifts target explicitly so repeated Admin saves
    // update the existing row instead of creating duplicate daily targets.
    if (shiftId == null) {
      final existing = await _supabase
          .from('sales_targets')
          .select('id')
          .eq('branch_id', branchId)
          .eq('target_date', date)
          .isFilter('shift_id', null)
          .maybeSingle();

      if (existing != null) {
        final data = await _supabase
            .from('sales_targets')
            .update({
              'target_amount': targetAmount,
              'created_by': userId,
            })
            .eq('id', existing['id'])
            .select('*, shifts(name)')
            .single();
        return SalesTarget.fromMap(data);
      }

      final data = await _supabase
          .from('sales_targets')
          .insert(row)
          .select('*, shifts(name)')
          .single();
      return SalesTarget.fromMap(data);
    }

    final data = await _supabase
        .from('sales_targets')
        .upsert(row, onConflict: 'branch_id,shift_id,target_date')
        .select('*, shifts(name)')
        .single();
    return SalesTarget.fromMap(data);
  }

  Future<List<SalesImport>> fetchImportsForDate(
    String branchId,
    DateTime date,
  ) async {
    final data = await _supabase
        .from('sales_imports')
        .select(
          '*, branches(name), shifts(name), profiles!sales_imports_imported_by_fkey(name)',
        )
        .eq('branch_id', branchId)
        .eq('sale_date', _dateStr(date))
        .order('imported_at', ascending: false);
    return (data as List).map((e) => SalesImport.fromMap(e)).toList();
  }

  Future<List<SalesImport>> fetchImportsForRange(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    final data = await _supabase
        .from('sales_imports')
        .select(
          '*, branches(name), shifts(name), profiles!sales_imports_imported_by_fkey(name)',
        )
        .eq('branch_id', branchId)
        .gte('sale_date', _dateStr(from))
        .lte('sale_date', _dateStr(to))
        .order('sale_date', ascending: false);
    return (data as List).map((e) => SalesImport.fromMap(e)).toList();
  }

  Future<List<SalesImportFailure>> fetchImportFailuresForDate(
    String branchId,
    DateTime date,
  ) async {
    final data = await _supabase
        .from('sales_import_failures')
        .select('*, profiles!sales_import_failures_attempted_by_fkey(name)')
        .eq('branch_id', branchId)
        .eq('sale_date', _dateStr(date))
        .order('attempted_at', ascending: false);
    return (data as List).map((e) => SalesImportFailure.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchPerformanceForRange(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    final data = await _supabase.rpc(
      'get_branch_shift_sales_performance',
      params: {
        'p_branch_id': branchId,
        'p_from': _dateStr(from),
        'p_to': _dateStr(to),
      },
    );
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Imports branch sales from CSV source rows.
  ///
  /// Optional product quantity data is kept separate from the branch sales
  /// amount and only used for product pricing and sales analytics.
  Future<SalesImport> importSalesData({
    required String branchId,
    String? shiftId,
    required DateTime saleDate,
    required double totalAmount,
    String? externalReference,
    String? productId,
    int? productQuantity,
  }) async {
    final items = <Map<String, dynamic>>[];
    if (productId != null && productQuantity != null && productQuantity > 0) {
      final item = <String, dynamic>{
        'product_id': productId,
        'quantity': productQuantity,
      };
      items.add(item);
    }

    final result = await _supabase.rpc(
      'import_sales_data',
      params: {
        'p_branch_id': branchId,
        'p_shift_id': shiftId,
        'p_sale_date': _dateStr(saleDate),
        'p_source': 'csv_upload',
        'p_total_amount': totalAmount,
        'p_external_reference': externalReference,
        'p_items': items,
      },
    );
    final resultMap = Map<String, dynamic>.from(result as Map);
    if (resultMap['success'] != true || resultMap['id'] == null) {
      throw Exception(resultMap['error'] ?? 'CSV sales import failed.');
    }
    final importId = resultMap['id'] as String;

    final data = await _supabase
        .from('sales_imports')
        .select(
          '*, branches(name), shifts(name), profiles!sales_imports_imported_by_fkey(name)',
        )
        .eq('id', importId)
        .single();
    return SalesImport.fromMap(data);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
