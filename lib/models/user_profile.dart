/// Represents a user's profile stored in the `profiles` table.
class UserProfile {
  final String id;
  final String name;
  final String email;
  final String role; // 'employee' | 'manager' | 'admin'
  final String? branchId;
  final String? currentBadgeId;
  final bool isActive;
  final int totalLifetimePoints;
  final DateTime createdAt;

  // Joined display fields
  final String? branchName;
  final String? currentBadgeName;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    this.currentBadgeId,
    required this.isActive,
    required this.totalLifetimePoints,
    required this.createdAt,
    this.branchName,
    this.currentBadgeName,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final branchData = _nestedMap(map['branches']);
    final badgeData = _nestedMap(map['badges']);

    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      role: map['role'] as String? ?? 'employee',
      branchId: map['branch_id'] as String?,
      currentBadgeId: map['current_badge_id'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      totalLifetimePoints: map['total_lifetime_points'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      branchName: branchData?['name'] as String?,
      currentBadgeName: badgeData?['name'] as String?,
    );
  }

  static Map<String, dynamic>? _nestedMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  bool get isEmployee => role == 'employee';
  bool get isManager => role == 'manager';
  bool get isAdmin => role == 'admin';

  /// Returns badge name (or computes based on standard thresholds)
  String get badgeTierName {
    if (currentBadgeName != null &&
        {'Bronze', 'Silver', 'Gold'}.contains(currentBadgeName)) {
      return currentBadgeName!;
    }
    if (totalLifetimePoints >= 3000) return 'Gold';
    if (totalLifetimePoints >= 1500) return 'Silver';
    if (totalLifetimePoints >= 500) return 'Bronze';
    return 'No Badge';
  }

  /// Next badge threshold info: target points & next badge name
  int get nextBadgeThreshold {
    if (totalLifetimePoints < 500) return 500;
    if (totalLifetimePoints < 1500) return 1500;
    if (totalLifetimePoints < 3000) return 3000;
    return 3000;
  }

  String get nextBadgeName {
    if (totalLifetimePoints < 500) return 'Bronze';
    if (totalLifetimePoints < 1500) return 'Silver';
    if (totalLifetimePoints < 3000) return 'Gold';
    return 'Max Tier';
  }

  double get badgeProgress {
    int prevMin = 0;
    int nextMin = 500;

    if (totalLifetimePoints >= 3000) return 1.0;
    if (totalLifetimePoints >= 1500) {
      prevMin = 1500;
      nextMin = 3000;
    } else if (totalLifetimePoints >= 500) {
      prevMin = 500;
      nextMin = 1500;
    }

    final span = nextMin - prevMin;
    final currentInTier = totalLifetimePoints - prevMin;
    return (currentInTier / span).clamp(0.0, 1.0);
  }
}
