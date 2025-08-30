class Bill {
  final String id;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final double totalUnits;
  final double totalAmount;
  final String status; // 'paid', 'unpaid', 'overdue'
  final DateTime generatedAt;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  Bill({
    required this.id,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.totalUnits,
    required this.totalAmount,
    this.status = 'unpaid',
    required this.generatedAt,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'],
      userId: json['user_id'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      totalUnits: json['total_units'],
      totalAmount: json['total_amount'],
      status: json['status'] ?? 'unpaid',
      generatedAt: DateTime.parse(json['generated_at']),
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'totalUnits': totalUnits,
      'totalAmount': totalAmount,
      'status': status,
      'generatedAt': generatedAt.toIso8601String(),
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}