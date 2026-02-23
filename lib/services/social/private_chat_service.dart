import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../multiplayer/socket_connection_handler.dart';
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
  final DocumentSnapshot? snapshot; // pour la pagination

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.timestamp,
    this.mediaUrl,
    this.audioDurationMs,
    this.snapshot,
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
      snapshot: doc,
    );
  }
}

/// Données de présence du chat (wallpaper + read receipts + typing).
class ChatMeta {
  final String? wallpaperUrl;
  final DateTime? friendReadAt;
  final bool friendIsTyping;

  const ChatMeta({
    this.wallpaperUrl,
    this.friendReadAt,
    this.friendIsTyping = false,
  });
}

class PrivateChatService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final ChatCryptoService _crypto;
  final http.Client _httpClient;

  static const _baseUrl = SocketConnectionHandler.serverUrl;
  static const _pageSize = 15;

  PrivateChatService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    ChatCryptoService? crypto,
    http.Client? httpClient,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _crypto = crypto ?? ChatCryptoService(),
        _httpClient = httpClient ?? http.Client();

  /// Identifiant déterministe : toujours le plus petit userId en premier.
  static String chatId(String myId, String friendId) {
    final sorted = [myId, friendId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  CollectionReference<Map<String, dynamic>> _messages(String cId) =>
      _db.collection('private_chats').doc(cId).collection('messages');

  DocumentReference<Map<String, dynamic>> _chatDoc(String cId) =>
      _db.collection('private_chats').doc(cId);

  /// Stream combiné : wallpaperUrl + friendReadAt + typing
  Stream<ChatMeta> metaStream(String cId, String friendId) {
    return _chatDoc(cId).snapshots().map((doc) {
      final data = doc.data();
      final wallpaperUrl = data?['wallpaperUrl'] as String?;
      final receipts = data?['readReceipts'] as Map<String, dynamic>?;
      final friendTs = receipts?[friendId] as Timestamp?;
      // Typing : on considère actif si la valeur date de moins de 5s
      final typing = data?['typing'] as Map<String, dynamic>?;
      bool friendIsTyping = false;
      final friendTypingTs = typing?[friendId] as Timestamp?;
      if (friendTypingTs != null) {
        final diff = DateTime.now().difference(friendTypingTs.toDate());
        friendIsTyping = diff.inSeconds < 5;
      }
      return ChatMeta(
        wallpaperUrl: wallpaperUrl,
        friendReadAt: friendTs?.toDate(),
        friendIsTyping: friendIsTyping,
      );
    });
  }

  /// Marque le chat comme lu par myUserId (appelé à l'ouverture de la conv).
  Future<void> markAsRead(String cId, String myUserId) async {
    await _chatDoc(cId).set({
      'readReceipts': {myUserId: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  /// Met à jour l'indicateur de frappe.
  Future<void> updateTyping(String cId, String myUserId, bool isTyping) async {
    await _chatDoc(cId).set({
      'typing': {
        myUserId: isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
      },
    }, SetOptions(merge: true));
  }

  /// Stream de messages déchiffrés — limité aux 50 derniers.
  Stream<List<ChatMessage>> messagesStream(String cId, String friendId) {
    return _messages(cId)
        .orderBy('timestamp', descending: false)
        .limitToLast(_pageSize)
        .snapshots()
        .asyncMap((snap) => _decryptSnapshot(snap, cId, friendId));
  }

  /// Charge les [_pageSize] messages précédant [before].
  Future<List<ChatMessage>> loadMoreMessages(
      String cId, String friendId, DocumentSnapshot before) async {
    final snap = await _messages(cId)
        .orderBy('timestamp', descending: false)
        .endBeforeDocument(before)
        .limitToLast(_pageSize)
        .get();
    return _decryptSnapshotList(snap.docs, cId, friendId);
  }

  Future<List<ChatMessage>> _decryptSnapshot(
      QuerySnapshot snap, String cId, String friendId) async {
    return _decryptSnapshotList(snap.docs, cId, friendId);
  }

  Future<List<ChatMessage>> _decryptSnapshotList(
      List<QueryDocumentSnapshot> docs, String cId, String friendId) async {
    SecretKey? key;
    try {
      key = await _crypto.getChatKey(cId, friendId);
    } catch (_) {
      key = null;
    }

    final results = <ChatMessage>[];
    for (final doc in docs) {
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

    // Push notification
    _sendChatNotification(
      chatId: cId,
      recipientId: friendId,
      preview: trimmed.length > 100 ? '${trimmed.substring(0, 100)}…' : trimmed,
    );
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

  /// Web uniquement : fetch le blob URL et upload les bytes vers Firebase Storage.
  Future<void> sendAudioFromUrl(
      String cId, String senderId, String blobUrl, int durationMs) async {
    final bytes = await _fetchBytes(blobUrl);
    final ref = _storage
        .ref()
        .child('chat_media/$cId/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await ref.putData(bytes, SettableMetadata(contentType: 'audio/m4a'));
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

  Future<Uint8List> _fetchBytes(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    return response.bodyBytes;
  }

  /// Envoie une push notification au destinataire (best-effort, silencieux en cas d'erreur).
  Future<void> _sendChatNotification({
    required String chatId,
    required String recipientId,
    required String preview,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final senderName = user.displayName ?? 'Quelqu\'un';

      await _httpClient.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/notify'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"recipientId":"$recipientId","senderName":"$senderName","preview":"${preview.replaceAll('"', '\\"')}"}',
      );
    } catch (_) {
      // Silencieux — la notification n'est pas critique
    }
  }
}
