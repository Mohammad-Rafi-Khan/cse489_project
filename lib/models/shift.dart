/// Represents a work shift stored in the `shifts` table.
class Shift {
  final String id;
  final String branchId;
  final String name;
  final String startTime; // stored as 'HH:MM:SS' from Postgres time type
  final String endTime;
  final bool isActive;
  final DateTime createdAt;

  const Shift({
    required this.id,
    required this.branchId,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isActive,
    required this.createdAt,
  });

  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Returns a human-readable time range label, e.g. "08:00 - 16:00".
  String get timeRange {
    String fmt(String t) {
      final parts = t.split(':');
      if (parts.length < 2) return t;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts[1].padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$displayH:$m $period';
    }

    return '${fmt(startTime)} - ${fmt(endTime)}';
  }

  @override
  String toString() => name;
}
