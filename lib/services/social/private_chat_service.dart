import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'chat_crypto_service.dart';

enum ChatMessageType { text, image, audio }

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final ChatMessageType type;
  final String? mediaUrl;
  final int? audioDurationMs;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.timestamp,
    this.mediaUrl,
    this.audioDurationMs,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot doc, {required String decryptedText}) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String? ?? 'text';
    final type = typeStr == 'image'
        ? ChatMessageType.image
        : typeStr == 'audio'
            ? ChatMessageType.audio
            : ChatMessageType.text;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: decryptedText,
      type: type,
      mediaUrl: data['mediaUrl'] as String?,
      audioDurationMs: data['audioDurationMs'] as int?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class PrivateChatService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final ChatCryptoService _crypto;

  PrivateChatService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    ChatCryptoService? crypto,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _crypto = crypto ?? ChatCryptoService();

  /// Identifiant déterministe : toujours le plus petit userId en premier.
  static String chatId(String myId, String friendId) {
    final sorted = [myId, friendId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  CollectionReference<Map<String, dynamic>> _messages(String cId) =>
      _db.collection('private_chats').doc(cId).collection('messages');

  /// Stream de messages déchiffrés à la volée.
  Stream<List<ChatMessage>> messagesStream(
      String cId, String friendId) {
    return _messages(cId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .asyncMap((snap) => _decryptSnapshot(snap, cId, friendId));
  }

  Future<List<ChatMessage>> _decryptSnapshot(
      QuerySnapshot snap, String cId, String friendId) async {
    SecretKey? key;
    try {
      key = await _crypto.getChatKey(cId, friendId);
    } catch (_) {
      key = null;
    }

    final results = <ChatMessage>[];
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final raw = data['text'] as String? ?? '';
      String decrypted = raw;
      if (key != null && raw.isNotEmpty) {
        decrypted = await _crypto.decrypt(key, raw) ?? raw;
      }
      results.add(ChatMessage.fromDoc(doc, decryptedText: decrypted));
    }
    return results;
  }

  Future<void> sendMessage(
      String cId, String senderId, String text, String friendId) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    String payload = trimmed;
    try {
      final key = await _crypto.getChatKey(cId, friendId);
      payload = await _crypto.encrypt(key, trimmed);
    } catch (_) {
      // En cas d'erreur crypto, on envoie en clair plutôt que de bloquer
    }

    await _messages(cId).add({
      'senderId': senderId,
      'type': 'text',
      'text': payload,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendImageBytes(
      String cId, String senderId, List<int> bytes) async {
    final ref = _storage
        .ref()
        .child('chat_media/$cId/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _messages(cId).add({
      'senderId': senderId,
      'type': 'image',
      'text': '',
      'mediaUrl': url,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendImage(String cId, String senderId, File imageFile) async {
    final ref = _storage
        .ref()
        .child('chat_media/$cId/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _messages(cId).add({
      'senderId': senderId,
      'type': 'image',
      'text': '',
      'mediaUrl': url,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendAudio(
      String cId, String senderId, File audioFile, int durationMs) async {
    final ref = _storage
        .ref()
        .child('chat_media/$cId/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await ref.putFile(audioFile, SettableMetadata(contentType: 'audio/m4a'));
    final url = await ref.getDownloadURL();
    await _messages(cId).add({
      'senderId': senderId,
      'type': 'audio',
      'text': '',
      'mediaUrl': url,
      'audioDurationMs': durationMs,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
