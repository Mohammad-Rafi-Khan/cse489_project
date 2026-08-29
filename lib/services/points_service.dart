import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/points_transaction.dart';

/// Handles point-award rules and the points transaction ledger.
///
/// Badge calculation and notification delivery intentionally live in their own
/// services/database logic; this service only knows how points are calculated
/// and how the ledger is read.
class PointsService {
  static const int dailyTaskPoints = 10;
  static const int weeklyTaskPoints = 30;
  static const int monthlyTaskPoints = 60;
  static const int photoProofBonusPoints = 5;

  final SupabaseClient _supabase = Supabase.instance.client;

  static int basePointsForFrequency(String frequency) {
    return switch (frequency) {
      'weekly' => weeklyTaskPoints,
      'monthly' => monthlyTaskPoints,
      _ => dailyTaskPoints,
    };
  }

  static PointAwardBreakdown calculateTaskAward({
    required String frequency,
    required bool hasPhotoProof,
  }) {
    final basePoints = basePointsForFrequency(frequency);
    final bonusPoints = hasPhotoProof ? photoProofBonusPoints : 0;

    return PointAwardBreakdown(
      basePoints: basePoints,
      bonusPoints: bonusPoints,
    );
  }

  /// Fetches points transaction history for an employee.
  Future<List<PointsTransaction>> fetchUserTransactions(String userId) async {
    final data = await _supabase
        .from('points_transactions')
        .select(
          '*, task_completions(completion_note, photo_url, task_assignments(tasks(title, frequency)))',
        )
        .eq('user_id', userId)
        .order('awarded_at', ascending: false);

    return (data as List).map((e) => PointsTransaction.fromMap(e)).toList();
  }
}

class PointAwardBreakdown {
  final int basePoints;
  final int bonusPoints;

  const PointAwardBreakdown({
    required this.basePoints,
    required this.bonusPoints,
  });

  int get totalPoints => basePoints + bonusPoints;
}
