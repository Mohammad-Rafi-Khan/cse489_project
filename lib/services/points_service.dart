import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/badge.dart';
import '../models/points_transaction.dart';

/// Handles points transactions ledger and badge tiers.
class PointsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches points transaction history for an employee.
  Future<List<PointsTransaction>> fetchUserTransactions(String userId) async {
    final data = await _supabase
        .from('points_transactions')
        .select()
        .eq('user_id', userId)
        .order('awarded_at', ascending: false);

    return (data as List).map((e) => PointsTransaction.fromMap(e)).toList();
  }

  /// Fetches all badge tiers.
  Future<List<BadgeTier>> fetchBadgeTiers() async {
    final data = await _supabase
        .from('badges')
        .select()
        .order('min_points', ascending: true);

    return (data as List).map((e) => BadgeTier.fromMap(e)).toList();
  }
}
