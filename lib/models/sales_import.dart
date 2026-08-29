/// A branch/shift sales total imported from CSV data.
class SalesImport {
  final String id;
  final String branchId;
  final String? shiftId;
  final DateTime saleDate;
  final String source;
  final String salesSource;
  final double totalAmount;
  final String importedBy;
  final DateTime importedAt;
  final String? externalReference;

  final String? branchName;
  final String? shiftName;
  final String? importedByName;

  const SalesImport({
    required this.id,
    required this.branchId,
    this.shiftId,
    required this.saleDate,
    required this.source,
    this.salesSource = 'csv_upload',
    required this.totalAmount,
    required this.importedBy,
    required this.importedAt,
    this.externalReference,
    this.branchName,
    this.shiftName,
    this.importedByName,
  });

  factory SalesImport.fromMap(Map<String, dynamic> map) {
    final branchData = _nestedMap(map['branches']);
    final shiftData = _nestedMap(map['shifts']);
    final profileData = _nestedMap(map['profiles']);

    return SalesImport(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      saleDate: DateTime.parse(map['sale_date'] as String),
      source: map['source'] as String? ?? 'csv_upload',
      salesSource: map['sales_source'] as String? ?? 'csv_upload',
      totalAmount: (map['total_amount'] as num).toDouble(),
      importedBy: map['imported_by'] as String,
      importedAt: DateTime.parse(map['imported_at'] as String),
      externalReference: map['external_reference'] as String?,
      branchName: branchData?['name'] as String?,
      shiftName: shiftData?['name'] as String?,
      importedByName: profileData?['name'] as String?,
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
}
