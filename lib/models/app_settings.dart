class AppSettings {
  final String id;
  final String userId;
  final String theme;
  final bool notificationEnabled;
  final bool autoBackup;
  final bool ocrEnabled;
  final bool voiceOverEnabled;
  final bool highContrastEnabled;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  AppSettings({
    required this.id,
    required this.userId,
    this.theme = 'light',
    this.notificationEnabled = true,
    this.autoBackup = true,
    this.ocrEnabled = true,
    this.voiceOverEnabled = false,
    this.highContrastEnabled = false,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      id: json['id'],
      userId: json['user_id'],
      theme: json['theme'] ?? 'light',
      notificationEnabled: json['notification_enabled'] == 1,
      autoBackup: json['auto_backup'] == 1,
      ocrEnabled: json['ocr_enabled'] == 1,
      voiceOverEnabled: json['voice_over_enabled'] == 1,
      highContrastEnabled: json['high_contrast_enabled'] == 1,
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'theme': theme,
      'notificationEnabled': notificationEnabled,
      'autoBackup': autoBackup,
      'ocrEnabled': ocrEnabled,
      'voiceOverEnabled': voiceOverEnabled,
      'highContrastEnabled': highContrastEnabled,
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}