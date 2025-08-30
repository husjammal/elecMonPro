import 'dart:convert';

class User {
  final String id;
  final String email;
  final String name;
  final String passwordHash;
  final DateTime createdAt;
  final Map<String, dynamic> settings;
  final bool isSynced;
  final DateTime? lastSyncedAt;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.passwordHash,
    required this.createdAt,
    required this.settings,
    this.isSynced = false,
    this.lastSyncedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      passwordHash: json['password_hash'],
      createdAt: DateTime.parse(json['created_at']),
      settings: json['settings'] != null ? jsonDecode(json['settings']) : {},
      isSynced: json['is_synced'] == 1,
      lastSyncedAt: json['last_synced_at'] != null ? DateTime.parse(json['last_synced_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'passwordHash': passwordHash,
      'createdAt': createdAt.toIso8601String(),
      'settings': settings,
      'isSynced': isSynced,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }
}