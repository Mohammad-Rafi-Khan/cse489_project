/// Represents a branch's calculated rank and competition points on the leaderboard.
class BranchLeaderboardEntry {
  final String id;
  final String competitionId;
  final String branchId;
  final int totalQualifyingQty;
  final int totalCompetitionPoints;
  final int? currentRank;
  final int? previousRank;
  final DateTime updatedAt;

  // Joined display fields
  final String? branchName;
  final String? branchLocation;

  const BranchLeaderboardEntry({
    required this.id,
    required this.competitionId,
    required this.branchId,
    required this.totalQualifyingQty,
    required this.totalCompetitionPoints,
    this.currentRank,
    this.previousRank,
    required this.updatedAt,
    this.branchName,
    this.branchLocation,
  });

  factory BranchLeaderboardEntry.fromMap(Map<String, dynamic> map) {
    final branchData = map['branches'] as Map<String, dynamic>?;

    return BranchLeaderboardEntry(
      id: map['id'] as String,
      competitionId: map['competition_id'] as String,
      branchId: map['branch_id'] as String,
      totalQualifyingQty: map['total_qualifying_qty'] as int? ?? 0,
      totalCompetitionPoints: map['total_competition_points'] as int? ?? 0,
      currentRank: map['current_rank'] as int?,
      previousRank: map['previous_rank'] as int?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      branchName: branchData?['name'] as String?,
      branchLocation: branchData?['location'] as String?,
    );
  }

  /// Rank movement indicator (-1: dropped, 0: same, 1: climbed)
  int get rankMovement {
    if (previousRank == null || currentRank == null) return 0;
    if (currentRank! < previousRank!) return 1; // improved (e.g. 2 -> 1)
    if (currentRank! > previousRank!) return -1; // dropped (e.g. 1 -> 3)
    return 0;
  }
}
