class Notification {
  final String id;
  final String userId;
  final String type; // 'high_usage', 'bill_due', 'system'
  final String message;
  final DateTime date;
  final bool isRead;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  Notification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.date,
    this.isRead = false,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'],
      message: json['message'],
      date: DateTime.parse(json['date']),
      isRead: json['is_read'] == 1,
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'message': message,
      'date': date.toIso8601String(),
      'isRead': isRead,
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}