import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../multiplayer/socket_connection_handler.dart';
import '../network/network_probe_service.dart';

class UserInfo {
  final String id;
  final String username;
  final String displayName;

  const UserInfo(
      {required this.id, required this.username, required this.displayName});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id']?.toString() ?? '',
      username: json['username'] as String,
      displayName: json['displayName'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
      };
}

class AuthResult {
  final bool success;
  final String? token;
  final UserInfo? user;
  final String? error;

  const AuthResult({required this.success, this.token, this.user, this.error});
}

class AuthService {
  static const String _baseUrl = SocketConnectionHandler.serverUrl;
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Retourne le Firebase ID token (se rafraîchit automatiquement)
  Future<String?> getStoredToken() async {
    return _firebaseAuth.currentUser?.getIdToken();
  }

  /// Récupère le profil complet depuis le serveur (username + displayName)
  Future<UserInfo?> fetchProfile() async {
    final token = await getStoredToken();
    final fbUser = _firebaseAuth.currentUser;
    if (token == null || fbUser == null) return null;

    final canReachBackend = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 900),
    );
    if (!canReachBackend) {
      return UserInfo(
        id: fbUser.uid,
        username: fbUser.displayName ?? fbUser.email?.split('@').first ?? '',
        displayName: fbUser.displayName ?? fbUser.email?.split('@').first ?? '',
      );
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['user'] != null) {
          return UserInfo(
            id: fbUser.uid,
            username: data['user']['username'] ?? '',
            displayName:
                data['user']['displayName'] ?? fbUser.displayName ?? '',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchProfile error: $e');
    }

    // Fallback sur Firebase Auth (mieux que rien)
    return UserInfo(
      id: fbUser.uid,
      username: fbUser.displayName ?? fbUser.email?.split('@').first ?? '',
      displayName: fbUser.displayName ?? fbUser.email?.split('@').first ?? '',
    );
  }

  Future<void> clearAuth() async {
    await _firebaseAuth.signOut();
  }

  Future<bool> isLoggedIn() async {
    return _firebaseAuth.currentUser != null;
  }

  Future<AuthResult> register(String username, String displayName, String email,
      String password) async {
    try {
      // 1. Créer le compte Firebase
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Mettre le displayName dans Firebase Auth
      await credential.user?.updateDisplayName(displayName);

      // 3. Récupérer le token
      final token = await credential.user?.getIdToken();

      if (token == null || credential.user == null) {
        return const AuthResult(
            success: false, error: 'Erreur de création de compte');
      }

      // 4. Enregistrer username + displayName sur le serveur (Firestore)
      try {
        await http
            .put(
              Uri.parse('$_baseUrl/api/auth/profile'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'displayName': displayName,
                'username': username,
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        if (kDebugMode) debugPrint('Profile update after register: $e');
      }

      final user = UserInfo(
        id: credential.user!.uid,
        username: username,
        displayName: displayName,
      );

      return AuthResult(success: true, token: token, user: user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Register error: $e');
      return AuthResult(success: false, error: 'Impossible de créer le compte');
    }
  }

  Future<AuthResult> login(String identifier, String password) async {
    try {
      final rawIdentifier = identifier.trim();
      if (rawIdentifier.isEmpty) {
        return const AuthResult(
            success: false, error: 'Email ou pseudo requis');
      }
      if (password.isEmpty) {
        return const AuthResult(success: false, error: 'Mot de passe requis');
      }

      final resolvedEmail = await _resolveEmailForLogin(rawIdentifier);
      if (resolvedEmail == null) {
        return const AuthResult(
          success: false,
          error: 'Email ou pseudo introuvable',
        );
      }

      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: resolvedEmail,
        password: password,
      );

      final token = await credential.user?.getIdToken();

      if (token == null || credential.user == null) {
        return const AuthResult(success: false, error: 'Erreur de connexion');
      }

      // Récupérer le vrai profil (username) depuis Firestore
      final user = await fetchProfile() ??
          UserInfo(
            id: credential.user!.uid,
            username: credential.user!.displayName ??
                credential.user!.email?.split('@').first ??
                '',
            displayName: credential.user!.displayName ??
                credential.user!.email?.split('@').first ??
                '',
          );

      return AuthResult(success: true, token: token, user: user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Login error: $e');
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
    }
  }

  Future<String?> _resolveEmailForLogin(String identifier) async {
    final normalized = identifier.trim();
    if (_emailRegex.hasMatch(normalized)) {
      return normalized.toLowerCase();
    }

    final resolvedFromIdentifier =
        await _resolveEmailFromIdentifier(normalized);
    if (resolvedFromIdentifier != null) {
      return resolvedFromIdentifier;
    }

    final resolvedFromServer = await _resolveEmailFromUsername(normalized);
    if (resolvedFromServer != null) {
      return resolvedFromServer;
    }

    return null;
  }

  Future<String?> _resolveEmailFromIdentifier(String identifier) async {
    final canReachBackend = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 900),
    );
    if (!canReachBackend) return null;

    try {
      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/api/auth/resolve-login?identifier=${Uri.encodeComponent(identifier)}',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      return _extractEmailFromLookupPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveEmailFromUsername(String username) async {
    final canReachBackend = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 900),
    );
    if (!canReachBackend) return null;

    try {
      final normalizedUsername = username.trim().toLowerCase();
      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/api/auth/check-username?username=${Uri.encodeComponent(normalizedUsername)}',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      return _extractEmailFromLookupPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  String? _extractEmailFromLookupPayload(dynamic payload) {
    if (payload is! Map) return null;

    final userMap = payload['user'];
    final dataMap = payload['data'];

    final candidates = <dynamic>[
      payload['email'],
      payload['resolvedEmail'],
      payload['loginEmail'],
      payload['identifierEmail'],
      if (userMap is Map) userMap['email'],
      if (dataMap is Map) dataMap['email'],
    ];

    for (final candidate in candidates) {
      if (candidate is! String) continue;
      final normalized = candidate.trim().toLowerCase();
      if (_emailRegex.hasMatch(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  Future<AuthResult> forgotPassword(String email) async {
    if (email.trim().isEmpty) {
      return const AuthResult(success: false, error: 'Email requis');
    }

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Forgot password error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible d\'envoyer l\'email',
      );
    }
  }

  Future<bool> checkUsernameAvailable(String username) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$_baseUrl/api/auth/check-username?username=${Uri.encodeComponent(username)}'),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      return data['available'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<AuthResult> updateProfile(String displayName) async {
    final token = await getStoredToken();
    if (token == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      // Mettre à jour dans Firebase Auth
      await _firebaseAuth.currentUser?.updateDisplayName(displayName);

      // Mettre à jour dans Firestore via le serveur
      final response = await http
          .put(
            Uri.parse('$_baseUrl/api/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'displayName': displayName}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserInfo.fromJson(data['user']);
        return AuthResult(success: true, user: user);
      }

      return AuthResult(
          success: false, error: data['error'] ?? 'Erreur de mise à jour');
    } catch (e) {
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
    }
  }

  Future<AuthResult> deleteAccount(String password) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      // Ré-authentifier avant suppression (requis par Firebase)
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Supprimer côté serveur (Firestore)
      final token = await user.getIdToken();
      if (token != null) {
        try {
          final request = http.Request(
            'DELETE',
            Uri.parse('$_baseUrl/api/auth/account'),
          );
          request.headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          });
          await request.send().timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      // Supprimer le compte Firebase
      await user.delete();

      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Delete account error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible de supprimer le compte',
      );
    }
  }

  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      // Ré-authentifier
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Changer le mot de passe
      await user.updatePassword(newPassword);

      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Change password error: $e');
      return const AuthResult(
        success: false,
        error: 'Erreur de changement de mot de passe',
      );
    }
  }

  Future<void> registerDeviceToken(String fcmToken, String platform) async {
    final token = await getStoredToken();
    if (token == null) return;

    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/auth/device-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'token': fcmToken, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('Register device token error: $e');
    }
  }

  /// Traduit les codes d'erreur Firebase en messages français
  String _mapFirebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé';
      case 'invalid-email':
        return 'Email invalide';
      case 'weak-password':
        return 'Mot de passe trop faible (min 6 caractères)';
      case 'user-not-found':
        return 'Aucun compte trouvé avec cet email ou pseudo';
      case 'wrong-password':
        return 'Mot de passe incorrect';
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect';
      case 'user-disabled':
        return 'Ce compte a été désactivé';
      case 'too-many-requests':
        return 'Trop de tentatives, réessaie plus tard';
      case 'requires-recent-login':
        return 'Reconnecte-toi pour effectuer cette action';
      default:
        return 'Erreur d\'authentification ($code)';
    }
  }
}
