import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../multiplayer/socket_connection_handler.dart';
import 'chat_crypto_service.dart';
import '../network/secure_api_headers.dart';

enum ChatMessageType { text, image, audio }

/// Échec d'un envoi média (timeout, annulation, ou erreur Storage) — remonté à
/// l'UI pour affichage explicite, jamais silencieux.
class MediaUploadException implements Exception {
  final String message;
  const MediaUploadException(this.message);
  @override
  String toString() => message;
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final ChatMessageType type;
  final String? mediaUrl;
  final Uint8List? mediaBytes;
  final int? audioDurationMs;
  final List<double>? waveform; // amplitudes normalisées 0-1
  final DateTime timestamp;
  final DocumentSnapshot? snapshot; // pour la pagination
  final List<String> deletedFor; // UIDs pour qui le message est caché
  final bool deletedForAll; // supprimé pour tout le monde

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.timestamp,
    this.mediaUrl,
    this.mediaBytes,
    this.audioDurationMs,
    this.waveform,
    this.snapshot,
    this.deletedFor = const [],
    this.deletedForAll = false,
  });

  factory ChatMessage.fromDoc(
    DocumentSnapshot doc, {
    required String decryptedText,
    Uint8List? mediaBytes,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String? ?? 'text';
    final type = typeStr == 'image'
        ? ChatMessageType.image
        : typeStr == 'audio'
            ? ChatMessageType.audio
            : ChatMessageType.text;
    final deletedFor = (data['deletedFor'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        const [];
    final waveformRaw = data['waveform'] as List<dynamic>?;
    final waveform = waveformRaw?.map((e) => (e as num).toDouble()).toList();
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: decryptedText,
      type: type,
      mediaUrl: data['mediaUrl'] as String?,
      mediaBytes: mediaBytes,
      audioDurationMs: data['audioDurationMs'] as int?,
      waveform: waveform,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      snapshot: doc,
      deletedFor: deletedFor,
      deletedForAll: data['deletedForAll'] as bool? ?? false,
    );
  }
}

/// Données de présence du chat (wallpaper + read receipts + typing).
class ChatMeta {
  final Uint8List? wallpaperBytes;
  final DateTime? friendReadAt;
  final bool friendIsTyping;

  const ChatMeta({
    this.wallpaperBytes,
    this.friendReadAt,
    this.friendIsTyping = false,
  });
}

class PrivateChatService {
  final FirebaseFirestore? _injectedDb;
  final FirebaseStorage? _injectedStorage;
  final ChatCryptoService _crypto;
  final http.Client _httpClient;

  static const _baseUrl = SocketConnectionHandler.serverUrl;
  static const _pageSize = 15;
  static const _encryptedMessageUnavailable = 'Message chiffré indisponible';
  static const Duration _notificationTimeout = Duration(seconds: 5);

  /// Plafond d'un envoi média. Plus large que les timeouts de contrôle (clé/
  /// notification à 5 s) car un transfert d'image/audio est plus lourd, mais
  /// borné pour ne jamais pendre indéfiniment sur réseau dégradé.
  final Duration _mediaUploadTimeout;

  /// Uploads média en cours (pour annulation quand l'utilisateur quitte l'écran).
  final Set<UploadTask> _activeUploads = {};

  PrivateChatService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    ChatCryptoService? crypto,
    http.Client? httpClient,
    Duration? mediaUploadTimeout,
  })  : _injectedDb = db,
        _injectedStorage = storage,
        _crypto = crypto ?? ChatCryptoService(),
        _httpClient = httpClient ?? http.Client(),
        _mediaUploadTimeout = mediaUploadTimeout ?? const Duration(seconds: 30);

  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;

  String _otherParticipant(String cId, String senderId) {
    final parts = cId.split('_');
    if (parts.length != 2 || !parts.contains(senderId)) {
      throw ArgumentError('Identifiant de chat invalide');
    }
    return parts.first == senderId ? parts.last : parts.first;
  }

  /// Identifiant déterministe : toujours le plus petit userId en premier.
  static String chatId(String myId, String friendId) {
    final sorted = [myId, friendId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  CollectionReference<Map<String, dynamic>> _messages(String cId) =>
      _db.collection('private_chats').doc(cId).collection('messages');

  DocumentReference<Map<String, dynamic>> _chatDoc(String cId) =>
      _db.collection('private_chats').doc(cId);

  /// Stream combiné : fond déchiffré + friendReadAt + typing.
  Stream<ChatMeta> metaStream(String cId, String friendId) {
    return _chatDoc(cId).snapshots().asyncMap((doc) async {
      final data = doc.data();
      Uint8List? wallpaperBytes;
      final wallpaperPath = data?['wallpaperPath'] as String?;
      if (wallpaperPath != null) {
        try {
          final key = await _crypto.getChatKey(cId, friendId);
          final encrypted = await _storage
              .ref()
              .child(wallpaperPath)
              .getData(5 * 1024 * 1024)
              .timeout(_mediaUploadTimeout);
          if (encrypted != null) {
            wallpaperBytes = await _crypto.decryptBytes(key, encrypted);
          }
        } catch (_) {}
      }
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
        wallpaperBytes: wallpaperBytes,
        friendReadAt: friendTs?.toDate(),
        friendIsTyping: friendIsTyping,
      );
    });
  }

  Future<void> setWallpaper(
      String cId, String senderId, Uint8List bytes) async {
    final key = await _crypto.getChatKey(cId, _otherParticipant(cId, senderId));
    final encrypted = await _crypto.encryptBytes(key, bytes);
    final ref = _storage.ref().child('chat_wallpapers/$cId.enc');
    await _runBoundedUpload(ref.putData(
        encrypted, SettableMetadata(contentType: 'application/octet-stream')));
    await _chatDoc(cId)
        .set({'wallpaperPath': ref.fullPath}, SetOptions(merge: true));
  }

  Future<void> removeWallpaper(String cId) async {
    await _chatDoc(cId).update({'wallpaperPath': FieldValue.delete()});
    try {
      await _storage.ref().child('chat_wallpapers/$cId.enc').delete();
    } catch (_) {}
  }

  /// Stream du nombre de messages non lus pour un chat donné.
  Stream<int> unreadCountStream(String cId, String myUserId) {
    return _chatDoc(cId).snapshots().asyncMap((doc) async {
      final data = doc.data();
      final receipts = data?['readReceipts'] as Map<String, dynamic>?;
      final myReadTs = receipts?[myUserId] as Timestamp?;

      Query<Map<String, dynamic>> query = _messages(cId);
      if (myReadTs != null) {
        query = query.where('timestamp', isGreaterThan: myReadTs);
      }
      // Ne compter que les messages de l'autre personne
      final snap = await query.get();
      return snap.docs
          .where((d) => (d.data()['senderId'] as String?) != myUserId)
          .length;
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
    String cId,
    String friendId,
    DocumentSnapshot before,
  ) async {
    final snap = await _messages(cId)
        .orderBy('timestamp', descending: false)
        .endBeforeDocument(before)
        .limitToLast(_pageSize)
        .get();
    return _decryptSnapshotList(snap.docs, cId, friendId);
  }

  Future<List<ChatMessage>> _decryptSnapshot(
    QuerySnapshot snap,
    String cId,
    String friendId,
  ) async {
    return _decryptSnapshotList(snap.docs, cId, friendId);
  }

  Future<List<ChatMessage>> _decryptSnapshotList(
    List<QueryDocumentSnapshot> docs,
    String cId,
    String friendId,
  ) async {
    SecretKey? key;
    try {
      key = await _crypto.getChatKey(cId, friendId);
    } catch (_) {
      key = null;
    }

    final results = <ChatMessage>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type'] as String? ?? 'text';
      final raw = data['text'] as String? ?? '';
      String decrypted = '';
      if (type == 'text' && raw.isNotEmpty) {
        if (key == null) {
          decrypted = _encryptedMessageUnavailable;
        } else {
          decrypted =
              await _crypto.decrypt(key, raw) ?? _encryptedMessageUnavailable;
        }
      }
      Uint8List? mediaBytes;
      final mediaPath = data['mediaPath'] as String?;
      if (type != 'text' && mediaPath != null && key != null) {
        try {
          final encrypted = await _storage
              .ref()
              .child(mediaPath)
              .getData(10 * 1024 * 1024)
              .timeout(_mediaUploadTimeout);
          if (encrypted != null) {
            mediaBytes = await _crypto.decryptBytes(key, encrypted);
          }
        } catch (_) {}
      }
      results.add(ChatMessage.fromDoc(doc,
          decryptedText: decrypted, mediaBytes: mediaBytes));
    }
    return results;
  }

  Future<void> sendMessage(
    String cId,
    String senderId,
    String text,
    String friendId,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final key = await _crypto.getChatKey(cId, friendId);
    final payload = await _crypto.encrypt(key, trimmed);

    await _messages(cId).add({
      'senderId': senderId,
      'type': 'text',
      'text': payload,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Push notification
    _sendChatNotification(chatId: cId, recipientId: friendId);
  }

  /// Exécute un upload borné : reporte la progression (0..1), applique le
  /// plafond média — en ANNULANT la tâche au dépassement pour ne pas la laisser
  /// tourner en arrière-plan. Toute
  /// erreur/timeout devient une [MediaUploadException] visible (pas de silence,
  /// pas de fallback dégradé).
  Future<void> _runBoundedUpload(
    UploadTask task, {
    void Function(double progress)? onProgress,
  }) async {
    _activeUploads.add(task);
    StreamSubscription<TaskSnapshot>? sub;
    if (onProgress != null) {
      sub = task.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total > 0) {
          onProgress((snap.bytesTransferred / total).clamp(0.0, 1.0));
        }
      }, onError: (_) {});
    }
    try {
      await task.timeout(
        _mediaUploadTimeout,
        onTimeout: () {
          unawaited(task.cancel());
          throw const MediaUploadException('Envoi média expiré');
        },
      );
    } on MediaUploadException {
      rethrow;
    } on TimeoutException {
      unawaited(task.cancel());
      throw const MediaUploadException('Envoi média expiré');
    } on FirebaseException catch (e) {
      throw MediaUploadException(
        e.code == 'canceled' ? 'Envoi média annulé' : 'Échec envoi média',
      );
    } finally {
      await sub?.cancel();
      _activeUploads.remove(task);
    }
  }

  /// Annule tous les envois média en cours. À appeler à la fermeture de l'écran
  /// de chat pour ne pas laisser un upload pendre indéfiniment en arrière-plan.
  Future<void> cancelActiveMediaUploads() async {
    final pending = List<UploadTask>.of(_activeUploads);
    _activeUploads.clear();
    for (final task in pending) {
      try {
        await task.cancel();
      } catch (_) {}
    }
  }

  Future<void> sendImageBytes(
    String cId,
    String senderId,
    List<int> bytes, {
    void Function(double progress)? onProgress,
  }) async {
    await _sendEncryptedMedia(
        cId, senderId, Uint8List.fromList(bytes), ChatMessageType.image,
        onProgress: onProgress);
  }

  Future<void> _sendEncryptedMedia(
      String cId, String senderId, Uint8List bytes, ChatMessageType type,
      {int? durationMs,
      List<double>? waveform,
      void Function(double progress)? onProgress}) async {
    final friendId = _otherParticipant(cId, senderId);
    final key = await _crypto.getChatKey(cId, friendId);
    final encrypted = await _crypto.encryptBytes(key, bytes);
    final ref = _storage.ref().child(
          'chat_media/$cId/${DateTime.now().microsecondsSinceEpoch}.enc',
        );
    await _runBoundedUpload(
        ref.putData(encrypted,
            SettableMetadata(contentType: 'application/octet-stream')),
        onProgress: onProgress);
    await _messages(cId).add({
      'senderId': senderId,
      'type': type.name,
      'text': '',
      'mediaPath': ref.fullPath,
      if (durationMs != null) 'audioDurationMs': durationMs,
      if (waveform != null) 'waveform': waveform,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendImage(
    String cId,
    String senderId,
    File imageFile, {
    void Function(double progress)? onProgress,
  }) async {
    await sendImageBytes(cId, senderId, await imageFile.readAsBytes(),
        onProgress: onProgress);
  }

  Future<void> sendAudio(
    String cId,
    String senderId,
    File audioFile,
    int durationMs, {
    List<double>? waveform,
    void Function(double progress)? onProgress,
  }) async {
    await _sendEncryptedMedia(
        cId, senderId, await audioFile.readAsBytes(), ChatMessageType.audio,
        durationMs: durationMs, waveform: waveform, onProgress: onProgress);
  }

  /// Web uniquement : fetch le blob URL et upload les bytes vers Firebase Storage.
  Future<void> sendAudioFromUrl(
    String cId,
    String senderId,
    String blobUrl,
    int durationMs, {
    List<double>? waveform,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await _fetchBytes(blobUrl);
    await _sendEncryptedMedia(cId, senderId, bytes, ChatMessageType.audio,
        durationMs: durationMs, waveform: waveform, onProgress: onProgress);
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final response =
        await _httpClient.get(Uri.parse(url)).timeout(_mediaUploadTimeout);
    return response.bodyBytes;
  }

  /// Supprime un message uniquement pour [myUserId] (les autres le voient toujours).
  Future<void> deleteMessageForMe(
    String cId,
    String messageId,
    String myUserId,
  ) async {
    await _messages(cId).doc(messageId).update({
      'deletedFor': FieldValue.arrayUnion([myUserId]),
    });
  }

  /// Supprime un message pour tout le monde (marque deletedForAll = true).
  Future<void> deleteMessageForAll(String cId, String messageId) async {
    await _messages(cId).doc(messageId).update({'deletedForAll': true});
  }

  /// Envoie une push notification au destinataire (best-effort, silencieux en cas d'erreur).
  Future<void> _sendChatNotification({
    required String chatId,
    required String recipientId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final senderName = user.displayName ?? 'Quelqu\'un';

      await _httpClient
          .post(
            Uri.parse('$_baseUrl/api/chats/$chatId/notify'),
            headers: await SecureApiHeaders.json(bearerToken: token),
            body: jsonEncode({
              'recipientId': recipientId,
              'senderName': senderName,
            }),
          )
          .timeout(_notificationTimeout);
    } catch (_) {
      // Silencieux — la notification n'est pas critique
    }
  }
}
