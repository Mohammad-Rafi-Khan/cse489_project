/// Represents a product in the `products` table.
class Product {
  final String id;
  final String name;
  final String category;
  final double currentPrice;
  final String? branchId;
  final String? updatedBy;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    this.currentPrice = 0,
    this.branchId,
    this.updatedBy,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawPrice = map['current_price'];
    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : rawPrice is String
        ? double.tryParse(rawPrice) ?? 0
        : 0.0;

    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String? ?? 'General',
      currentPrice: parsedPrice,
      branchId: map['branch_id'] as String?,
      updatedBy: map['updated_by'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? category,
    double? currentPrice,
    String? branchId,
    String? updatedBy,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      currentPrice: currentPrice ?? this.currentPrice,
      branchId: branchId ?? this.branchId,
      updatedBy: updatedBy ?? this.updatedBy,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
