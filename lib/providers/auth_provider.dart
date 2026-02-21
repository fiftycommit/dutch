import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/auth/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  UserInfo? _user;
  String? _token;
  bool _isLoading = false;
  bool _isInitialized = false;
  StreamSubscription<fb.User?>? _authSub;

  UserInfo? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  AuthService get authService => _authService;

  /// Initialise l'auth en écoutant Firebase authStateChanges
  Future<void> init() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();

    try {
      // Charger l'utilisateur courant (session persistée par Firebase)
      final fbUser = fb.FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        _token = await fbUser.getIdToken();
        // Récupérer le vrai profil (username) depuis Firestore
        _user = await _authService.fetchProfile();
      }

      // Écouter les changements d'état auth
      _authSub = fb.FirebaseAuth.instance.authStateChanges().listen(
        (fbUser) async {
          if (fbUser != null) {
            _token = await fbUser.getIdToken();
            // Récupérer le vrai profil depuis Firestore
            _user = await _authService.fetchProfile();
          } else {
            _token = null;
            _user = null;
          }
          notifyListeners();
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Auth init error: $e');
    }

    _isLoading = false;
    _isInitialized = true;
    notifyListeners();
  }

  /// Rafraîchit le token Firebase (auto-refresh)
  Future<String?> getFreshToken() async {
    final fbUser = fb.FirebaseAuth.instance.currentUser;
    if (fbUser == null) return null;
    _token = await fbUser.getIdToken();
    return _token;
  }

  Future<AuthResult> login(String identifier, String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.login(identifier, password);

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

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
