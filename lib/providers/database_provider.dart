import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/meter_reading.dart';
import '../models/bill.dart';
import '../models/pricing_tier.dart';
import '../models/notification.dart' as models;
import '../models/app_settings.dart';

class DatabaseProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  // In-memory cache for performance
  final Map<String, List<MeterReading>> _readingsCache = {};
  final Map<String, List<Bill>> _billsCache = {};
  final Map<String, List<PricingTier>> _pricingTiersCache = {};
  final Map<String, List<models.Notification>> _notificationsCache = {};
  final Map<String, AppSettings> _appSettingsCache = {};

  // Cache expiry times
  final Map<String, DateTime> _cacheExpiry = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  List<MeterReading> _readings = [];
  List<MeterReading> _filteredReadings = [];
  List<Bill> _bills = [];
  List<PricingTier> _pricingTiers = [];
  List<models.Notification> _notifications = [];
  AppSettings? _appSettings;

  // Loading states
  bool _isLoadingReadings = false;
  bool _isLoadingBills = false;
  bool _isLoadingPricingTiers = false;
  bool _isLoadingNotifications = false;
  bool _isLoadingSettings = false;

  List<MeterReading> get readings => _readings;
  List<MeterReading> get filteredReadings => _filteredReadings;
  List<Bill> get bills => _bills;
  List<PricingTier> get pricingTiers => _pricingTiers;
  List<models.Notification> get notifications => _notifications;
  AppSettings? get appSettings => _appSettings;

  // Loading state getters
  bool get isLoadingReadings => _isLoadingReadings;
  bool get isLoadingBills => _isLoadingBills;
  bool get isLoadingPricingTiers => _isLoadingPricingTiers;
  bool get isLoadingNotifications => _isLoadingNotifications;
  bool get isLoadingSettings => _isLoadingSettings;

  // Cache management helpers
  bool _isCacheValid(String key) {
    final expiry = _cacheExpiry[key];
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  void _invalidateCache(String key) {
    _cacheExpiry.remove(key);
  }

  void _setCacheExpiry(String key) {
    _cacheExpiry[key] = DateTime.now().add(_cacheDuration);
  }

  void clearAllCache() {
    _readingsCache.clear();
    _billsCache.clear();
    _pricingTiersCache.clear();
    _notificationsCache.clear();
    _appSettingsCache.clear();
    _cacheExpiry.clear();
  }

  Future<void> loadReadings(String userId) async {
    _isLoadingReadings = true;
    notifyListeners();

    try {
      final cacheKey = 'readings_$userId';

      if (_isCacheValid(cacheKey) && _readingsCache.containsKey(cacheKey)) {
        _readings = _readingsCache[cacheKey]!;
      } else {
        _readings = await _databaseService.getMeterReadings(userId);
        _readingsCache[cacheKey] = _readings;
        _setCacheExpiry(cacheKey);
      }

      _filteredReadings = _readings; // Initially show all readings
    } catch (e) {
      debugPrint('Error loading readings: $e');
      // Keep existing data if available, otherwise set empty
      if (_readings.isEmpty) {
        _readings = [];
        _filteredReadings = [];
      }
      rethrow;
    } finally {
      _isLoadingReadings = false;
      notifyListeners();
    }
  }

  Future<void> loadFilteredReadings({
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
    _filteredReadings = await _databaseService.getFilteredMeterReadings(
      userId: userId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
      minConsumption: minConsumption,
      maxConsumption: maxConsumption,
      isManual: isManual,
      sortBy: sortBy,
      sortAscending: sortAscending,
    );
    notifyListeners();
  }

  Future<void> clearFilters(String userId) async {
    _filteredReadings = _readings;
    notifyListeners();
  }

  Future<void> loadBills(String userId) async {
    final cacheKey = 'bills_$userId';

    if (_isCacheValid(cacheKey) && _billsCache.containsKey(cacheKey)) {
      _bills = _billsCache[cacheKey]!;
    } else {
      _bills = await _databaseService.getBills(userId);
      _billsCache[cacheKey] = _bills;
      _setCacheExpiry(cacheKey);
    }

    notifyListeners();
  }

  Future<void> loadPricingTiers(String userId) async {
    final cacheKey = 'pricing_tiers_$userId';

    if (_isCacheValid(cacheKey) && _pricingTiersCache.containsKey(cacheKey)) {
      _pricingTiers = _pricingTiersCache[cacheKey]!;
    } else {
      _pricingTiers = await _databaseService.getPricingTiers(userId);
      _pricingTiersCache[cacheKey] = _pricingTiers;
      _setCacheExpiry(cacheKey);
    }

    notifyListeners();
  }

  Future<void> loadNotifications(String userId) async {
    final cacheKey = 'notifications_$userId';

    if (_isCacheValid(cacheKey) && _notificationsCache.containsKey(cacheKey)) {
      _notifications = _notificationsCache[cacheKey]!;
    } else {
      _notifications = await _databaseService.getNotifications(userId);
      _notificationsCache[cacheKey] = _notifications;
      _setCacheExpiry(cacheKey);
    }

    notifyListeners();
  }

  Future<void> loadAppSettings(String userId) async {
    final cacheKey = 'app_settings_$userId';

    if (_isCacheValid(cacheKey) && _appSettingsCache.containsKey(cacheKey)) {
      _appSettings = _appSettingsCache[cacheKey];
    } else {
      _appSettings = await _databaseService.getAppSettings(userId);
      if (_appSettings != null) {
        _appSettingsCache[cacheKey] = _appSettings!;
        _setCacheExpiry(cacheKey);
      }
    }

    notifyListeners();
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    if (_appSettings == null) {
      await _databaseService.insertAppSettings(settings);
    } else {
      await _databaseService.updateAppSettings(settings);
    }
    _appSettings = settings;
    notifyListeners();
  }

  Future<void> addReading(MeterReading reading) async {
    await _databaseService.insertMeterReading(reading);
    _invalidateCache('readings_${reading.userId}');
    await loadReadings(reading.userId);
  }

  Future<void> updateReading(MeterReading reading) async {
    await _databaseService.updateMeterReading(reading);
    _invalidateCache('readings_${reading.userId}');
    await loadReadings(reading.userId);
  }

  Future<void> deleteReading(String id, String userId) async {
    await _databaseService.deleteMeterReading(id);
    _invalidateCache('readings_$userId');
    await loadReadings(userId);
  }

  Future<void> addBill(Bill bill) async {
    await _databaseService.insertBill(bill);
    await loadBills(bill.userId);
  }

  Future<void> updateBill(Bill bill) async {
    await _databaseService.updateBill(bill);
    await loadBills(bill.userId);
  }

  Future<void> deleteBill(String id, String userId) async {
    await _databaseService.deleteBill(id);
    await loadBills(userId);
  }

  Future<void> addPricingTier(PricingTier tier) async {
    await _databaseService.insertPricingTier(tier);
    await loadPricingTiers(tier.userId);
  }

  Future<void> updatePricingTier(PricingTier tier) async {
    await _databaseService.updatePricingTier(tier);
    await loadPricingTiers(tier.userId);
  }

  Future<void> deletePricingTier(String id, String userId) async {
    await _databaseService.deletePricingTier(id);
    await loadPricingTiers(userId);
  }

  Future<double> calculateBillAmount(String userId, DateTime start, DateTime end) async {
    return await _databaseService.calculateBillAmount(userId, start, end);
  }

  Future<MeterReading?> getLastMeterReading(String userId) async {
    return await _databaseService.getLastMeterReading(userId);
  }

  Future<List<MeterReading>> getMeterReadingsByDateRange(String userId, DateTime start, DateTime end) async {
    return await _databaseService.getMeterReadingsByDateRange(userId, start, end);
  }

  Future<List<Bill>> getBillsByUserId(String userId) async {
    return await _databaseService.getBills(userId);
  }

  // Memory management
  void dispose() {
    clearAllCache();
  }
}