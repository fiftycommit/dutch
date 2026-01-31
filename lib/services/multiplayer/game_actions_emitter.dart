import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Émetteur d'actions de jeu vers le serveur
/// Principe GRASP: Information Expert - Sait comment envoyer les actions de jeu
class GameActionsEmitter {
  final io.Socket? Function() _getSocket;
  final String? Function() _getRoomCode;

  GameActionsEmitter({
    required io.Socket? Function() getSocket,
    required String? Function() getRoomCode,
  })  : _getSocket = getSocket,
        _getRoomCode = getRoomCode;

  io.Socket? get _socket => _getSocket();
  String? get _roomCode => _getRoomCode();

  void drawCard() {
    debugPrint('🃏 Pioche une carte');
    _socket?.emit('game:draw_card', {'roomCode': _roomCode});
  }

  void replaceCard(int cardIndex) {
    debugPrint('🔄 Remplace carte $cardIndex');
    _socket?.emit('game:replace_card', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  void discardDrawnCard() {
    debugPrint('🗑️ Rejette la carte piochée');
    _socket?.emit('game:discard_card', {'roomCode': _roomCode});
  }

  void takeFromDiscard() {
    debugPrint('♻️ Prend de la défausse');
    _socket?.emit('game:take_from_discard', {'roomCode': _roomCode});
  }

  void callDutch() {
    debugPrint('📢 DUTCH !');
    _socket?.emit('game:call_dutch', {'roomCode': _roomCode});
  }

  void attemptMatch(int cardIndex) {
    debugPrint('🎯 Tente de matcher carte $cardIndex');
    _socket?.emit('game:attempt_match', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  /// Carte 7 : Regarder sa propre carte
  void usePower7LookOwnCard(int cardIndex) {
    debugPrint('👁️ Pouvoir 7 : Regarde sa carte #${cardIndex + 1}');
    _socket?.emit('game:use_special_power', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  /// Carte 10 : Espionner une carte adversaire
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) {
    debugPrint(
        '🔍 Pouvoir 10 : Espionne joueur $targetPlayerIndex carte #${targetCardIndex + 1}');
    _socket?.emit('game:use_special_power', {
      'roomCode': _roomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  /// Carte V (Valet) : Échange universel entre 2 joueurs
  void usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    debugPrint(
        '🔄 Pouvoir Valet : Échange joueur $player1Index carte #${card1Index + 1} ↔ joueur $player2Index carte #${card2Index + 1}');
    _socket?.emit('game:use_special_power', {
      'roomCode': _roomCode,
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  /// JOKER : Mélanger la main d'un joueur (y compris soi-même)
  void usePowerJokerShuffle(int targetPlayerIndex) {
    debugPrint('🃏 Pouvoir Joker : Mélange joueur $targetPlayerIndex');
    _socket?.emit('game:use_special_power', {
      'roomCode': _roomCode,
      'targetPlayerIndex': targetPlayerIndex,
    });
  }

  void skipSpecialPower() {
    debugPrint('⏭️ Ignore le pouvoir spécial');
    _socket?.emit('game:skip_special_power', {'roomCode': _roomCode});
  }

  void setReady(bool ready) {
    if (_roomCode == null) return;
    _socket?.emitWithAck(
      'room:ready',
      {'roomCode': _roomCode, 'ready': ready},
      ack: (_) {},
    );
  }

  void sendChatMessage(String message) {
    if (_roomCode == null) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    _socket?.emitWithAck(
      'chat:send',
      {'roomCode': _roomCode, 'message': trimmed},
      ack: (_) {},
    );
  }

  void setFocused(bool focused) {
    if (_roomCode == null) return;
    _socket?.emit('presence:focus', {
      'roomCode': _roomCode,
      'focused': focused,
    });
  }

  void confirmPresence() {
    if (_roomCode == null) return;
    _socket?.emit('presence:ack', {'roomCode': _roomCode});
  }

  void markReady() {
    if (_roomCode == null) return;
    _socket?.emit('player:ready', {'roomCode': _roomCode});
  }

  void cancelGame() {
    if (_roomCode == null) return;
    debugPrint('🏳️ Abandon de la partie...');
    _socket?.emit('game:forfeit', {'roomCode': _roomCode});
  }

  void requestFullState() {
    if (_roomCode == null) return;
    debugPrint('🔄 Demande de synchronisation...');
    _socket?.emit('game:request_state', {'roomCode': _roomCode});
  }
}
