import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import '../models/user.dart';
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../models/bill.dart';
import '../models/notification.dart';
import '../models/app_settings.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _syncTimer;

  // Sync status
  bool _isOnline = false;
  bool _isSyncing = false;
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  // Initialize sync service
  Future<void> initialize() async {
    // Initialize connectivity monitoring
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _onConnectivityChanged(result);

    // Initialize WorkManager for background sync
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

    // Register background sync task
    await Workmanager().registerPeriodicTask(
      'syncTask',
      'backgroundSync',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    // Start periodic sync when online
    _startPeriodicSync();
  }

  void _onConnectivityChanged(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (!wasOnline && _isOnline) {
      // Came back online, trigger sync
      performFullSync();
    }

    _syncStatusController.add(SyncStatus(
      isOnline: _isOnline,
      isSyncing: _isSyncing,
      lastSyncTime: DateTime.now(),
    ));
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isOnline && !_isSyncing) {
        performIncrementalSync();
      }
    });
  }

  Future<void> performFullSync() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    _syncStatusController.add(SyncStatus(
      isOnline: _isOnline,
      isSyncing: true,
      lastSyncTime: DateTime.now(),
    ));

    try {
      await _syncAllData();
    } catch (e) {
      debugPrint('Full sync failed: $e');
    } finally {
      _isSyncing = false;
      _syncStatusController.add(SyncStatus(
        isOnline: _isOnline,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      ));
    }
  }

  Future<void> performIncrementalSync() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    _syncStatusController.add(SyncStatus(
      isOnline: _isOnline,
      isSyncing: true,
      lastSyncTime: DateTime.now(),
    ));

    try {
      await _syncUnsyncedData();
    } catch (e) {
      debugPrint('Incremental sync failed: $e');
    } finally {
      _isSyncing = false;
      _syncStatusController.add(SyncStatus(
        isOnline: _isOnline,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      ));
    }
  }

  Future<void> _syncAllData() async {
    // Sync users
    final users = await _databaseService.getUnsyncedUsers();
    await _syncUsers(users);

    // Sync meter readings
    final readings = await _databaseService.getUnsyncedMeterReadings();
    await _syncMeterReadings(readings);

    // Sync pricing tiers
    final tiers = await _databaseService.getUnsyncedPricingTiers();
    await _syncPricingTiers(tiers);

    // Sync bills
    final bills = await _databaseService.getUnsyncedBills();
    await _syncBills(bills);

    // Sync notifications
    final notifications = await _databaseService.getUnsyncedNotifications();
    await _syncNotifications(notifications);

    // Sync app settings
    final settings = await _databaseService.getUnsyncedAppSettings();
    await _syncAppSettings(settings);
  }

  Future<void> _syncUnsyncedData() async {
    // Similar to _syncAllData but optimized for incremental sync
    await _syncAllData();
  }

  Future<void> _syncUsers(List<User> users) async {
    for (final user in users) {
      try {
        // Simulate API call to sync user
        await _simulateApiCall('syncUser', user.toJson());
        await _databaseService.markAsSynced('users', user.id);
      } catch (e) {
        debugPrint('Failed to sync user ${user.id}: $e');
        // Handle conflict resolution
        await _handleUserConflict(user);
      }
    }
  }

  Future<void> _syncMeterReadings(List<MeterReading> readings) async {
    for (final reading in readings) {
      try {
        await _simulateApiCall('syncMeterReading', reading.toJson());
        await _databaseService.markAsSynced('meter_readings', reading.id);
      } catch (e) {
        debugPrint('Failed to sync reading ${reading.id}: $e');
        await _handleReadingConflict(reading);
      }
    }
  }

  Future<void> _syncPricingTiers(List<PricingTier> tiers) async {
    for (final tier in tiers) {
      try {
        await _simulateApiCall('syncPricingTier', tier.toJson());
        await _databaseService.markAsSynced('pricing_tiers', tier.id);
      } catch (e) {
        debugPrint('Failed to sync tier ${tier.id}: $e');
        await _handleTierConflict(tier);
      }
    }
  }

  Future<void> _syncBills(List<Bill> bills) async {
    for (final bill in bills) {
      try {
        await _simulateApiCall('syncBill', bill.toJson());
        await _databaseService.markAsSynced('bills', bill.id);
      } catch (e) {
        debugPrint('Failed to sync bill ${bill.id}: $e');
        await _handleBillConflict(bill);
      }
    }
  }

  Future<void> _syncNotifications(List<Notification> notifications) async {
    for (final notification in notifications) {
      try {
        await _simulateApiCall('syncNotification', notification.toJson());
        await _databaseService.markAsSynced('notifications', notification.id);
      } catch (e) {
        debugPrint('Failed to sync notification ${notification.id}: $e');
        await _handleNotificationConflict(notification);
      }
    }
  }

  Future<void> _syncAppSettings(List<AppSettings> settings) async {
    for (final setting in settings) {
      try {
        await _simulateApiCall('syncAppSettings', setting.toJson());
        await _databaseService.markAsSynced('app_settings', setting.id);
      } catch (e) {
        debugPrint('Failed to sync settings ${setting.id}: $e');
        await _handleSettingsConflict(setting);
      }
    }
  }

  // Conflict resolution methods
  Future<void> _handleUserConflict(User user) async {
    // Last-write-wins strategy
    // In a real app, you might want to show a dialog for user resolution
    debugPrint('Handling user conflict for ${user.id}');
  }

  Future<void> _handleReadingConflict(MeterReading reading) async {
    debugPrint('Handling reading conflict for ${reading.id}');
  }

  Future<void> _handleTierConflict(PricingTier tier) async {
    debugPrint('Handling tier conflict for ${tier.id}');
  }

  Future<void> _handleBillConflict(Bill bill) async {
    debugPrint('Handling bill conflict for ${bill.id}');
  }

  Future<void> _handleNotificationConflict(Notification notification) async {
    debugPrint('Handling notification conflict for ${notification.id}');
  }

  Future<void> _handleSettingsConflict(AppSettings settings) async {
    debugPrint('Handling settings conflict for ${settings.id}');
  }

  // Simulate API call (replace with actual Firebase/Cloud API calls)
  Future<void> _simulateApiCall(String endpoint, Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
    // In real implementation, make actual HTTP calls to your backend
    debugPrint('API Call: $endpoint with data: ${jsonEncode(data)}');
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}

// Background task callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final syncService = SyncService();
      await syncService.initialize();
      await syncService.performFullSync();
      return true;
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return false;
    }
  });
}

// Sync status model
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final DateTime lastSyncTime;

  SyncStatus({
    required this.isOnline,
    required this.isSyncing,
    required this.lastSyncTime,
  });
}