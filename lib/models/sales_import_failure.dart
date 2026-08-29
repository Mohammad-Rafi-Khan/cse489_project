/// A failed CSV sales import attempt captured for admin review.
class SalesImportFailure {
  final String id;
  final String? branchId;
  final DateTime? saleDate;
  final String source;
  final String salesSource;
  final String errorMessage;
  final String attemptedBy;
  final DateTime attemptedAt;
  final String? branchName;
  final String? attemptedByName;

  const SalesImportFailure({
    required this.id,
    this.branchId,
    this.saleDate,
    required this.source,
    this.salesSource = 'csv_upload',
    required this.errorMessage,
    required this.attemptedBy,
    required this.attemptedAt,
    this.branchName,
    this.attemptedByName,
  });

  factory SalesImportFailure.fromMap(Map<String, dynamic> map) {
    final branchData = _nestedMap(map['branches']);
    final profileData = _nestedMap(map['profiles']);

    return SalesImportFailure(
      id: map['id'] as String,
      branchId: map['branch_id'] as String?,
      saleDate: map['sale_date'] == null
          ? null
          : DateTime.parse(map['sale_date'] as String),
      source: map['source'] as String? ?? 'csv_upload',
      salesSource: map['sales_source'] as String? ?? 'csv_upload',
      errorMessage: map['error_message'] as String? ?? 'Import failed',
      attemptedBy: map['attempted_by'] as String,
      attemptedAt: DateTime.parse(map['attempted_at'] as String),
      branchName: branchData?['name'] as String?,
      attemptedByName: profileData?['name'] as String?,
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
