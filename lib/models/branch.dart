/// Represents a retail branch stored in the `branches` table.
class Branch {
  final String id;
  final String name;
  final String? location;
  final String? managerId;
  final bool isActive;

  const Branch({
    required this.id,
    required this.name,
    this.location,
    this.managerId,
    required this.isActive,
  });

  factory Branch.fromMap(Map<String, dynamic> map) {
    return Branch(
      id: map['id'] as String,
      name: map['name'] as String,
      location: map['location'] as String?,
      managerId: map['manager_id'] as String?,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  @override
  String toString() => name;
}
