import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';
import '../models/notification.dart' as app_notification;
import '../models/bill.dart';
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../models/app_settings.dart';
import '../models/user.dart';
import 'database_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final DatabaseService _databaseService = DatabaseService();

  bool _initialized = false;
  Timer? _usageCheckTimer;

  // Notification channels
  static const String _billChannelId = 'bill_reminders';
  static const String _usageChannelId = 'usage_alerts';
  static const String _suggestionChannelId = 'energy_suggestions';

  static const String _billChannelName = 'Bill Reminders';
  static const String _usageChannelName = 'Usage Alerts';
  static const String _suggestionChannelName = 'Energy Saving Suggestions';

  static const String _billChannelDescription = 'Reminders for upcoming bill due dates';
  static const String _usageChannelDescription = 'Alerts for high usage and tier thresholds';
  static const String _suggestionChannelDescription = 'Personalized energy saving tips';

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _createNotificationChannels();

    _initialized = true;

    // Start periodic usage monitoring
    _startUsageMonitoring();
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel billChannel = AndroidNotificationChannel(
      _billChannelId,
      _billChannelName,
      description: _billChannelDescription,
      importance: Importance.high,
      playSound: true,
    );

    const AndroidNotificationChannel usageChannel = AndroidNotificationChannel(
      _usageChannelId,
      _usageChannelName,
      description: _usageChannelDescription,
      importance: Importance.high,
      playSound: true,
    );

    const AndroidNotificationChannel suggestionChannel = AndroidNotificationChannel(
      _suggestionChannelId,
      _suggestionChannelName,
      description: _suggestionChannelDescription,
      importance: Importance.defaultImportance,
      playSound: false,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(billChannel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(usageChannel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(suggestionChannel);
  }

  Future<bool> requestPermissions() async {
    // Permissions are requested during initialization via InitializationSettings
    // For iOS, permissions are requested in DarwinInitializationSettings
    // For Android, permissions are granted when the app is installed
    // This method can be used to check if permissions are granted
    final bool? androidGranted = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();

    return androidGranted ?? true; // Assume granted for other platforms
  }

  void _onNotificationTapped(NotificationResponse notificationResponse) {
    // Handle notification tap - could navigate to specific screens
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      // Parse payload and handle navigation
      print('Notification tapped with payload: $payload');
    }
  }

  // Bill reminder scheduling
  Future<void> scheduleBillReminder(String userId, Bill bill) async {
    final settings = await _databaseService.getAppSettings(userId);
    if (settings == null || !settings.notificationEnabled) return;

    final dueDate = bill.endDate;
    final reminderDate = dueDate.subtract(const Duration(days: 3)); // 3 days before due date

    if (reminderDate.isBefore(DateTime.now())) return; // Don't schedule past reminders

    final notificationId = bill.id.hashCode;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _billChannelId,
      _billChannelName,
      channelDescription: _billChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Bill Due Soon',
      'Your electricity bill of \$${bill.totalAmount.toStringAsFixed(2)} is due on ${dueDate.toString().split(' ')[0]}',
      tz.TZDateTime.from(reminderDate, tz.local),
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'bill:${bill.id}',
    );

    // Store notification in database
    final dbNotification = app_notification.Notification(
      id: 'bill_reminder_${bill.id}',
      userId: userId,
      type: 'bill_due',
      message: 'Bill reminder scheduled for ${dueDate.toString().split(' ')[0]}',
      date: DateTime.now(),
    );
    await _databaseService.insertNotification(dbNotification);
  }

  Future<void> cancelBillReminder(String billId) async {
    final notificationId = billId.hashCode;
    await _flutterLocalNotificationsPlugin.cancel(notificationId);
  }

  // Usage threshold monitoring
  void _startUsageMonitoring() {
    _usageCheckTimer = Timer.periodic(const Duration(hours: 6), (timer) async {
      await _checkUsageThresholds();
    });
  }

  Future<void> _checkUsageThresholds() async {
    final users = await _databaseService.getUnsyncedUsers(); // Get all users for simplicity
    for (final user in users) {
      await _checkUserUsageThresholds(user.id);
    }
  }

  Future<void> _checkUserUsageThresholds(String userId) async {
    final settings = await _databaseService.getAppSettings(userId);
    if (settings == null || !settings.notificationEnabled) return;

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final readings = await _databaseService.getMeterReadingsByDateRange(userId, startOfMonth, now);

    if (readings.isEmpty) return;

    final totalConsumption = readings.fold<double>(0.0, (sum, reading) => sum + reading.consumption);
    final tiers = await _databaseService.getPricingTiers(userId);

    if (tiers.isEmpty) return;

    tiers.sort((a, b) => a.threshold.compareTo(b.threshold));

    for (final tier in tiers) {
      final threshold = tier.threshold;
      final approachThreshold = threshold * 0.9;

      if (totalConsumption >= approachThreshold && totalConsumption < threshold) {
        await _sendUsageAlert(userId, 'approaching', tier.name, threshold, totalConsumption);
      } else if (totalConsumption >= threshold) {
        await _sendUsageAlert(userId, 'exceeded', tier.name, threshold, totalConsumption);
      }
    }
  }

  Future<void> _sendUsageAlert(String userId, String type, String tierName, double threshold, double currentUsage) async {
    final notificationId = '${userId}_${tierName}_${type}_${DateTime.now().millisecondsSinceEpoch}'.hashCode;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _usageChannelId,
      _usageChannelName,
      channelDescription: _usageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    final message = type == 'approaching'
        ? 'Your electricity usage is approaching the $tierName threshold (${threshold.toStringAsFixed(0)} kWh). Current: ${currentUsage.toStringAsFixed(0)} kWh.'
        : 'Your electricity usage has exceeded the $tierName threshold (${threshold.toStringAsFixed(0)} kWh). Current: ${currentUsage.toStringAsFixed(0)} kWh.';

    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      'High Usage Alert',
      message,
      platformChannelSpecifics,
      payload: 'usage:$userId',
    );

    // Store notification in database
    final dbNotification = app_notification.Notification(
      id: 'usage_alert_${notificationId}',
      userId: userId,
      type: 'high_usage',
      message: message,
      date: DateTime.now(),
    );
    await _databaseService.insertNotification(dbNotification);
  }

  // Personalized energy saving suggestions
  Future<void> sendEnergySavingSuggestion(String userId) async {
    final settings = await _databaseService.getAppSettings(userId);
    if (settings == null || !settings.notificationEnabled) return;

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final readings = await _databaseService.getMeterReadingsByDateRange(userId, startOfMonth, now);

    if (readings.isEmpty) return;

    final totalConsumption = readings.fold<double>(0.0, (sum, reading) => sum + reading.consumption);
    final averageDailyUsage = totalConsumption / now.day;

    String suggestion = _generateSuggestion(averageDailyUsage, readings.length);

    final notificationId = 'suggestion_${userId}_${DateTime.now().millisecondsSinceEpoch}'.hashCode;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _suggestionChannelId,
      _suggestionChannelName,
      channelDescription: _suggestionChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      'Energy Saving Tip',
      suggestion,
      platformChannelSpecifics,
      payload: 'suggestion:$userId',
    );

    // Store notification in database
    final dbNotification = app_notification.Notification(
      id: 'suggestion_${notificationId}',
      userId: userId,
      type: 'system',
      message: suggestion,
      date: DateTime.now(),
    );
    await _databaseService.insertNotification(dbNotification);
  }

  String _generateSuggestion(double averageDailyUsage, int readingCount) {
    if (averageDailyUsage > 20) {
      return 'Your average daily usage is high (${averageDailyUsage.toStringAsFixed(1)} kWh). Try unplugging unused devices and using LED bulbs to save energy.';
    } else if (averageDailyUsage > 15) {
      return 'Consider running appliances during off-peak hours to reduce your electricity costs.';
    } else if (readingCount < 10) {
      return 'Track your usage more frequently to identify patterns and optimize your consumption.';
    } else {
      return 'Great job on your energy usage! Keep monitoring to maintain efficient consumption.';
    }
  }

  // Schedule periodic suggestions (e.g., weekly)
  Future<void> scheduleWeeklySuggestions(String userId) async {
    final settings = await _databaseService.getAppSettings(userId);
    if (settings == null || !settings.notificationEnabled) return;

    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    final notificationId = 'weekly_suggestion_${userId}'.hashCode;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _suggestionChannelId,
      _suggestionChannelName,
      channelDescription: _suggestionChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Weekly Energy Tip',
      'Check out this week\'s personalized energy saving suggestion!',
      tz.TZDateTime.from(nextWeek, tz.local),
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'weekly_suggestion:$userId',
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  // Utility methods
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }

  void dispose() {
    _usageCheckTimer?.cancel();
  }
}