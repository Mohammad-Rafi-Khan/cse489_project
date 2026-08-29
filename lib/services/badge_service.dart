import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/badge.dart';

/// Handles badge tier reads and badge calculation support.
class BadgeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches all badge tiers ordered by threshold.
  Future<List<BadgeTier>> fetchBadgeTiers() async {
    final data = await _supabase
        .from('badges')
        .select()
        .order('min_points', ascending: true);

    return (data as List).map((e) => BadgeTier.fromMap(e)).toList();
  }
}
