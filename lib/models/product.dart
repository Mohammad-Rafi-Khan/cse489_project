/// Represents a product in the `products` table.
class Product {
  final String id;
  final String name;
  final String category;
  final double unitPrice;
  final bool isActive;
  final DateTime createdAt;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unitPrice,
    required this.isActive,
    required this.createdAt,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      unitPrice: (map['unit_price'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? category,
    double? unitPrice,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      unitPrice: unitPrice ?? this.unitPrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
