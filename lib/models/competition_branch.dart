/// Represents a branch participating in a competition.
class CompetitionBranch {
  final String id;
  final String competitionId;
  final String branchId;
  final String? branchName;
  final String? branchLocation;

  const CompetitionBranch({
    required this.id,
    required this.competitionId,
    required this.branchId,
    this.branchName,
    this.branchLocation,
  });

  factory CompetitionBranch.fromMap(Map<String, dynamic> map) {
    final branchData = map['branches'] as Map<String, dynamic>?;

    return CompetitionBranch(
      id: map['id'] as String,
      competitionId: map['competition_id'] as String,
      branchId: map['branch_id'] as String,
      branchName: branchData?['name'] as String?,
      branchLocation: branchData?['location'] as String?,
    );
  }
}
