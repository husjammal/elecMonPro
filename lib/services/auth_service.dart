import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import 'platform_storage_service.dart';
import '../models/user.dart' as models;

class AuthService {
  final firebase_auth.FirebaseAuth _firebaseAuth = firebase_auth.FirebaseAuth.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final DatabaseService _databaseService = DatabaseService();

  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _cachedUserKey = 'cached_user';
  static const String _sessionTokenKey = 'session_token';

  // Registration with email and password
  Future<firebase_auth.UserCredential> registerWithEmailPassword(String email, String password, String name) async {
    try {
      firebase_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user in local database
      models.User newUser = models.User(
        id: userCredential.user!.uid,
        email: email,
        name: name,
        passwordHash: '', // Not storing password locally for Firebase Auth
        createdAt: DateTime.now(),
        settings: {},
      );

      await _databaseService.insertUser(newUser);

      // Cache user data for offline
      await _cacheUserData(newUser);

      return userCredential;
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  // Login with email and password
  Future<firebase_auth.UserCredential> loginWithEmailPassword(String email, String password) async {
    try {
      firebase_auth.UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Get user from local database or create if not exists
      models.User? localUser = await _databaseService.getUser(userCredential.user!.uid);
      if (localUser == null) {
        localUser = models.User(
          id: userCredential.user!.uid,
          email: email,
          name: userCredential.user!.displayName ?? 'User',
          passwordHash: '',
          createdAt: DateTime.now(),
          settings: {},
        );
        await _databaseService.insertUser(localUser);
      }

      // Cache user data for offline
      await _cacheUserData(localUser);

      return userCredential;
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
      await _clearCachedData();
    } catch (e) {
      throw Exception('Logout failed: $e');
    }
  }

  // Password reset
  Future<void> resetPassword(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Password reset failed: $e');
    }
  }

  // Biometric authentication
  Future<bool> authenticateWithBiometrics() async {
    try {
      bool canAuthenticate = await _localAuth.canCheckBiometrics;
      if (!canAuthenticate) {
        throw Exception('Biometric authentication not available');
      }

      return await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access the app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      throw Exception('Biometric authentication failed: $e');
    }
  }

  // Setup biometric authentication
  Future<void> setupBiometricAuth() async {
    try {
      bool authenticated = await authenticateWithBiometrics();
      if (authenticated) {
        await PlatformStorageService.write(_biometricEnabledKey, 'true');
      }
    } catch (e) {
      throw Exception('Biometric setup failed: $e');
    }
  }

  // Check if biometric is enabled
  Future<bool> isBiometricEnabled() async {
    String? enabled = await PlatformStorageService.read(_biometricEnabledKey);
    return enabled == 'true';
  }

  // Get current user
  firebase_auth.User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }

  // Get cached user for offline mode
  Future<models.User?> getCachedUser() async {
    try {
      String? userJson = await PlatformStorageService.read(_cachedUserKey);
      if (userJson != null) {
        Map<String, dynamic> userMap = Map<String, dynamic>.from(json.decode(userJson));
        return models.User.fromJson(userMap);
      }
    } catch (e) {
      // Handle parsing error
    }
    return null;
  }

  // Check if user is authenticated (online or offline)
  Future<bool> isAuthenticated() async {
    // Check online authentication first
    if (_firebaseAuth.currentUser != null) {
      return true;
    }

    // Check offline cached session
    models.User? cachedUser = await getCachedUser();
    String? sessionToken = await PlatformStorageService.read(_sessionTokenKey);

    if (cachedUser != null && sessionToken != null) {
      // Verify session token (simple check, can be enhanced)
      return true;
    }

    return false;
  }

  // Session management
  Future<void> createSession() async {
    String sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    await PlatformStorageService.write(_sessionTokenKey, sessionToken);
  }

  Future<void> clearSession() async {
    await PlatformStorageService.delete(_sessionTokenKey);
  }

  // Check network connectivity
  Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Sync user data when online
  Future<void> syncUserData() async {
    if (!await isOnline()) return;

    firebase_auth.User? currentUser = getCurrentUser();
    if (currentUser != null) {
      models.User? localUser = await _databaseService.getUser(currentUser.uid);
      if (localUser != null) {
        // Update local user data if needed
        await _databaseService.updateUser(localUser);
      }
    }
  }

  // Private helper methods
  Future<void> _cacheUserData(models.User user) async {
    await PlatformStorageService.write(_cachedUserKey, json.encode(user.toJson()));
    await createSession();
  }

  Future<void> _clearCachedData() async {
    await PlatformStorageService.delete(_cachedUserKey);
    await clearSession();
  }
}