class MeterReading {
  final String id;
  final String userId;
  final double readingValue;
  final DateTime date;
  final String? photoPath;
  final String? notes;
  final bool isManual;
  final double consumption;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  MeterReading({
    required this.id,
    required this.userId,
    required this.readingValue,
    required this.date,
    this.photoPath,
    this.notes,
    this.isManual = true,
    required this.consumption,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory MeterReading.fromJson(Map<String, dynamic> json) {
    return MeterReading(
      id: json['id'],
      userId: json['user_id'],
      readingValue: json['reading_value'],
      date: DateTime.parse(json['date']),
      photoPath: json['photo_path'],
      notes: json['notes'],
      isManual: json['is_manual'] == 1,
      consumption: json['consumption'],
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'readingValue': readingValue,
      'date': date.toIso8601String(),
      'photoPath': photoPath,
      'notes': notes,
      'isManual': isManual,
      'consumption': consumption,
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}