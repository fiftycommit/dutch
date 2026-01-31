import 'package:flutter/widgets.dart';
import '../../../services/ui/emote_service.dart';

/// Gère le chat et les emotes du mode multijoueur
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion du chat
class MultiplayerChatManager {
  final VoidCallback _notifyListeners;
  final EmoteService _emoteService = EmoteService();

  final List<Map<String, dynamic>> _chatMessages = [];
  final List<EmoteEvent> _recentEmotes = [];

  List<Map<String, dynamic>> get chatMessages => List.unmodifiable(_chatMessages);
  List<EmoteEvent> get recentEmotes => List.unmodifiable(_recentEmotes);
  Stream<EmoteEvent> get emoteStream => _emoteService.emoteStream;

  MultiplayerChatManager({required VoidCallback notifyListeners})
      : _notifyListeners = notifyListeners;

  void handleChatMessage(Map<String, dynamic> data) {
    _chatMessages.add(data);
    if (_chatMessages.length > 120) {
      _chatMessages.removeAt(0);
    }
    _notifyListeners();
  }

  void addLocalEmote(String emoji, String playerName, String playerId) {
    final emote = EmoteEvent(
      emoji: emoji,
      playerName: playerName,
      playerId: playerId,
      timestamp: DateTime.now(),
    );
    _emoteService.sendEmote(emoji, playerName, playerId);
    _recentEmotes.add(emote);
    if (_recentEmotes.length > 10) {
      _recentEmotes.removeAt(0);
    }
    _notifyListeners();
  }

  void reset() {
    _chatMessages.clear();
    _recentEmotes.clear();
  }
}
