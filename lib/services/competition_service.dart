import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/competition.dart';
import '../models/branch_leaderboard_entry.dart';

/// Handles competition management and leaderboard rankings.
class CompetitionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches all competitions with joined branches, products, and leaderboard.
  Future<List<Competition>> fetchCompetitions() async {
    final data = await _supabase
        .from('competitions')
        .select(
            '*, competition_branches(*, branches(name, location)), competition_products(*, products(name, category, unit_price)), branch_leaderboard_entries(*, branches(name, location))')
        .order('start_date', ascending: false);

    return (data as List).map((e) => Competition.fromMap(e)).toList();
  }

  /// Fetches a single competition with complete leaderboard.
  Future<Competition> fetchCompetitionDetail(String competitionId) async {
    final data = await _supabase
        .from('competitions')
        .select(
            '*, competition_branches(*, branches(name, location)), competition_products(*, products(name, category, unit_price)), branch_leaderboard_entries(*, branches(name, location))')
        .eq('id', competitionId)
        .single();

    return Competition.fromMap(data);
  }

  /// Creates a new competition with participating branches and qualifying products.
  Future<Competition> createCompetition({
    required String title,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> branchIds,
    required List<Map<String, dynamic>> products, // [{ 'product_id': '...', 'points_per_unit': 2 }]
  }) async {
    final userId = _supabase.auth.currentUser?.id;

    final compData = await _supabase
        .from('competitions')
        .insert({
          'title': title,
          'description': description,
          'start_date': '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
          'end_date': '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
          'status': startDate.isAfter(DateTime.now()) ? 'upcoming' : 'active',
          'is_active': true,
          'created_by': userId,
        })
        .select()
        .single();

    final compId = compData['id'] as String;

    // Link branches
    if (branchIds.isNotEmpty) {
      final branchRows = branchIds.map((bId) => {
            'competition_id': compId,
            'branch_id': bId,
          }).toList();
      await _supabase.from('competition_branches').insert(branchRows);
    }

    // Link products
    if (products.isNotEmpty) {
      final productRows = products.map((p) => {
            'competition_id': compId,
            'product_id': p['product_id'],
            'points_per_unit': p['points_per_unit'] ?? 1,
          }).toList();
      await _supabase.from('competition_products').insert(productRows);
    }

    // Initialize leaderboard
    await recalculateLeaderboard(compId);

    return fetchCompetitionDetail(compId);
  }

  /// Recalculates leaderboard rankings based on branch sales during the competition window.
  Future<List<BranchLeaderboardEntry>> recalculateLeaderboard(String competitionId) async {
    await _supabase.rpc('recalculate_competition_leaderboard', params: {
      'p_competition_id': competitionId,
    });

    final data = await _supabase
        .from('branch_leaderboard_entries')
        .select('*, branches(name, location)')
        .eq('competition_id', competitionId)
        .order('current_rank');

    return (data as List).map((e) => BranchLeaderboardEntry.fromMap(e)).toList();
  }

  /// Updates competition details.
  Future<void> updateCompetitionStatus({
    required String id,
    required String status,
    required bool isActive,
  }) async {
    await _supabase
        .from('competitions')
        .update({
          'status': status,
          'is_active': isActive,
        })
        .eq('id', id);
  }
}
