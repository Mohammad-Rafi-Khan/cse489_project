/// Represents a qualifying product and its point multiplier in a competition.
class CompetitionProduct {
  final String id;
  final String competitionId;
  final String productId;
  final int pointsPerUnit;

  // Joined display fields
  final String? productName;
  final String? productCategory;
  final double? unitPrice;

  const CompetitionProduct({
    required this.id,
    required this.competitionId,
    required this.productId,
    required this.pointsPerUnit,
    this.productName,
    this.productCategory,
    this.unitPrice,
  });

  factory CompetitionProduct.fromMap(Map<String, dynamic> map) {
    final productData = map['products'] as Map<String, dynamic>?;

    return CompetitionProduct(
      id: map['id'] as String,
      competitionId: map['competition_id'] as String,
      productId: map['product_id'] as String,
      pointsPerUnit: map['points_per_unit'] as int? ?? 1,
      productName: productData?['name'] as String?,
      productCategory: productData?['category'] as String?,
      unitPrice: (productData?['unit_price'] as num?)?.toDouble(),
    );
  }
}
