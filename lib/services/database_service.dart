import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user.dart';
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../models/bill.dart';
import '../models/notification.dart';
import '../models/app_settings.dart';
import 'cloud_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final CloudService _cloudService = CloudService();
  final Connectivity _connectivity = Connectivity();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<String> _getDatabaseKey() async {
    String? key = await _secureStorage.read(key: 'db_key');
    if (key == null) {
      key = base64Url.encode(List<int>.generate(32, (i) => i % 256));
      await _secureStorage.write(key: 'db_key', value: key);
    }
    return key;
  }

  Future<bool> _shouldSync(String userId) async {
    try {
      // Check if online
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return false;

      // Check if auto backup is enabled
      final settings = await getAppSettings(userId);
      return settings?.autoBackup ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'elecmonpro.db');

    final key = await _getDatabaseKey();

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute("PRAGMA key = '$key';");
        await _onCreate(db, version);
      },
    );

    // For existing database, set the key
    await db.execute("PRAGMA key = '$key';");

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        settings TEXT,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE meter_readings (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        reading_value REAL NOT NULL,
        date DATETIME NOT NULL,
        photo_path TEXT,
        notes TEXT,
        is_manual BOOLEAN DEFAULT 1,
        consumption REAL,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE pricing_tiers (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        rate_per_unit REAL NOT NULL,
        threshold REAL NOT NULL,
        inflation_factor REAL DEFAULT 0.0,
        start_date DATETIME NOT NULL,
        end_date DATETIME,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE bills (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        start_date DATETIME NOT NULL,
        end_date DATETIME NOT NULL,
        total_units REAL NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT DEFAULT 'unpaid',
        generated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL,
        message TEXT NOT NULL,
        date DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_read BOOLEAN DEFAULT 0,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        theme TEXT DEFAULT 'light',
        notification_enabled BOOLEAN DEFAULT 1,
        auto_backup BOOLEAN DEFAULT 1,
        ocr_enabled BOOLEAN DEFAULT 1,
        is_synced BOOLEAN DEFAULT 0,
        last_synced_at DATETIME,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_meter_readings_user_id ON meter_readings(user_id)');
    await db.execute('CREATE INDEX idx_meter_readings_date ON meter_readings(date)');
    await db.execute('CREATE INDEX idx_meter_readings_user_date ON meter_readings(user_id, date)');
    await db.execute('CREATE INDEX idx_meter_readings_is_synced ON meter_readings(is_synced)');
    await db.execute('CREATE INDEX idx_pricing_tiers_user_id ON pricing_tiers(user_id)');
    await db.execute('CREATE INDEX idx_bills_user_id ON bills(user_id)');
    await db.execute('CREATE INDEX idx_bills_date ON bills(generated_at)');
    await db.execute('CREATE INDEX idx_notifications_user_id ON notifications(user_id)');
    await db.execute('CREATE INDEX idx_notifications_date ON notifications(date)');
    await db.execute('CREATE INDEX idx_app_settings_user_id ON app_settings(user_id)');
  }

  // CRUD for User
  Future<int> insertUser(User user) async {
    final db = await database;
    return await db.insert('users', _userToMap(user));
  }

  Future<User?> getUser(String id) async {
    final db = await database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return User.fromJson(maps.first);
    }
    return null;
  }

  Future<int> updateUser(User user) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final userMap = _userToMap(user);
    userMap['is_synced'] = 0; // Force unsynced status
    return await db.update('users', userMap, where: 'id = ?', whereArgs: [user.id]);
  }

  Future<int> deleteUser(String id) async {
    final db = await database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD for MeterReading
  Future<int> insertMeterReading(MeterReading reading) async {
    final db = await database;
    final result = await db.insert('meter_readings', _meterReadingToMap(reading));
    await checkTierAlerts(reading.userId);

    // Trigger cloud sync if auto backup is enabled
    if (await _shouldSync(reading.userId)) {
      try {
        await _cloudService.syncUnsyncedData(reading.userId);
      } catch (e) {
        // Sync failed, but don't block the local operation
        print('Cloud sync failed: $e');
      }
    }

    return result;
  }

  Future<List<MeterReading>> getMeterReadings(String userId) async {
    final db = await database;
    final maps = await db.query('meter_readings', where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
    return maps.map((map) => MeterReading.fromJson(map)).toList();
  }

  Future<MeterReading?> getLastMeterReading(String userId) async {
    final db = await database;
    final maps = await db.query('meter_readings', where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC', limit: 1);
    if (maps.isNotEmpty) {
      return MeterReading.fromJson(maps.first);
    }
    return null;
  }

  Future<int> updateMeterReading(MeterReading reading) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final readingMap = _meterReadingToMap(reading);
    readingMap['is_synced'] = 0; // Force unsynced status
    return await db.update('meter_readings', readingMap, where: 'id = ?', whereArgs: [reading.id]);
  }

  Future<int> deleteMeterReading(String id) async {
    final db = await database;
    return await db.delete('meter_readings', where: 'id = ?', whereArgs: [id]);
  }

  Future<MeterReading?> getMeterReading(String id) async {
    final db = await database;
    final maps = await db.query('meter_readings', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return MeterReading.fromJson(maps.first);
    }
    return null;
  }

  // CRUD for PricingTier
  Future<int> insertPricingTier(PricingTier tier) async {
    final db = await database;
    final result = await db.insert('pricing_tiers', _pricingTierToMap(tier));

    // Trigger cloud sync if auto backup is enabled
    if (await _shouldSync(tier.userId)) {
      try {
        await _cloudService.syncUnsyncedData(tier.userId);
      } catch (e) {
        print('Cloud sync failed: $e');
      }
    }

    return result;
  }

  Future<List<PricingTier>> getPricingTiers(String userId) async {
    final db = await database;
    final maps = await db.query('pricing_tiers', where: 'user_id = ?', whereArgs: [userId], orderBy: 'start_date DESC');
    return maps.map((map) => PricingTier.fromJson(map)).toList();
  }

  Future<int> updatePricingTier(PricingTier tier) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final tierMap = _pricingTierToMap(tier);
    tierMap['is_synced'] = 0; // Force unsynced status
    return await db.update('pricing_tiers', tierMap, where: 'id = ?', whereArgs: [tier.id]);
  }

  Future<int> deletePricingTier(String id) async {
    final db = await database;
    return await db.delete('pricing_tiers', where: 'id = ?', whereArgs: [id]);
  }

  Future<PricingTier?> getPricingTier(String id) async {
    final db = await database;
    final maps = await db.query('pricing_tiers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return PricingTier.fromJson(maps.first);
    }
    return null;
  }

  // CRUD for Bill
  Future<int> insertBill(Bill bill) async {
    final db = await database;
    final result = await db.insert('bills', _billToMap(bill));

    // Trigger cloud sync if auto backup is enabled
    if (await _shouldSync(bill.userId)) {
      try {
        await _cloudService.syncUnsyncedData(bill.userId);
      } catch (e) {
        print('Cloud sync failed: $e');
      }
    }

    return result;
  }

  Future<List<Bill>> getBills(String userId) async {
    final db = await database;
    final maps = await db.query('bills', where: 'user_id = ?', whereArgs: [userId], orderBy: 'generated_at DESC');
    return maps.map((map) => Bill.fromJson(map)).toList();
  }

  Future<int> updateBill(Bill bill) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final billMap = _billToMap(bill);
    billMap['is_synced'] = 0; // Force unsynced status
    return await db.update('bills', billMap, where: 'id = ?', whereArgs: [bill.id]);
  }

  Future<int> deleteBill(String id) async {
    final db = await database;
    return await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  Future<Bill?> getBill(String id) async {
    final db = await database;
    final maps = await db.query('bills', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Bill.fromJson(maps.first);
    }
    return null;
  }

  // CRUD for Notification
  Future<int> insertNotification(Notification notification) async {
    final db = await database;
    return await db.insert('notifications', _notificationToMap(notification));
  }

  Future<List<Notification>> getNotifications(String userId) async {
    final db = await database;
    final maps = await db.query('notifications', where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
    return maps.map((map) => Notification.fromJson(map)).toList();
  }

  Future<int> updateNotification(Notification notification) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final notificationMap = _notificationToMap(notification);
    notificationMap['is_synced'] = 0; // Force unsynced status
    return await db.update('notifications', notificationMap, where: 'id = ?', whereArgs: [notification.id]);
  }

  Future<int> deleteNotification(String id) async {
    final db = await database;
    return await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  Future<Notification?> getNotification(String id) async {
    final db = await database;
    final maps = await db.query('notifications', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Notification.fromJson(maps.first);
    }
    return null;
  }

  // CRUD for AppSettings
  Future<int> insertAppSettings(AppSettings settings) async {
    final db = await database;
    final result = await db.insert('app_settings', _appSettingsToMap(settings));

    // Trigger cloud sync if auto backup is enabled
    if (await _shouldSync(settings.userId)) {
      try {
        await _cloudService.syncUnsyncedData(settings.userId);
      } catch (e) {
        print('Cloud sync failed: $e');
      }
    }

    return result;
  }

  Future<AppSettings?> getAppSettings(String userId) async {
    final db = await database;
    final maps = await db.query('app_settings', where: 'user_id = ?', whereArgs: [userId]);
    if (maps.isNotEmpty) {
      return AppSettings.fromJson(maps.first);
    }
    return null;
  }

  Future<int> updateAppSettings(AppSettings settings) async {
    final db = await database;
    // Mark as unsynced when updated offline
    final settingsMap = _appSettingsToMap(settings);
    settingsMap['is_synced'] = 0; // Force unsynced status
    return await db.update('app_settings', settingsMap, where: 'id = ?', whereArgs: [settings.id]);
  }

  Future<int> deleteAppSettings(String id) async {
    final db = await database;
    return await db.delete('app_settings', where: 'id = ?', whereArgs: [id]);
  }

  // Query methods
  Future<List<MeterReading>> searchMeterReadings(String userId, String query) async {
    final db = await database;
    final maps = await db.query(
      'meter_readings',
      where: 'user_id = ? AND (notes LIKE ? OR date LIKE ? OR reading_value LIKE ?)',
      whereArgs: [userId, '%$query%', '%$query%', '%$query%'],
      orderBy: 'date DESC',
    );
    return maps.map((map) => MeterReading.fromJson(map)).toList();
  }

  Future<List<MeterReading>> getFilteredMeterReadings({
    required String userId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    double? minConsumption,
    double? maxConsumption,
    bool? isManual,
    String sortBy = 'date',
    bool sortAscending = false,
  }) async {
    final db = await database;

    List<String> whereClauses = ['user_id = ?'];
    List<dynamic> whereArgs = [userId];

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClauses.add('(notes LIKE ? OR date LIKE ? OR reading_value LIKE ?)');
      whereArgs.addAll(['%$searchQuery%', '%$searchQuery%', '%$searchQuery%']);
    }

    if (startDate != null) {
      whereClauses.add('date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClauses.add('date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    if (minConsumption != null) {
      whereClauses.add('consumption >= ?');
      whereArgs.add(minConsumption);
    }

    if (maxConsumption != null) {
      whereClauses.add('consumption <= ?');
      whereArgs.add(maxConsumption);
    }

    if (isManual != null) {
      whereClauses.add('is_manual = ?');
      whereArgs.add(isManual ? 1 : 0);
    }

    String orderBy;
    switch (sortBy) {
      case 'consumption':
      case 'cost': // For now, sort by consumption as proxy for cost
        orderBy = 'consumption ${sortAscending ? 'ASC' : 'DESC'}';
        break;
      case 'reading_value':
        orderBy = 'reading_value ${sortAscending ? 'ASC' : 'DESC'}';
        break;
      case 'date':
      default:
        orderBy = 'date ${sortAscending ? 'ASC' : 'DESC'}';
        break;
    }

    final maps = await db.query(
      'meter_readings',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    return maps.map((map) => MeterReading.fromJson(map)).toList();
  }

  Future<List<MeterReading>> getMeterReadingsByDateRange(String userId, DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'meter_readings',
      where: 'user_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [userId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    return maps.map((map) => MeterReading.fromJson(map)).toList();
  }

  Future<double> calculateBillAmount(String userId, DateTime start, DateTime end) async {
    final readings = await getMeterReadingsByDateRange(userId, start, end);
    if (readings.isEmpty) return 0.0;

    final tiers = await getPricingTiers(userId);
    if (tiers.isEmpty) return 0.0;

    double totalConsumption = readings.fold(0.0, (sum, reading) => sum + reading.consumption);

    // Sort tiers by threshold ascending
    tiers.sort((a, b) => a.threshold.compareTo(b.threshold));

    double totalCost = 0.0;
    double remainingConsumption = totalConsumption;

    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      double consumptionInTier = 0.0;

      if (i == 0) {
        // First tier: 0 to threshold
        consumptionInTier = remainingConsumption < tier.threshold ? remainingConsumption : tier.threshold;
      } else {
        // Subsequent tiers: from previous threshold to current
        final prevThreshold = tiers[i - 1].threshold;
        final currentThreshold = tier.threshold;
        if (remainingConsumption > prevThreshold) {
          consumptionInTier = (remainingConsumption < currentThreshold ? remainingConsumption : currentThreshold) - prevThreshold;
        }
      }

      if (consumptionInTier > 0) {
        // Apply inflation adjustment
        final yearsSinceStart = DateTime.now().difference(tier.startDate).inDays / 365.0;
        final adjustedRate = tier.ratePerUnit * pow(1 + tier.inflationFactor, yearsSinceStart);

        totalCost += consumptionInTier * adjustedRate;
        remainingConsumption -= consumptionInTier;
      }

      if (remainingConsumption <= 0) break;
    }

    // If consumption exceeds all tiers, use the last tier's rate for remaining
    if (remainingConsumption > 0 && tiers.isNotEmpty) {
      final lastTier = tiers.last;
      final yearsSinceStart = DateTime.now().difference(lastTier.startDate).inDays / 365.0;
      final adjustedRate = lastTier.ratePerUnit * pow(1 + lastTier.inflationFactor, yearsSinceStart);
      totalCost += remainingConsumption * adjustedRate;
    }

    return totalCost;
  }

  Future<void> checkTierAlerts(String userId) async {
    final db = await database;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1).subtract(const Duration(days: 1));

    final readings = await getMeterReadingsByDateRange(userId, startOfMonth, endOfMonth);
    if (readings.isEmpty) return;

    double totalConsumption = readings.fold(0.0, (sum, reading) => sum + reading.consumption);

    final tiers = await getPricingTiers(userId);
    if (tiers.isEmpty) return;

    tiers.sort((a, b) => a.threshold.compareTo(b.threshold));

    for (final tier in tiers) {
      final threshold = tier.threshold;
      final approachThreshold = threshold * 0.9;

      if (totalConsumption >= approachThreshold && totalConsumption < threshold) {
        // Approaching threshold
        final existing = await db.query(
          'notifications',
          where: 'user_id = ? AND type = ? AND message LIKE ?',
          whereArgs: [userId, 'tier_approach', '%${tier.name}%'],
        );
        if (existing.isEmpty) {
          final notification = Notification(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: userId,
            type: 'tier_approach',
            message: 'Consumption approaching ${tier.name} threshold (${threshold.toStringAsFixed(0)} kWh). Current: ${totalConsumption.toStringAsFixed(0)} kWh.',
            date: DateTime.now(),
          );
          await insertNotification(notification);
        }
      } else if (totalConsumption >= threshold) {
        // Exceeding threshold
        final existing = await db.query(
          'notifications',
          where: 'user_id = ? AND type = ? AND message LIKE ?',
          whereArgs: [userId, 'tier_exceed', '%${tier.name}%'],
        );
        if (existing.isEmpty) {
          final notification = Notification(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            userId: userId,
            type: 'tier_exceed',
            message: 'Consumption exceeded ${tier.name} threshold (${threshold.toStringAsFixed(0)} kWh). Current: ${totalConsumption.toStringAsFixed(0)} kWh.',
            date: DateTime.now(),
          );
          await insertNotification(notification);
        }
      }
    }
  }

  Future<List<Bill>> getUnpaidBills(String userId) async {
    final db = await database;
    final maps = await db.query(
      'bills',
      where: 'user_id = ? AND status != ?',
      whereArgs: [userId, 'paid'],
      orderBy: 'generated_at DESC',
    );
    return maps.map((map) => Bill.fromJson(map)).toList();
  }

  // Sync methods
  Future<List<User>> getUnsyncedUsers() async {
    final db = await database;
    final maps = await db.query('users', where: 'is_synced = 0');
    return maps.map((map) => User.fromJson(map)).toList();
  }

  Future<List<MeterReading>> getUnsyncedMeterReadings() async {
    final db = await database;
    final maps = await db.query('meter_readings', where: 'is_synced = 0');
    return maps.map((map) => MeterReading.fromJson(map)).toList();
  }

  Future<List<PricingTier>> getUnsyncedPricingTiers() async {
    final db = await database;
    final maps = await db.query('pricing_tiers', where: 'is_synced = 0');
    return maps.map((map) => PricingTier.fromJson(map)).toList();
  }

  Future<List<Bill>> getUnsyncedBills() async {
    final db = await database;
    final maps = await db.query('bills', where: 'is_synced = 0');
    return maps.map((map) => Bill.fromJson(map)).toList();
  }

  Future<List<Notification>> getUnsyncedNotifications() async {
    final db = await database;
    final maps = await db.query('notifications', where: 'is_synced = 0');
    return maps.map((map) => Notification.fromJson(map)).toList();
  }

  Future<List<AppSettings>> getUnsyncedAppSettings() async {
    final db = await database;
    final maps = await db.query('app_settings', where: 'is_synced = 0');
    return maps.map((map) => AppSettings.fromJson(map)).toList();
  }

  Future<void> markAsSynced(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {'is_synced': 1, 'last_synced_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Merge data from cloud (handle conflicts)
  Future<void> mergeFromCloud(String userId) async {
    try {
      await _cloudService.restoreData(userId);
    } catch (e) {
      print('Merge from cloud failed: $e');
      // Continue with local data if merge fails
    }
  }

  // Force sync all data
  Future<void> forceSyncAll(String userId) async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        await _cloudService.syncUnsyncedData(userId);
      }
    } catch (e) {
      print('Force sync failed: $e');
    }
  }

  // Helper methods to convert models to maps
  Map<String, dynamic> _userToMap(User user) {
    return {
      'id': user.id,
      'email': user.email,
      'name': user.name,
      'password_hash': user.passwordHash,
      'created_at': user.createdAt.toIso8601String(),
      'settings': jsonEncode(user.settings),
      'is_synced': user.isSynced ? 1 : 0,
      'last_synced_at': user.lastSyncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _meterReadingToMap(MeterReading reading) {
    return {
      'id': reading.id,
      'user_id': reading.userId,
      'reading_value': reading.readingValue,
      'date': reading.date.toIso8601String(),
      'photo_path': reading.photoPath,
      'notes': reading.notes,
      'is_manual': reading.isManual ? 1 : 0,
      'consumption': reading.consumption,
      'is_synced': reading.isSynced ? 1 : 0,
      'last_synced_at': reading.lastSyncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _pricingTierToMap(PricingTier tier) {
    return {
      'id': tier.id,
      'user_id': tier.userId,
      'name': tier.name,
      'rate_per_unit': tier.ratePerUnit,
      'threshold': tier.threshold,
      'inflation_factor': tier.inflationFactor,
      'start_date': tier.startDate.toIso8601String(),
      'end_date': tier.endDate?.toIso8601String(),
      'is_synced': tier.isSynced ? 1 : 0,
      'last_synced_at': tier.lastSyncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _billToMap(Bill bill) {
    return {
      'id': bill.id,
      'user_id': bill.userId,
      'start_date': bill.startDate.toIso8601String(),
      'end_date': bill.endDate.toIso8601String(),
      'total_units': bill.totalUnits,
      'total_amount': bill.totalAmount,
      'status': bill.status,
      'generated_at': bill.generatedAt.toIso8601String(),
      'is_synced': bill.isSynced ? 1 : 0,
      'last_synced_at': bill.lastSyncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _notificationToMap(Notification notification) {
    return {
      'id': notification.id,
      'user_id': notification.userId,
      'type': notification.type,
      'message': notification.message,
      'date': notification.date.toIso8601String(),
      'is_read': notification.isRead ? 1 : 0,
      'is_synced': notification.isSynced ? 1 : 0,
      'last_synced_at': notification.lastSyncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _appSettingsToMap(AppSettings settings) {
    return {
      'id': settings.id,
      'user_id': settings.userId,
      'theme': settings.theme,
      'notification_enabled': settings.notificationEnabled ? 1 : 0,
      'auto_backup': settings.autoBackup ? 1 : 0,
      'ocr_enabled': settings.ocrEnabled ? 1 : 0,
      'is_synced': settings.isSynced ? 1 : 0,
      'last_synced_at': settings.lastSyncedAt?.toIso8601String(),
    };
  }
}