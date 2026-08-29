import '../models/product.dart';
import '../models/shift.dart';

/// Parses and validates admin CSV sales import rows.
///
/// Required CSV columns are `batch_reference` and `total_amount`. Optional
/// columns are `shift_name`, `product_name`, and `quantity`.
class CsvSalesImportParser {
  CsvSalesImportParseResult parse(
    String csvText, {
    Map<String, Product> productsByName = const {},
    Map<String, Shift> shiftsByName = const {},
  }) {
    final rawLines = csvText
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final validRows = <CsvSalesImportRow>[];
    final failedRows = <CsvSalesImportIssue>[];
    final hasHeader = rawLines.isNotEmpty && _looksLikeHeader(rawLines.first);
    final dataLines = hasHeader ? rawLines.skip(1).toList() : rawLines;
    final productLookup = _normalizeProductLookup(productsByName);
    final shiftLookup = _normalizeShiftLookup(shiftsByName);

    for (var index = 0; index < dataLines.length; index++) {
      final rowNumber = hasHeader ? index + 2 : index + 1;
      final result = _validateRow(
        rowNumber: rowNumber,
        line: dataLines[index],
        productsByName: productLookup,
        shiftsByName: shiftLookup,
      );
      final row = result.$1;
      final issue = result.$2;
      if (row != null) {
        validRows.add(row);
      } else if (issue != null) {
        failedRows.add(issue);
      }
    }

    return CsvSalesImportParseResult(
      totalRows: validRows.length + failedRows.length,
      validRows: validRows,
      failedRows: failedRows,
    );
  }

  (CsvSalesImportRow?, CsvSalesImportIssue?) _validateRow({
    required int rowNumber,
    required String line,
    required Map<String, Product> productsByName,
    required Map<String, Shift> shiftsByName,
  }) {
    final columns = _splitCsvLine(line);
    if (columns.length < 2) {
      return (
        null,
        CsvSalesImportIssue(
          rowNumber: rowNumber,
          rawLine: line,
          reason: 'Reference and amount are required.',
        ),
      );
    }

    final reference = columns[0].trim();
    final amount = double.tryParse(columns[1].trim());
    final shiftName = columns.length > 2 ? columns[2].trim() : '';
    final productName = columns.length > 3 ? columns[3].trim() : '';
    final quantityText = columns.length > 4 ? columns[4].trim() : '';

    if (reference.isEmpty) {
      return (
        null,
        CsvSalesImportIssue(
          rowNumber: rowNumber,
          rawLine: line,
          reason: 'CSV batch reference is required.',
        ),
      );
    }
    if (amount == null || amount < 0) {
      return (
        null,
        CsvSalesImportIssue(
          rowNumber: rowNumber,
          rawLine: line,
          reason: 'Total amount must be zero or more.',
        ),
      );
    }

    final shift = shiftName.isEmpty
        ? null
        : shiftsByName[shiftName.toLowerCase()];
    if (shiftName.isNotEmpty && shift == null) {
      return (
        null,
        CsvSalesImportIssue(
          rowNumber: rowNumber,
          rawLine: line,
          reason: 'Shift "$shiftName" was not found.',
        ),
      );
    }

    Product? product;
    int? quantity;
    if (productName.isNotEmpty || quantityText.isNotEmpty) {
      product = productsByName[productName.toLowerCase()];
      quantity = int.tryParse(quantityText);
      if (product == null) {
        return (
          null,
          CsvSalesImportIssue(
            rowNumber: rowNumber,
            rawLine: line,
            reason: 'Product "$productName" is not active or was not found.',
          ),
        );
      }
      if (quantity == null || quantity <= 0) {
        return (
          null,
          CsvSalesImportIssue(
            rowNumber: rowNumber,
            rawLine: line,
            reason: 'Product quantity must be positive.',
          ),
        );
      }
    }

    return (
      CsvSalesImportRow(
        rowNumber: rowNumber,
        reference: reference,
        totalAmount: amount,
        shift: shift,
        product: product,
        quantity: quantity,
      ),
      null,
    );
  }

  Map<String, Product> _normalizeProductLookup(Map<String, Product> input) {
    return {
      for (final entry in input.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  Map<String, Shift> _normalizeShiftLookup(Map<String, Shift> input) {
    return {
      for (final entry in input.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        final hasEscapedQuote =
            inQuotes && i + 1 < line.length && line[i + 1] == '"';
        if (hasEscapedQuote) {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    values.add(buffer.toString());
    return values;
  }

  bool _looksLikeHeader(String line) {
    final lowered = line.toLowerCase();
    return lowered.contains('batch_reference') ||
        lowered.contains('total_amount') ||
        lowered.contains('shift_name');
  }
}

class CsvSalesImportParseResult {
  final int totalRows;
  final List<CsvSalesImportRow> validRows;
  final List<CsvSalesImportIssue> failedRows;

  const CsvSalesImportParseResult({
    required this.totalRows,
    required this.validRows,
    required this.failedRows,
  });
}

class CsvSalesImportRow {
  final int rowNumber;
  final String reference;
  final double totalAmount;
  final Shift? shift;
  final Product? product;
  final int? quantity;

  const CsvSalesImportRow({
    required this.rowNumber,
    required this.reference,
    required this.totalAmount,
    this.shift,
    this.product,
    this.quantity,
  });
}

class CsvSalesImportIssue {
  final int rowNumber;
  final String rawLine;
  final String reason;

  const CsvSalesImportIssue({
    required this.rowNumber,
    required this.rawLine,
    required this.reason,
  });
}
