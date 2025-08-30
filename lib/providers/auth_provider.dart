import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/user.dart' as models;

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  models.User? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;

  models.User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      _isAuthenticated = await _authService.isAuthenticated();
      if (_isAuthenticated) {
        _currentUser = await _authService.getCachedUser();
      }
    } catch (e) {
      _isAuthenticated = false;
      _currentUser = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.loginWithEmailPassword(email, password);
      await checkAuthStatus();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register(String email, String password, String name) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.registerWithEmailPassword(email, password, name);
      await checkAuthStatus();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    await _authService.resetPassword(email);
  }
}