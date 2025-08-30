class PricingTier {
  final String id;
  final String userId;
  final String name;
  final double ratePerUnit;
  final double threshold; // Upper limit in kWh for this tier
  final double inflationFactor; // Annual inflation adjustment factor (e.g., 0.05 for 5%)
  final DateTime startDate;
  final DateTime? endDate;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  PricingTier({
    required this.id,
    required this.userId,
    required this.name,
    required this.ratePerUnit,
    required this.threshold,
    this.inflationFactor = 0.0,
    required this.startDate,
    this.endDate,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory PricingTier.fromJson(Map<String, dynamic> json) {
    return PricingTier(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      ratePerUnit: json['rate_per_unit'],
      threshold: json['threshold'] ?? 0.0,
      inflationFactor: json['inflation_factor'] ?? 0.0,
      startDate: DateTime.parse(json['start_date']),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'ratePerUnit': ratePerUnit,
      'threshold': threshold,
      'inflationFactor': inflationFactor,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}