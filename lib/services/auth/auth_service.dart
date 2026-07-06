import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  final bool needsUsernameSetup;
  final String? suggestedUsername;

  const AuthResult({
    required this.success,
    this.token,
    this.user,
    this.error,
    this.needsUsernameSetup = false,
    this.suggestedUsername,
  });
}

class AuthService {
  static const String _baseUrl = SocketConnectionHandler.serverUrl;

  /// Produit un username valide depuis n'importe quelle chaîne :
  /// lowercase, espaces remplacés par '_', caractères non autorisés supprimés, 20 car max.
  static String _normalizeUsername(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
  }

  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  /// Flag pour n'initialiser GoogleSignIn qu'une seule fois (requis par v7)
  bool _googleSignInInitialized = false;

  /// Initialise GoogleSignIn.instance (idempotent).
  /// Doit être appelé avant tout appel à authenticate().
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  /// Retourne le Firebase ID token (se rafraîchit automatiquement)
  Future<String?> getStoredToken() async {
    return _firebaseAuth.currentUser?.getIdToken();
  }

  /// Récupère le profil complet depuis le serveur (username + displayName)
  /// Vérifie si le profil existe côté serveur (sans fallback)
  Future<UserInfo?> fetchServerProfile() async {
    final token = await getStoredToken();
    final fbUser = _firebaseAuth.currentUser;
    if (token == null || fbUser == null) return null;

    final canReachBackend = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 900),
    );
    if (!canReachBackend) return null;

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
      if (kDebugMode) debugPrint('fetchServerProfile error: $e');
    }

    return null;
  }

  Future<UserInfo?> fetchProfile() async {
    final serverProfile = await fetchServerProfile();
    if (serverProfile != null) return serverProfile;

    // Fallback sur Firebase Auth (mieux que rien)
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser == null) return null;

    return UserInfo(
      id: fbUser.uid,
      username: _normalizeUsername(
          fbUser.email?.split('@').first ?? fbUser.displayName ?? ''),
      displayName: fbUser.displayName ?? fbUser.email?.split('@').first ?? '',
    );
  }

  Future<void> clearAuth() async {
    await _firebaseAuth.signOut();
  }

  Future<bool> isLoggedIn() async {
    return _firebaseAuth.currentUser != null;
  }

  Future<AuthResult> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Sur web : Firebase signInWithPopup (pas de People API requise)
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final userCredential = await _firebaseAuth.signInWithPopup(provider);
        final token = await userCredential.user?.getIdToken();

        if (token == null || userCredential.user == null) {
          return const AuthResult(
              success: false, error: 'Erreur de connexion Google');
        }

        final fbUser = userCredential.user!;
        // Vérifier si le profil existe dans Firestore (pas de fallback)
        final existingProfile = await fetchServerProfile();
        if (existingProfile != null) {
          return AuthResult(success: true, token: token, user: existingProfile);
        }

        // Nouveau compte : proposer le choix du username
        final suggested = _normalizeUsername(
            fbUser.email?.split('@').first ?? fbUser.displayName ?? '');
        return AuthResult(
          success: true,
          token: token,
          user: UserInfo(
            id: fbUser.uid,
            username: suggested,
            displayName: fbUser.displayName ?? fbUser.email ?? '',
          ),
          needsUsernameSetup: true,
          suggestedUsername: suggested,
        );
      } else {
        // Sur iOS / Android : google_sign_in v7 (singleton + authenticate)
        await _ensureGoogleSignInInitialized();
        final GoogleSignInAccount googleUser;
        try {
          googleUser = await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) {
            return const AuthResult(success: false, error: 'Connexion annulée');
          }
          rethrow;
        }

        final idToken = googleUser.authentication.idToken;
        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        final userCredential =
            await _firebaseAuth.signInWithCredential(credential);
        final token = await userCredential.user?.getIdToken();

        if (token == null || userCredential.user == null) {
          return const AuthResult(
              success: false, error: 'Erreur de connexion Google');
        }

        // Vérifier si le profil existe dans Firestore (pas de fallback)
        final existingProfile = await fetchServerProfile();
        if (existingProfile != null) {
          return AuthResult(success: true, token: token, user: existingProfile);
        }

        // Nouveau compte : proposer le choix du username
        final suggested = _normalizeUsername(googleUser.email.split('@').first);
        return AuthResult(
          success: true,
          token: token,
          user: UserInfo(
            id: userCredential.user!.uid,
            username: suggested,
            displayName: googleUser.displayName ?? googleUser.email,
          ),
          needsUsernameSetup: true,
          suggestedUsername: suggested,
        );
      }
    } on FirebaseAuthException catch (e) {
      // Keychain fallback : l'auth Google a pu réussir malgré l'erreur
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) {
        final token = await fbUser.getIdToken();
        final profile = await fetchProfile();
        if (profile != null) {
          return AuthResult(success: true, token: token, user: profile);
        }
        final suggested = _normalizeUsername(
            fbUser.email?.split('@').first ?? fbUser.displayName ?? '');
        return AuthResult(
          success: true,
          token: token,
          user: UserInfo(
              id: fbUser.uid,
              username: suggested,
              displayName: fbUser.displayName ?? ''),
          needsUsernameSetup: true,
          suggestedUsername: suggested,
        );
      }
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      // Keychain fallback
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser != null) {
        final token = await fbUser.getIdToken();
        final profile = await fetchProfile();
        if (profile != null) {
          return AuthResult(success: true, token: token, user: profile);
        }
        final suggested = _normalizeUsername(
            fbUser.email?.split('@').first ?? fbUser.displayName ?? '');
        return AuthResult(
          success: true,
          token: token,
          user: UserInfo(
              id: fbUser.uid,
              username: suggested,
              displayName: fbUser.displayName ?? ''),
          needsUsernameSetup: true,
          suggestedUsername: suggested,
        );
      }
      if (kDebugMode) debugPrint('Google Sign-In error: $e');
      return const AuthResult(
          success: false, error: 'Impossible de se connecter avec Google');
    }
  }

  Future<AuthResult> register(String username, String displayName, String email,
      String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/register-password'),
            headers: await _buildJsonHeaders(includeAppCheck: true),
            body: jsonEncode({
              'username': username,
              'displayName': displayName,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _decodeJsonMap(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        return AuthResult(
          success: false,
          error: _extractServerError(
            data,
            fallback: 'Impossible de créer le compte',
          ),
        );
      }

      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        return const AuthResult(
          success: false,
          error: 'Réponse serveur invalide',
        );
      }

      final firebaseResult = await _signInWithCustomToken(customToken);
      if (!firebaseResult.success || firebaseResult.user == null) {
        return firebaseResult;
      }

      final userMap = data['user'];
      if (userMap is Map<String, dynamic>) {
        return AuthResult(
          success: true,
          token: firebaseResult.token,
          user: UserInfo.fromJson(userMap),
        );
      }

      return firebaseResult;
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

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login-password'),
            headers: await _buildJsonHeaders(includeAppCheck: true),
            body: jsonEncode({
              'identifier': rawIdentifier,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonMap(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        return AuthResult(
          success: false,
          error: _extractServerError(
            data,
            fallback: 'Email ou mot de passe incorrect',
          ),
        );
      }

      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        return const AuthResult(
          success: false,
          error: 'Réponse serveur invalide',
        );
      }

      return _signInWithCustomToken(customToken);
    } catch (e) {
      if (kDebugMode) debugPrint('Login error: $e');
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
    }
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
            headers: await _buildJsonHeaders(includeAppCheck: true),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      return data['available'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Crée le profil Firestore après inscription Google (username + displayName)
  Future<void> saveProfile({
    required String username,
    required String displayName,
  }) async {
    final token = await getStoredToken();
    if (token == null) return;

    try {
      await http
          .put(
            Uri.parse('$_baseUrl/api/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'username': username,
              'displayName': displayName,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('saveProfile error: $e');
    }
  }

  Future<Map<String, String>> _buildJsonHeaders({
    bool includeAppCheck = false,
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }

    if (includeAppCheck) {
      final appCheckToken = await _getAppCheckToken();
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    }

    return headers;
  }

  Future<String?> _getAppCheckToken() async {
    try {
      return await FirebaseAppCheck.instance.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('App Check token error: $e');
      return null;
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }

  String _extractServerError(
    Map<String, dynamic> payload, {
    required String fallback,
  }) {
    final error = payload['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    return fallback;
  }

  Future<AuthResult> _signInWithCustomToken(String customToken) async {
    try {
      final credential = await _firebaseAuth.signInWithCustomToken(customToken);
      final token = await credential.user?.getIdToken();

      if (token == null || credential.user == null) {
        return const AuthResult(success: false, error: 'Erreur de connexion');
      }

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
      final fallbackUser = _firebaseAuth.currentUser;
      if (fallbackUser != null) {
        final token = await fallbackUser.getIdToken();
        final user = await fetchProfile();
        if (token != null && user != null) {
          return AuthResult(success: true, token: token, user: user);
        }
      }
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
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

  // ── Multi-provider helpers ──────────────────────────────────────────────────

  /// Retourne la liste des provider IDs liés au compte ('password', 'google.com', etc.)
  List<String> getLinkedProviders() {
    final user = _firebaseAuth.currentUser;
    if (user == null) return [];
    return user.providerData.map((p) => p.providerId).toList();
  }

  /// Ré-authentifie l'utilisateur selon son provider principal.
  /// - `password` si le provider est email/mdp
  /// - Google popup/signIn sinon
  Future<AuthResult> reauthenticate({String? password}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      final providers = getLinkedProviders();

      if (password != null && providers.contains('password')) {
        // Ré-auth par email/mdp
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
        return const AuthResult(success: true);
      }

      if (providers.contains('google.com')) {
        // Ré-auth par Google
        if (kIsWeb) {
          final provider = GoogleAuthProvider()
            ..addScope('email')
            ..addScope('profile');
          await user.reauthenticateWithPopup(provider);
        } else {
          await _ensureGoogleSignInInitialized();
          final GoogleSignInAccount googleUser;
          try {
            googleUser = await GoogleSignIn.instance.authenticate();
          } on GoogleSignInException catch (e) {
            if (e.code == GoogleSignInExceptionCode.canceled) {
              return const AuthResult(
                  success: false, error: 'Connexion annulée');
            }
            rethrow;
          }
          final idToken = googleUser.authentication.idToken;
          final credential = GoogleAuthProvider.credential(
            idToken: idToken,
          );
          await user.reauthenticateWithCredential(credential);
        }
        return const AuthResult(success: true);
      }

      return const AuthResult(
          success: false,
          error: 'Aucune méthode de ré-authentification disponible');
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Reauthenticate error: $e');
      return const AuthResult(
          success: false, error: 'Erreur de ré-authentification');
    }
  }

  /// Lie un compte Google à l'utilisateur courant
  Future<AuthResult> linkGoogleAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await user.linkWithPopup(provider);
      } else {
        await _ensureGoogleSignInInitialized();
        final GoogleSignInAccount googleUser;
        try {
          googleUser = await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) {
            return const AuthResult(success: false, error: 'Connexion annulée');
          }
          rethrow;
        }
        final idToken = googleUser.authentication.idToken;
        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );
        await user.linkWithCredential(credential);
      }
      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        return const AuthResult(
            success: false,
            error: 'Ce compte Google est déjà lié à un autre utilisateur');
      }
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Link Google error: $e');
      return const AuthResult(
          success: false, error: 'Impossible de lier le compte Google');
    }
  }

  /// Lie un email/mot de passe à l'utilisateur courant (compte Google-only)
  Future<AuthResult> linkEmailPassword(String email, String password) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await user.linkWithCredential(credential);
      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return const AuthResult(
            success: false,
            error: 'Cet email est déjà utilisé par un autre compte');
      }
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Link email error: $e');
      return const AuthResult(
          success: false, error: 'Impossible de lier l\'email');
    }
  }

  /// Délie un provider (refuse si c'est le dernier)
  Future<AuthResult> unlinkProvider(String providerId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    final providers = getLinkedProviders();
    if (providers.length <= 1) {
      return const AuthResult(
          success: false,
          error: 'Tu dois garder au moins une méthode de connexion');
    }

    try {
      await user.unlink(providerId);
      return const AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapFirebaseError(e.code));
    } catch (e) {
      if (kDebugMode) debugPrint('Unlink provider error: $e');
      return const AuthResult(
          success: false, error: 'Impossible de délier ce fournisseur');
    }
  }

  // ── Suppression de compte ──────────────────────────────────────────────────

  Future<AuthResult> deleteAccount({String? password}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const AuthResult(success: false, error: 'Non connecté');
    }

    try {
      // Ré-authentifier avant suppression (requis par Firebase)
      final reauth = await reauthenticate(password: password);
      if (!reauth.success) return reauth;

      // Supprimer côté serveur (Firestore)
      // On tente la suppression serveur mais on ne bloque pas la suppression
      // Firebase si elle échoue — l'erreur est loguée pour investigation.
      bool serverDeleteFailed = false;
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
          final response =
              await request.send().timeout(const Duration(seconds: 10));
          if (response.statusCode >= 400) {
            serverDeleteFailed = true;
            if (kDebugMode) {
              debugPrint(
                  'Suppression serveur échouée (HTTP ${response.statusCode})');
            }
          }
        } catch (e) {
          serverDeleteFailed = true;
          if (kDebugMode) {
            debugPrint('Suppression serveur échouée : $e');
          }
        }
      }

      // Supprimer le compte Firebase
      await user.delete();

      if (serverDeleteFailed) {
        return const AuthResult(
          success: true,
          error:
              'Compte supprimé, mais certaines données serveur n\'ont pas pu être nettoyées',
        );
      }
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
