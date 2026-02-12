import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../multiplayer/socket_connection_handler.dart';

class UserInfo {
  final int id;
  final String username;
  final String displayName;

  const UserInfo(
      {required this.id, required this.username, required this.displayName});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as int,
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
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  String? _cachedToken;
  UserInfo? _cachedUser;

  Future<String?> getStoredToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  Future<UserInfo?> getStoredUser() async {
    if (_cachedUser != null) return _cachedUser;
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _cachedUser = UserInfo.fromJson(jsonDecode(userJson));
      } catch (_) {}
    }
    return _cachedUser;
  }

  Future<void> _storeAuth(String token, UserInfo user) async {
    _cachedToken = token;
    _cachedUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> clearAuth() async {
    _cachedToken = null;
    _cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getStoredToken();
    return token != null;
  }

  Future<AuthResult> register(String username, String displayName, String email,
      String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'displayName': displayName,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        final user = UserInfo.fromJson(data['user']);
        final token = data['token'] as String;
        await _storeAuth(token, user);
        return AuthResult(success: true, token: token, user: user);
      }

      return AuthResult(
          success: false, error: data['error'] ?? 'Erreur d\'inscription');
    } catch (e) {
      if (kDebugMode) debugPrint('Register error: $e');
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
    }
  }

  Future<AuthResult> forgotPassword(String email) async {
    if (email.trim().isEmpty) {
      return const AuthResult(success: false, error: 'Email requis');
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/forgot-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return const AuthResult(success: true);
      }

      return AuthResult(
        success: false,
        error: data['error']?.toString() ?? 'Erreur de reinitialisation',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Forgot password error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible de contacter le serveur',
      );
    }
  }

  Future<AuthResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    if (token.trim().isEmpty) {
      return const AuthResult(success: false, error: 'Token requis');
    }
    if (newPassword.trim().isEmpty) {
      return const AuthResult(
        success: false,
        error: 'Nouveau mot de passe requis',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token.trim(),
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return const AuthResult(success: true);
      }

      return AuthResult(
        success: false,
        error: data['error']?.toString() ?? 'Lien invalide ou expire',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Reset password error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible de contacter le serveur',
      );
    }
  }

  Future<AuthResult> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserInfo.fromJson(data['user']);
        final token = data['token'] as String;
        await _storeAuth(token, user);
        return AuthResult(success: true, token: token, user: user);
      }

      return AuthResult(
          success: false, error: data['error'] ?? 'Identifiants incorrects');
    } catch (e) {
      if (kDebugMode) debugPrint('Login error: $e');
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
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
      return const AuthResult(success: false, error: 'Non connecte');
    }

    try {
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
        await _storeAuth(token, user);
        return AuthResult(success: true, user: user);
      }

      return AuthResult(
          success: false, error: data['error'] ?? 'Erreur de mise a jour');
    } catch (e) {
      return AuthResult(
          success: false, error: 'Impossible de contacter le serveur');
    }
  }

  Future<AuthResult> deleteAccount(String password) async {
    final token = await getStoredToken();
    if (token == null) {
      return const AuthResult(success: false, error: 'Non connecte');
    }

    if (password.trim().isEmpty) {
      return const AuthResult(success: false, error: 'Mot de passe requis');
    }

    try {
      final request = http.Request(
        'DELETE',
        Uri.parse('$_baseUrl/api/auth/account'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      request.body = jsonEncode({'password': password});

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      final Map<String, dynamic> data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200 && data['success'] == true) {
        await clearAuth();
        return const AuthResult(success: true);
      }

      return AuthResult(
        success: false,
        error: data['error']?.toString() ?? 'Erreur de suppression du compte',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Delete account error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible de contacter le serveur',
      );
    }
  }

  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await getStoredToken();
    if (token == null) {
      return const AuthResult(success: false, error: 'Non connecte');
    }

    if (currentPassword.trim().isEmpty) {
      return const AuthResult(
        success: false,
        error: 'Mot de passe actuel requis',
      );
    }
    if (newPassword.trim().isEmpty) {
      return const AuthResult(
        success: false,
        error: 'Nouveau mot de passe requis',
      );
    }

    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/api/auth/password'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return const AuthResult(success: true);
      }

      return AuthResult(
        success: false,
        error:
            data['error']?.toString() ?? 'Erreur de changement de mot de passe',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Change password error: $e');
      return const AuthResult(
        success: false,
        error: 'Impossible de contacter le serveur',
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
}
