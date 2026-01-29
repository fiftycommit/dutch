import 'dart:async';

class EmoteEvent {
  final String emoji;
  final String playerName;
  final String playerId;
  final DateTime timestamp;

  EmoteEvent({
    required this.emoji,
    required this.playerName,
    required this.playerId,
    required this.timestamp,
  });
}

class EmoteService {
  static final EmoteService _instance = EmoteService._internal();
  factory EmoteService() => _instance;
  EmoteService._internal();

  final StreamController<EmoteEvent> _emoteController =
      StreamController<EmoteEvent>.broadcast();

  Stream<EmoteEvent> get emoteStream => _emoteController.stream;

  void sendEmote(String emoji, String playerName, String playerId) {
    _emoteController.add(EmoteEvent(
      emoji: emoji,
      playerName: playerName,
      playerId: playerId,
      timestamp: DateTime.now(),
    ));
  }

  void dispose() {
    _emoteController.close();
  }
}
