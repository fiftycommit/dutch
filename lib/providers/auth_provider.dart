import 'package:flutter/foundation.dart';
import '../services/auth/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  UserInfo? _user;
  String? _token;
  bool _isLoading = false;
  bool _isInitialized = false;

  UserInfo? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _user != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  AuthService get authService => _authService;

  /// Initialise l'auth en restaurant le token stocké
  Future<void> init() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _authService.getStoredToken();
      _user = await _authService.getStoredUser();
    } catch (e) {
      if (kDebugMode) debugPrint('Auth init error: $e');
    }

    _isLoading = false;
    _isInitialized = true;
    notifyListeners();
  }

  Future<AuthResult> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.login(username, password);

    if (result.success) {
      _user = result.user;
      _token = result.token;
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> register(String username, String displayName, String email,
      String password) async {
    _isLoading = true;
    notifyListeners();

    final result =
        await _authService.register(username, displayName, email, password);

    if (result.success) {
      _user = result.user;
      _token = result.token;
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> forgotPassword(String email) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.forgotPassword(email);

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.resetPassword(
      token: token,
      newPassword: newPassword,
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> updateProfile(String displayName) async {
    final result = await _authService.updateProfile(displayName);

    if (result.success) {
      _user = result.user;
      notifyListeners();
    }

    return result;
  }

  Future<AuthResult> deleteAccount(String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.deleteAccount(password);

    if (result.success) {
      _user = null;
      _token = null;
      _isInitialized = true;
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<void> logout() async {
    await _authService.clearAuth();
    _user = null;
    _token = null;
    notifyListeners();
  }
}
