/// Represents a reward badge tier from the `badges` table.
class BadgeTier {
  final String id;
  final String name; // 'Bronze', 'Silver', 'Gold', 'Platinum'
  final int minPoints;
  final String? description;
  final String iconName;

  const BadgeTier({
    required this.id,
    required this.name,
    required this.minPoints,
    this.description,
    this.iconName = 'military_tech',
  });

  factory BadgeTier.fromMap(Map<String, dynamic> map) {
    return BadgeTier(
      id: map['id'] as String,
      name: map['name'] as String,
      minPoints: map['min_points'] as int? ?? 0,
      description: map['description'] as String?,
      iconName: map['icon_name'] as String? ?? 'military_tech',
    );
  }
}
