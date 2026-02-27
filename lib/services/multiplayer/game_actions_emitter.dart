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

  /// Émet un événement de manière sécurisée
  /// Retourne true si l'émission a été faite, false sinon
  bool _safeEmit(String event, Map<String, dynamic> data) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      if (kDebugMode) {
        debugPrint('⚠️ Socket non connecté, action $event ignorée');
      }
      return false;
    }
    if (_roomCode == null) {
      if (kDebugMode) debugPrint('⚠️ Pas de roomCode, action $event ignorée');
      return false;
    }
    socket.emit(event, data);
    return true;
  }

  void drawCard() {
    if (kDebugMode) debugPrint('🃏 Pioche une carte');
    _safeEmit('game:draw_card', {'roomCode': _roomCode});
  }

  void replaceCard(int cardIndex) {
    if (kDebugMode) debugPrint('🔄 Remplace carte $cardIndex');
    _safeEmit('game:replace_card', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  void discardDrawnCard() {
    if (kDebugMode) debugPrint('🗑️ Rejette la carte piochée');
    _safeEmit('game:discard_card', {'roomCode': _roomCode});
  }

  void takeFromDiscard() {
    if (kDebugMode) debugPrint('♻️ Prend de la défausse');
    _safeEmit('game:take_from_discard', {'roomCode': _roomCode});
  }

  void callDutch() {
    if (kDebugMode) debugPrint('📢 DUTCH !');
    _safeEmit('game:call_dutch', {'roomCode': _roomCode});
  }

  void attemptMatch(int cardIndex) {
    if (kDebugMode) debugPrint('🎯 Tente de matcher carte $cardIndex');
    _safeEmit('game:attempt_match', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  /// Carte 7 : Regarder sa propre carte
  void usePower7LookOwnCard(int cardIndex) {
    if (kDebugMode) {
      debugPrint('👁️ Pouvoir 7 : Regarde sa carte #${cardIndex + 1}');
    }
    _safeEmit('game:use_special_power', {
      'roomCode': _roomCode,
      'cardIndex': cardIndex,
    });
  }

  /// Carte 10 : Espionner une carte adversaire
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) {
    if (kDebugMode) {
      debugPrint(
          '🔍 Pouvoir 10 : Espionne joueur $targetPlayerIndex carte #${targetCardIndex + 1}');
    }
    _safeEmit('game:use_special_power', {
      'roomCode': _roomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  /// Carte V (Valet) : Échange universel entre 2 joueurs
  void usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    if (kDebugMode) {
      debugPrint(
          '🔄 Pouvoir Valet : Échange joueur $player1Index carte #${card1Index + 1} ↔ joueur $player2Index carte #${card2Index + 1}');
    }
    _safeEmit('game:use_special_power', {
      'roomCode': _roomCode,
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  /// JOKER : Mélanger la main d'un joueur (y compris soi-même)
  void usePowerJokerShuffle(int targetPlayerIndex) {
    if (kDebugMode) {
      debugPrint('🃏 Pouvoir Joker : Mélange joueur $targetPlayerIndex');
    }
    _safeEmit('game:use_special_power', {
      'roomCode': _roomCode,
      'targetPlayerIndex': targetPlayerIndex,
    });
  }

  /// Emission de la sélection partielle (pour retour visuel en temps réel)
  void sendSpecialPowerTargetSelection(
      int? player1Index, int? card1Index, int? player2Index, int? card2Index) {
    if (kDebugMode) {
      debugPrint('🎯 Sélection partielle Valet : '
          'p1=$player1Index c1=$card1Index '
          'p2=$player2Index c2=$card2Index');
    }
    _safeEmit('special_power:target_selection', {
      'roomCode': _roomCode,
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  void skipSpecialPower() {
    if (kDebugMode) debugPrint('⏭️ Ignore le pouvoir spécial');
    _safeEmit('game:skip_special_power', {'roomCode': _roomCode});
  }

  void setReady(bool ready) {
    _safeEmit('room:ready', {'roomCode': _roomCode, 'ready': ready});
  }

  void sendChatMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    _safeEmit('chat:send', {'roomCode': _roomCode, 'message': trimmed});
  }

  void setFocused(bool focused) {
    _safeEmit('presence:focus', {
      'roomCode': _roomCode,
      'focused': focused,
    });
  }

  void confirmPresence() {
    _safeEmit('presence:ack', {'roomCode': _roomCode});
  }

  void markReady() {
    _safeEmit('player:ready', {'roomCode': _roomCode});
  }

  void cancelGame() {
    if (kDebugMode) debugPrint('🏳️ Abandon de la partie...');
    _safeEmit('game:forfeit', {'roomCode': _roomCode});
  }

  void requestFullState() {
    if (kDebugMode) debugPrint('🔄 Demande de synchronisation...');
    _safeEmit('game:request_state', {'roomCode': _roomCode});
  }
}
