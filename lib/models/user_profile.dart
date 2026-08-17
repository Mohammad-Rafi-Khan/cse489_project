/// Represents a user's profile stored in the `profiles` table.
/// Supabase Auth manages the password; this table stores app-level data.
class UserProfile {
  final String id;
  final String name;
  final String email;
  final String role; // 'employee' | 'manager' | 'admin'
  final String? branchId;
  final bool isActive;
  final int totalLifetimePoints;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    required this.isActive,
    required this.totalLifetimePoints,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      role: map['role'] as String? ?? 'employee',
      branchId: map['branch_id'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      totalLifetimePoints: map['total_lifetime_points'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  bool get isEmployee => role == 'employee';
  bool get isManager => role == 'manager';
  bool get isAdmin => role == 'admin';
}
