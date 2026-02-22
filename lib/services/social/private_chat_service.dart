import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class PrivateChatService {
  final FirebaseFirestore _db;

  PrivateChatService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Identifiant déterministe : toujours le plus petit userId en premier.
  static String chatId(String myId, String friendId) {
    final sorted = [myId, friendId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  CollectionReference<Map<String, dynamic>> _messages(String cId) =>
      _db.collection('private_chats').doc(cId).collection('messages');

  Stream<List<ChatMessage>> messagesStream(String cId) {
    return _messages(cId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> sendMessage(String cId, String senderId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _messages(cId).add({
      'senderId': senderId,
      'text': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
