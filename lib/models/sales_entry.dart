/// Represents a single sales transaction from the `sales_entries` table.
class SalesEntry {
  final String id;
  final String branchId;
  final String? shiftId;
  final DateTime saleDate;
  final String employeeId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final DateTime recordedAt;

  // Joined display fields
  final String? productName;
  final String? productCategory;
  final String? employeeName;
  final String? shiftName;

  const SalesEntry({
    required this.id,
    required this.branchId,
    this.shiftId,
    required this.saleDate,
    required this.employeeId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.recordedAt,
    this.productName,
    this.productCategory,
    this.employeeName,
    this.shiftName,
  });

  factory SalesEntry.fromMap(Map<String, dynamic> map) {
    final productData = map['products'] as Map<String, dynamic>?;
    final profileData = map['profiles'] as Map<String, dynamic>?;
    final shiftData = map['shifts'] as Map<String, dynamic>?;

    return SalesEntry(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      saleDate: DateTime.parse(map['sale_date'] as String),
      employeeId: map['employee_id'] as String,
      productId: map['product_id'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      productName: productData?['name'] as String?,
      productCategory: productData?['category'] as String?,
      employeeName: profileData?['name'] as String?,
      shiftName: shiftData?['name'] as String?,
    );
  }
}
