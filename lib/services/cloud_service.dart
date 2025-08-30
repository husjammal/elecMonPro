import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path/path.dart' as path;
import 'package:workmanager/workmanager.dart';
import '../models/user.dart' as models;
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../models/bill.dart';
import '../models/notification.dart';
import '../models/app_settings.dart';
import 'database_service.dart';

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseService _databaseService = DatabaseService();

  bool _isInitialized = false;

  // Initialize Firebase
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      _isInitialized = true;

      // Initialize WorkManager for background backup
      await Workmanager().initialize(_callbackDispatcher, isInDebugMode: false);
    } catch (e) {
      throw Exception('Failed to initialize Firebase: $e');
    }
  }

  // Backup all data to Firestore
  Future<void> backupAllData(String userId) async {
    if (!_isInitialized) await initialize();
    if (_auth.currentUser == null) throw Exception('User not authenticated');

    try {
      final batch = _firestore.batch();
      final userDoc = _firestore.collection('users').doc(userId);

      // Backup users
      final users = await _databaseService.getUser(userId);
      if (users != null) {
        batch.set(userDoc, _userToFirestore(users), SetOptions(merge: true));
      }

      // Backup meter readings
      final readings = await _databaseService.getMeterReadings(userId);
      for (final reading in readings) {
        final readingDoc = userDoc.collection('meter_readings').doc(reading.id);
        batch.set(readingDoc, _meterReadingToFirestore(reading), SetOptions(merge: true));

        // Upload photo if exists
        if (reading.photoPath != null && reading.photoPath!.isNotEmpty) {
          await _uploadPhoto(reading.photoPath!, userId, reading.id);
        }
      }

      // Backup pricing tiers
      final tiers = await _databaseService.getPricingTiers(userId);
      for (final tier in tiers) {
        final tierDoc = userDoc.collection('pricing_tiers').doc(tier.id);
        batch.set(tierDoc, _pricingTierToFirestore(tier), SetOptions(merge: true));
      }

      // Backup bills
      final bills = await _databaseService.getBills(userId);
      for (final bill in bills) {
        final billDoc = userDoc.collection('bills').doc(bill.id);
        batch.set(billDoc, _billToFirestore(bill), SetOptions(merge: true));
      }

      // Backup notifications
      final notifications = await _databaseService.getNotifications(userId);
      for (final notification in notifications) {
        final notificationDoc = userDoc.collection('notifications').doc(notification.id);
        batch.set(notificationDoc, _notificationToFirestore(notification), SetOptions(merge: true));
      }

      // Backup app settings
      final settings = await _databaseService.getAppSettings(userId);
      if (settings != null) {
        final settingsDoc = userDoc.collection('app_settings').doc(settings.id);
        batch.set(settingsDoc, _appSettingsToFirestore(settings), SetOptions(merge: true));
      }

      await batch.commit();

      // Mark all data as synced
      await _markAllAsSynced(userId);

    } catch (e) {
      throw Exception('Backup failed: $e');
    }
  }

  // Restore data from Firestore
  Future<void> restoreData(String userId) async {
    if (!_isInitialized) await initialize();
    if (_auth.currentUser == null) throw Exception('User not authenticated');

    try {
      final userDoc = _firestore.collection('users').doc(userId);

      // Restore users
      final userSnapshot = await userDoc.get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.data()!;
        final user = models.User(
          id: userId,
          email: userData['email'],
          name: userData['name'],
          passwordHash: '',
          createdAt: DateTime.parse(userData['created_at']),
          settings: jsonDecode(userData['settings'] ?? '{}'),
          isSynced: true,
          lastSyncedAt: DateTime.parse(userData['last_synced_at']),
        );
        await _databaseService.insertUser(user);
      }

      // Restore meter readings
      final readingsSnapshot = await userDoc.collection('meter_readings').get();
      for (final doc in readingsSnapshot.docs) {
        final reading = _firestoreToMeterReading(doc.data(), userId, doc.id);
        await _handleMeterReadingConflict(reading);
      }

      // Restore pricing tiers
      final tiersSnapshot = await userDoc.collection('pricing_tiers').get();
      for (final doc in tiersSnapshot.docs) {
        final tier = _firestoreToPricingTier(doc.data(), userId, doc.id);
        await _handlePricingTierConflict(tier);
      }

      // Restore bills
      final billsSnapshot = await userDoc.collection('bills').get();
      for (final doc in billsSnapshot.docs) {
        final bill = _firestoreToBill(doc.data(), userId, doc.id);
        await _handleBillConflict(bill);
      }

      // Restore notifications
      final notificationsSnapshot = await userDoc.collection('notifications').get();
      for (final doc in notificationsSnapshot.docs) {
        final notification = _firestoreToNotification(doc.data(), userId, doc.id);
        await _handleNotificationConflict(notification);
      }

      // Restore app settings
      final settingsSnapshot = await userDoc.collection('app_settings').get();
      for (final doc in settingsSnapshot.docs) {
        final settings = _firestoreToAppSettings(doc.data(), userId, doc.id);
        await _handleAppSettingsConflict(settings);
      }

    } catch (e) {
      throw Exception('Restore failed: $e');
    }
  }

  // Upload photo to Firebase Storage
  Future<String?> _uploadPhoto(String localPath, String userId, String readingId) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;

      final fileName = path.basename(localPath);
      final storageRef = _storage.ref().child('users/$userId/readings/$readingId/$fileName');

      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask.whenComplete(() => null);

      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Photo upload failed: $e');
      return null;
    }
  }

  // Download photo from Firebase Storage
  Future<String?> downloadPhoto(String userId, String readingId, String fileName) async {
    try {
      final storageRef = _storage.ref().child('users/$userId/readings/$readingId/$fileName');
      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Photo download failed: $e');
      return null;
    }
  }

  // Schedule automatic backup
  Future<void> scheduleAutomaticBackup(String userId, Duration interval) async {
    await Workmanager().registerPeriodicTask(
      'autoBackup_$userId',
      'automaticBackup',
      frequency: interval,
      inputData: {'userId': userId},
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }

  // Cancel automatic backup
  Future<void> cancelAutomaticBackup(String userId) async {
    await Workmanager().cancelByUniqueName('autoBackup_$userId');
  }

  // Manual backup
  Future<void> manualBackup(String userId) async {
    await backupAllData(userId);
  }

  // Manual restore
  Future<void> manualRestore(String userId) async {
    await restoreData(userId);
  }

  // Sync unsynced data
  Future<void> syncUnsyncedData(String userId) async {
    if (!_isInitialized) await initialize();
    if (_auth.currentUser == null) throw Exception('User not authenticated');

    try {
      final batch = _firestore.batch();
      final userDoc = _firestore.collection('users').doc(userId);

      // Sync unsynced users
      final unsyncedUsers = await _databaseService.getUnsyncedUsers();
      for (final user in unsyncedUsers) {
        final userDocRef = _firestore.collection('users').doc(user.id);
        batch.set(userDocRef, _userToFirestore(user), SetOptions(merge: true));
        await _databaseService.markAsSynced('users', user.id);
      }

      // Sync unsynced readings
      final unsyncedReadings = await _databaseService.getUnsyncedMeterReadings();
      for (final reading in unsyncedReadings) {
        final readingDoc = userDoc.collection('meter_readings').doc(reading.id);
        batch.set(readingDoc, _meterReadingToFirestore(reading), SetOptions(merge: true));

        if (reading.photoPath != null && reading.photoPath!.isNotEmpty) {
          await _uploadPhoto(reading.photoPath!, userId, reading.id);
        }

        await _databaseService.markAsSynced('meter_readings', reading.id);
      }

      // Sync other data types similarly...
      final unsyncedTiers = await _databaseService.getUnsyncedPricingTiers();
      for (final tier in unsyncedTiers) {
        final tierDoc = userDoc.collection('pricing_tiers').doc(tier.id);
        batch.set(tierDoc, _pricingTierToFirestore(tier), SetOptions(merge: true));
        await _databaseService.markAsSynced('pricing_tiers', tier.id);
      }

      final unsyncedBills = await _databaseService.getUnsyncedBills();
      for (final bill in unsyncedBills) {
        final billDoc = userDoc.collection('bills').doc(bill.id);
        batch.set(billDoc, _billToFirestore(bill), SetOptions(merge: true));
        await _databaseService.markAsSynced('bills', bill.id);
      }

      final unsyncedNotifications = await _databaseService.getUnsyncedNotifications();
      for (final notification in unsyncedNotifications) {
        final notificationDoc = userDoc.collection('notifications').doc(notification.id);
        batch.set(notificationDoc, _notificationToFirestore(notification), SetOptions(merge: true));
        await _databaseService.markAsSynced('notifications', notification.id);
      }

      final unsyncedSettings = await _databaseService.getUnsyncedAppSettings();
      for (final settings in unsyncedSettings) {
        final settingsDoc = userDoc.collection('app_settings').doc(settings.id);
        batch.set(settingsDoc, _appSettingsToFirestore(settings), SetOptions(merge: true));
        await _databaseService.markAsSynced('app_settings', settings.id);
      }

      await batch.commit();

    } catch (e) {
      throw Exception('Sync failed: $e');
    }
  }

  // Conflict resolution methods
  Future<void> _handleMeterReadingConflict(MeterReading reading) async {
    final existing = await _databaseService.getMeterReading(reading.id);
    if (existing == null) {
      await _databaseService.insertMeterReading(reading);
    } else {
      // Last-write-wins strategy
      if (reading.lastSyncedAt != null && existing.lastSyncedAt != null) {
        if (reading.lastSyncedAt!.isAfter(existing.lastSyncedAt!)) {
          await _databaseService.updateMeterReading(reading);
        }
      } else {
        await _databaseService.updateMeterReading(reading);
      }
    }
  }

  Future<void> _handlePricingTierConflict(PricingTier tier) async {
    final existing = await _databaseService.getPricingTier(tier.id);
    if (existing == null) {
      await _databaseService.insertPricingTier(tier);
    } else {
      if (tier.lastSyncedAt != null && existing.lastSyncedAt != null) {
        if (tier.lastSyncedAt!.isAfter(existing.lastSyncedAt!)) {
          await _databaseService.updatePricingTier(tier);
        }
      } else {
        await _databaseService.updatePricingTier(tier);
      }
    }
  }

  Future<void> _handleBillConflict(Bill bill) async {
    final existing = await _databaseService.getBill(bill.id);
    if (existing == null) {
      await _databaseService.insertBill(bill);
    } else {
      if (bill.lastSyncedAt != null && existing.lastSyncedAt != null) {
        if (bill.lastSyncedAt!.isAfter(existing.lastSyncedAt!)) {
          await _databaseService.updateBill(bill);
        }
      } else {
        await _databaseService.updateBill(bill);
      }
    }
  }

  Future<void> _handleNotificationConflict(Notification notification) async {
    final existing = await _databaseService.getNotification(notification.id);
    if (existing == null) {
      await _databaseService.insertNotification(notification);
    } else {
      if (notification.lastSyncedAt != null && existing.lastSyncedAt != null) {
        if (notification.lastSyncedAt!.isAfter(existing.lastSyncedAt!)) {
          await _databaseService.updateNotification(notification);
        }
      } else {
        await _databaseService.updateNotification(notification);
      }
    }
  }

  Future<void> _handleAppSettingsConflict(AppSettings settings) async {
    final existing = await _databaseService.getAppSettings(settings.userId);
    if (existing == null) {
      await _databaseService.insertAppSettings(settings);
    } else {
      if (settings.lastSyncedAt != null && existing.lastSyncedAt != null) {
        if (settings.lastSyncedAt!.isAfter(existing.lastSyncedAt!)) {
          await _databaseService.updateAppSettings(settings);
        }
      } else {
        await _databaseService.updateAppSettings(settings);
      }
    }
  }

  // Mark all data as synced
  Future<void> _markAllAsSynced(String userId) async {
    final now = DateTime.now().toIso8601String();

    // Update all tables with sync status
    final db = await _databaseService.database;
    await db.rawUpdate('UPDATE users SET is_synced = 1, last_synced_at = ? WHERE id = ?', [now, userId]);
    await db.rawUpdate('UPDATE meter_readings SET is_synced = 1, last_synced_at = ? WHERE user_id = ?', [now, userId]);
    await db.rawUpdate('UPDATE pricing_tiers SET is_synced = 1, last_synced_at = ? WHERE user_id = ?', [now, userId]);
    await db.rawUpdate('UPDATE bills SET is_synced = 1, last_synced_at = ? WHERE user_id = ?', [now, userId]);
    await db.rawUpdate('UPDATE notifications SET is_synced = 1, last_synced_at = ? WHERE user_id = ?', [now, userId]);
    await db.rawUpdate('UPDATE app_settings SET is_synced = 1, last_synced_at = ? WHERE user_id = ?', [now, userId]);
  }

  // Helper methods for Firestore conversion
  Map<String, dynamic> _userToFirestore(models.User user) {
    return {
      'id': user.id,
      'email': user.email,
      'name': user.name,
      'created_at': user.createdAt.toIso8601String(),
      'settings': jsonEncode(user.settings),
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _meterReadingToFirestore(MeterReading reading) {
    return {
      'id': reading.id,
      'user_id': reading.userId,
      'reading_value': reading.readingValue,
      'date': reading.date.toIso8601String(),
      'photo_path': reading.photoPath,
      'notes': reading.notes,
      'is_manual': reading.isManual,
      'consumption': reading.consumption,
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _pricingTierToFirestore(PricingTier tier) {
    return {
      'id': tier.id,
      'user_id': tier.userId,
      'name': tier.name,
      'rate_per_unit': tier.ratePerUnit,
      'threshold': tier.threshold,
      'inflation_factor': tier.inflationFactor,
      'start_date': tier.startDate.toIso8601String(),
      'end_date': tier.endDate?.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _billToFirestore(Bill bill) {
    return {
      'id': bill.id,
      'user_id': bill.userId,
      'start_date': bill.startDate.toIso8601String(),
      'end_date': bill.endDate.toIso8601String(),
      'total_units': bill.totalUnits,
      'total_amount': bill.totalAmount,
      'status': bill.status,
      'generated_at': bill.generatedAt.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _notificationToFirestore(Notification notification) {
    return {
      'id': notification.id,
      'user_id': notification.userId,
      'type': notification.type,
      'message': notification.message,
      'date': notification.date.toIso8601String(),
      'is_read': notification.isRead,
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _appSettingsToFirestore(AppSettings settings) {
    return {
      'id': settings.id,
      'user_id': settings.userId,
      'theme': settings.theme,
      'notification_enabled': settings.notificationEnabled,
      'auto_backup': settings.autoBackup,
      'ocr_enabled': settings.ocrEnabled,
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  // Helper methods for Firestore to model conversion
  models.User _firestoreToUser(Map<String, dynamic> data, String id) {
    return models.User(
      id: id,
      email: data['email'],
      name: data['name'],
      passwordHash: '',
      createdAt: DateTime.parse(data['created_at']),
      settings: jsonDecode(data['settings'] ?? '{}'),
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

  MeterReading _firestoreToMeterReading(Map<String, dynamic> data, String userId, String id) {
    return MeterReading(
      id: id,
      userId: userId,
      readingValue: data['reading_value'],
      date: DateTime.parse(data['date']),
      photoPath: data['photo_path'],
      notes: data['notes'],
      isManual: data['is_manual'] ?? true,
      consumption: data['consumption'] ?? 0.0,
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

  PricingTier _firestoreToPricingTier(Map<String, dynamic> data, String userId, String id) {
    return PricingTier(
      id: id,
      userId: userId,
      name: data['name'],
      ratePerUnit: data['rate_per_unit'],
      threshold: data['threshold'],
      inflationFactor: data['inflation_factor'] ?? 0.0,
      startDate: DateTime.parse(data['start_date']),
      endDate: data['end_date'] != null ? DateTime.parse(data['end_date']) : null,
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

  Bill _firestoreToBill(Map<String, dynamic> data, String userId, String id) {
    return Bill(
      id: id,
      userId: userId,
      startDate: DateTime.parse(data['start_date']),
      endDate: DateTime.parse(data['end_date']),
      totalUnits: data['total_units'],
      totalAmount: data['total_amount'],
      status: data['status'],
      generatedAt: DateTime.parse(data['generated_at']),
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

  Notification _firestoreToNotification(Map<String, dynamic> data, String userId, String id) {
    return Notification(
      id: id,
      userId: userId,
      type: data['type'],
      message: data['message'],
      date: DateTime.parse(data['date']),
      isRead: data['is_read'] ?? false,
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

  AppSettings _firestoreToAppSettings(Map<String, dynamic> data, String userId, String id) {
    return AppSettings(
      id: id,
      userId: userId,
      theme: data['theme'] ?? 'light',
      notificationEnabled: data['notification_enabled'] ?? true,
      autoBackup: data['auto_backup'] ?? true,
      ocrEnabled: data['ocr_enabled'] ?? true,
      isSynced: true,
      lastSyncedAt: DateTime.parse(data['last_synced_at']),
    );
  }

}

// Background task callback
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final cloudService = CloudService();
      await cloudService.initialize();

      final userId = inputData?['userId'] as String?;
      if (userId != null) {
        await cloudService.backupAllData(userId);
      }

      return true;
    } catch (e) {
      print('Background backup failed: $e');
      return false;
    }
  });
}