import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/sync_service.dart';

class SyncProvider with ChangeNotifier {
  final SyncService _syncService = SyncService();

  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _syncError;

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get syncError => _syncError;
  bool get hasError => _syncError != null;

  // Sync status stream subscription
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  SyncProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    // Listen to sync status changes
    _syncStatusSubscription = _syncService.syncStatus.listen(_onSyncStatusChanged);

    // Initialize sync service
    await _syncService.initialize();
  }

  void _onSyncStatusChanged(SyncStatus status) {
    _isOnline = status.isOnline;
    _isSyncing = status.isSyncing;
    _lastSyncTime = status.lastSyncTime;
    _syncError = null; // Clear any previous errors on status change
    notifyListeners();
  }

  // Public methods
  Future<void> performFullSync() async {
    try {
      _syncError = null;
      notifyListeners();
      await _syncService.performFullSync();
    } catch (e) {
      _syncError = e.toString();
      notifyListeners();
      debugPrint('Sync error: $e');
    }
  }

  Future<void> performIncrementalSync() async {
    try {
      _syncError = null;
      notifyListeners();
      await _syncService.performIncrementalSync();
    } catch (e) {
      _syncError = e.toString();
      notifyListeners();
      debugPrint('Incremental sync error: $e');
    }
  }

  void clearError() {
    _syncError = null;
    notifyListeners();
  }

  // Get sync status description
  String getSyncStatusDescription() {
    if (!_isOnline) {
      return 'Offline - Changes will sync when online';
    }

    if (_isSyncing) {
      return 'Syncing...';
    }

    if (_lastSyncTime != null) {
      final timeAgo = DateTime.now().difference(_lastSyncTime!);
      if (timeAgo.inMinutes < 1) {
        return 'Synced just now';
      } else if (timeAgo.inMinutes < 60) {
        return 'Synced ${timeAgo.inMinutes} minutes ago';
      } else if (timeAgo.inHours < 24) {
        return 'Synced ${timeAgo.inHours} hours ago';
      } else {
        return 'Synced ${timeAgo.inDays} days ago';
      }
    }

    return 'Ready to sync';
  }

  // Get sync status color
  Color getSyncStatusColor() {
    if (!_isOnline) {
      return Colors.orange;
    }

    if (_isSyncing) {
      return Colors.blue;
    }

    if (hasError) {
      return Colors.red;
    }

    return Colors.green;
  }

  // Get sync status icon
  IconData getSyncStatusIcon() {
    if (!_isOnline) {
      return Icons.wifi_off;
    }

    if (_isSyncing) {
      return Icons.sync;
    }

    if (hasError) {
      return Icons.error;
    }

    return Icons.check_circle;
  }

  @override
  void dispose() {
    _syncStatusSubscription?.cancel();
    _syncService.dispose();
    super.dispose();
  }
}