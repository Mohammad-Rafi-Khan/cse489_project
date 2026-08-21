import 'competition_branch.dart';
import 'competition_product.dart';
import 'branch_leaderboard_entry.dart';

/// Represents an inter-branch product competition.
class Competition {
  final String id;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'upcoming' | 'active' | 'ended' | 'cancelled'
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;

  // Joined details
  final List<CompetitionBranch> branches;
  final List<CompetitionProduct> products;
  final List<BranchLeaderboardEntry> leaderboard;

  const Competition({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isActive,
    this.createdBy,
    required this.createdAt,
    this.branches = const [],
    this.products = const [],
    this.leaderboard = const [],
  });

  factory Competition.fromMap(Map<String, dynamic> map) {
    List<CompetitionBranch> bList = [];
    if (map['competition_branches'] is List) {
      bList = (map['competition_branches'] as List)
          .map((e) => CompetitionBranch.fromMap(e as Map<String, dynamic>))
          .toList();
    }

    List<CompetitionProduct> pList = [];
    if (map['competition_products'] is List) {
      pList = (map['competition_products'] as List)
          .map((e) => CompetitionProduct.fromMap(e as Map<String, dynamic>))
          .toList();
    }

    List<BranchLeaderboardEntry> lList = [];
    if (map['branch_leaderboard_entries'] is List) {
      lList = (map['branch_leaderboard_entries'] as List)
          .map((e) => BranchLeaderboardEntry.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => (a.currentRank ?? 999).compareTo(b.currentRank ?? 999));
    }

    return Competition(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      status: map['status'] as String? ?? 'active',
      isActive: map['is_active'] as bool? ?? true,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      branches: bList,
      products: pList,
      leaderboard: lList,
    );
  }

  bool get isUpcoming => status == 'upcoming';
  bool get isActiveStatus => status == 'active';
  bool get isEnded => status == 'ended';
}
