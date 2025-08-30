import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

/// Platform-specific storage service that handles web and mobile differences
class PlatformStorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static SharedPreferences? _prefs;

  /// Initialize the storage service
  static Future<void> init() async {
    if (kIsWeb) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  /// Write data to storage
  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      if (_prefs == null) await init();
      await _prefs!.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  /// Read data from storage
  static Future<String?> read(String key) async {
    if (kIsWeb) {
      if (_prefs == null) await init();
      return _prefs!.getString(key);
    } else {
      return await _secureStorage.read(key: key);
    }
  }

  /// Delete data from storage
  static Future<void> delete(String key) async {
    if (kIsWeb) {
      if (_prefs == null) await init();
      await _prefs!.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  /// Check if key exists
  static Future<bool> containsKey(String key) async {
    if (kIsWeb) {
      if (_prefs == null) await init();
      return _prefs!.containsKey(key);
    } else {
      final value = await _secureStorage.read(key: key);
      return value != null;
    }
  }

  /// Clear all data
  static Future<void> clear() async {
    if (kIsWeb) {
      if (_prefs == null) await init();
      await _prefs!.clear();
    } else {
      // Note: FlutterSecureStorage doesn't have a clear method
      // We'll need to track keys and delete them individually
    }
  }
}

/// Platform-specific biometric authentication service
class PlatformBiometricService {
  /// Check if biometric authentication is available
  static Future<bool> isAvailable() async {
    if (kIsWeb) {
      // Web doesn't support biometric authentication
      return false;
    } else {
      try {
        // Import local_auth only for mobile platforms
        final localAuth = await _getLocalAuth();
        return await localAuth.canCheckBiometrics;
      } catch (e) {
        return false;
      }
    }
  }

  /// Authenticate with biometrics
  static Future<bool> authenticate(String reason) async {
    if (kIsWeb) {
      // Web doesn't support biometric authentication
      return false;
    } else {
      try {
        final localAuth = await _getLocalAuth();
        return await localAuth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            biometricOnly: true,
            useErrorDialogs: true,
            stickyAuth: true,
          ),
        );
      } catch (e) {
        return false;
      }
    }
  }

  /// Get local auth instance (only for mobile)
  static dynamic _getLocalAuth() {
    // This will only be called on mobile platforms
    // We use dynamic to avoid import issues on web
    throw UnsupportedError('Biometric authentication not available on this platform');
  }
}

/// Platform-specific work manager service
class PlatformWorkManagerService {
  /// Schedule background task
  static Future<void> scheduleTask(String taskName, Duration frequency) async {
    if (kIsWeb) {
      // Web doesn't support background tasks
      return;
    } else {
      // Use workmanager for mobile platforms
      // This would need to be implemented with the actual workmanager package
    }
  }

  /// Cancel background task
  static Future<void> cancelTask(String taskName) async {
    if (kIsWeb) {
      // Web doesn't support background tasks
      return;
    } else {
      // Cancel workmanager task for mobile platforms
    }
  }
}