import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../multiplayer/socket_connection_handler.dart';
import '../network/secure_api_headers.dart';

/// Chiffrement AES-256-GCM des messages avant stockage Firestore.
/// La clé est dérivée côté dutch-server (jamais stockée dans Firebase).
class ChatCryptoService {
  static const _baseUrl = SocketConnectionHandler.serverUrl;
  static const _storage = FlutterSecureStorage();

  final _algorithm = AesGcm.with256bits();

  // ── Clé de chat ──────────────────────────────────────────────────────────

  /// Récupère la clé AES-256 pour un chat donné.
  /// Cherche d'abord dans le secure storage local, sinon appelle le serveur.
  Future<SecretKey> getChatKey(String chatId, String friendId) async {
    final storageKey = 'chat_key_$chatId';
    final cached = await _storage.read(key: storageKey);
    if (cached != null) {
      final bytes = base64Decode(cached);
      return SecretKey(bytes);
    }

    final keyBase64 = await _fetchKeyFromServer(friendId);
    await _storage.write(key: storageKey, value: keyBase64);
    return SecretKey(base64Decode(keyBase64));
  }

  Future<String> _fetchKeyFromServer(String friendId) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw Exception('Non authentifié');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/chats/$friendId/key'),
      headers: await SecureApiHeaders.json(bearerToken: token),
    );

    if (response.statusCode != 200) {
      throw Exception('Erreur récupération clé: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['key'] as String;
  }

  // ── Chiffrement / Déchiffrement ───────────────────────────────────────────

  /// Chiffre un texte → base64(iv[12] + ciphertext + mac[16])
  Future<String> encrypt(SecretKey key, String plaintext) async {
    final iv = _randomIv();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: iv,
    );
    // Format : iv (12 bytes) || ciphertext || mac (16 bytes)
    final combined = Uint8List(
        12 + secretBox.cipherText.length + secretBox.mac.bytes.length);
    combined.setRange(0, 12, iv);
    combined.setRange(12, 12 + secretBox.cipherText.length, secretBox.cipherText);
    combined.setRange(
        12 + secretBox.cipherText.length, combined.length, secretBox.mac.bytes);
    return base64Encode(combined);
  }

  /// Déchiffre un base64 chiffré → texte clair.
  /// Retourne null si la donnée n'est pas chiffrée (anciens messages en clair).
  Future<String?> decrypt(SecretKey key, String cipherBase64) async {
    Uint8List combined;
    try {
      combined = base64Decode(cipherBase64);
    } catch (_) {
      return null; // pas du base64 → message en clair (legacy)
    }
    if (combined.length < 28) return null; // trop court pour être valide

    final iv = combined.sublist(0, 12);
    final mac = Mac(combined.sublist(combined.length - 16));
    final cipherText = combined.sublist(12, combined.length - 16);

    try {
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      final plainBytes = await _algorithm.decrypt(secretBox, secretKey: key);
      return utf8.decode(plainBytes);
    } catch (_) {
      return null; // déchiffrement échoué → message en clair (legacy)
    }
  }

  Uint8List _randomIv() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
  }

  /// Vide le cache des clés (utile à la déconnexion)
  Future<void> clearKeyCache() async {
    final all = await _storage.readAll();
    for (final k in all.keys) {
      if (k.startsWith('chat_key_')) {
        await _storage.delete(key: k);
      }
    }
  }
}
