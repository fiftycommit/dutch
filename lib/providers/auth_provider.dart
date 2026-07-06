import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/auth/auth_service.dart';

class AuthProvider with ChangeNotifier {
  static const Duration _startupAuthTimeout = Duration(seconds: 2);

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
      if (fb_core.Firebase.apps.isEmpty) {
        if (kDebugMode) {
          debugPrint('Auth init skipped: Firebase non initialisé');
        }
        return;
      }

      // Charger l'utilisateur courant (session persistée par Firebase)
      final fbUser = fb.FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        try {
          _token = await fbUser.getIdToken().timeout(_startupAuthTimeout);
          _user =
              await _authService.fetchProfile().timeout(_startupAuthTimeout);
        } catch (e) {
          // Sur macOS, keychain peut échouer - ignorer silencieusement
          if (kDebugMode) debugPrint('Auth init token/profile error: $e');
        }
      }

      // Écouter les changements d'état auth
      _authSub = fb.FirebaseAuth.instance.authStateChanges().listen(
        (fbUser) async {
          try {
            if (fbUser != null) {
              _token = await fbUser.getIdToken().timeout(_startupAuthTimeout);
              // Récupérer le vrai profil depuis Firestore
              _user = await _authService
                  .fetchProfile()
                  .timeout(_startupAuthTimeout);
            } else {
              _token = null;
              _user = null;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Auth state refresh error: $e');
          }
          notifyListeners();
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Auth init error: $e');
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Rafraîchit le token Firebase (auto-refresh)
  Future<String?> getFreshToken() async {
    if (fb_core.Firebase.apps.isEmpty) return null;
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

  Future<AuthResult> loginWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.signInWithGoogle();

    if (result.success) {
      _user = result.user;
      _token = result.token;
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  /// Déconnecte l'utilisateur (utilisé si l'onboarding Google est annulé)
  Future<void> signOut() async {
    await _authService.clearAuth();
    _user = null;
    _token = null;
    notifyListeners();
  }

  /// Crée le profil sur le serveur après inscription Google
  Future<void> saveGoogleProfile({
    required String username,
    required String displayName,
  }) async {
    await _authService.saveProfile(
      username: username,
      displayName: displayName,
    );
  }

  /// Met à jour le username local après le choix de l'utilisateur
  void setUsername(String username) {
    if (_user != null) {
      _user = UserInfo(
        id: _user!.id,
        username: username,
        displayName: _user!.displayName,
      );
      notifyListeners();
    }
  }

  /// Vérifie si un username est disponible sur le serveur
  Future<bool> checkUsernameAvailable(String username) =>
      _authService.checkUsernameAvailable(username);

  Future<AuthResult> register(String username, String displayName, String email,
      String password) async {
    _isLoading = true;
    notifyListeners();

    final result =
        await _authService.register(username, displayName, email, password);

    if (result.success) {
      _user = result.user;
      _token = result.token;
      _isInitialized = true;
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

  /// Retourne la liste des providers liés ('password', 'google.com', etc.)
  List<String> getLinkedProviders() => _authService.getLinkedProviders();

  /// Ré-authentifie selon le provider (Google popup ou mot de passe)
  Future<AuthResult> reauthenticate({String? password}) =>
      _authService.reauthenticate(password: password);

  /// Lie un compte Google au compte courant
  Future<AuthResult> linkGoogle() async {
    final result = await _authService.linkGoogleAccount();
    if (result.success) notifyListeners();
    return result;
  }

  /// Lie un email/mot de passe au compte courant
  Future<AuthResult> linkEmailPassword(String email, String password) async {
    final result = await _authService.linkEmailPassword(email, password);
    if (result.success) notifyListeners();
    return result;
  }

  /// Délie un provider (refuse si dernier)
  Future<AuthResult> unlinkProvider(String providerId) async {
    final result = await _authService.unlinkProvider(providerId);
    if (result.success) notifyListeners();
    return result;
  }

  Future<AuthResult> deleteAccount({String? password}) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.deleteAccount(password: password);

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
