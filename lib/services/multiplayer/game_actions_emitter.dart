import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Émetteur d'actions de jeu vers le serveur
/// Principe GRASP: Information Expert - Sait comment envoyer les actions de jeu
class GameActionsEmitter {
  static const Duration _actionAckTimeout = Duration(seconds: 5);

  final io.Socket? Function() _getSocket;
  final String? Function() _getRoomCode;
  int _actionSequence = 0;

  GameActionsEmitter({
    required io.Socket? Function() getSocket,
    required String? Function() getRoomCode,
  })  : _getSocket = getSocket,
        _getRoomCode = getRoomCode;

  io.Socket? get _socket => _getSocket();
  String? get _roomCode => _getRoomCode();

  String _nextActionId(String event) {
    _actionSequence += 1;
    final sanitizedEvent = event.replaceAll(':', '_');
    return '$sanitizedEvent-${DateTime.now().microsecondsSinceEpoch}-$_actionSequence';
  }

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

  Future<bool> _safeEmitWithAck(String event, Map<String, dynamic> data) {
    final socket = _socket;
    final roomCode = _roomCode;
    if (socket == null || !socket.connected) {
      if (kDebugMode) {
        debugPrint('⚠️ Socket non connecté, action $event ignorée');
      }
      return Future.value(false);
    }
    if (roomCode == null) {
      if (kDebugMode) debugPrint('⚠️ Pas de roomCode, action $event ignorée');
      return Future.value(false);
    }

    final completer = Completer<bool>();
    Timer? timeout;

    void complete(bool value) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      completer.complete(value);
    }

    final actionId = _nextActionId(event);
    final payload = <String, dynamic>{
      ...data,
      'roomCode': roomCode,
      'actionId': actionId,
    };

    timeout = Timer(_actionAckTimeout, () {
      if (kDebugMode) {
        debugPrint('⏱️ ACK $event expiré actionId=$actionId');
      }
      complete(false);
    });

    socket.emitWithAck(event, payload, ack: (response) {
      final success = response is Map
          ? response['success'] == true || response['ok'] == true
          : response == true;
      if (!success && kDebugMode) {
        debugPrint('⚠️ Action $event refusée: $response');
      }
      complete(success);
    });

    return completer.future;
  }

  Future<bool> drawCard() {
    if (kDebugMode) debugPrint('🃏 Pioche une carte');
    return _safeEmitWithAck('game:draw_card', const {});
  }

  Future<bool> replaceCard(int cardIndex) {
    if (kDebugMode) debugPrint('🔄 Remplace carte $cardIndex');
    return _safeEmitWithAck('game:replace_card', {
      'cardIndex': cardIndex,
    });
  }

  Future<bool> discardDrawnCard() {
    if (kDebugMode) debugPrint('🗑️ Rejette la carte piochée');
    return _safeEmitWithAck('game:discard_card', const {});
  }

  Future<bool> callDutch() {
    if (kDebugMode) debugPrint('📢 DUTCH !');
    return _safeEmitWithAck('game:call_dutch', const {});
  }

  Future<bool> attemptMatch(int cardIndex) {
    if (kDebugMode) debugPrint('🎯 Tente de matcher carte $cardIndex');
    return _safeEmitWithAck('game:attempt_match', {
      'cardIndex': cardIndex,
    });
  }

  /// Carte 7 : Regarder sa propre carte
  Future<bool> usePower7LookOwnCard(int cardIndex) {
    if (kDebugMode) {
      debugPrint('👁️ Pouvoir 7 : Regarde sa carte #${cardIndex + 1}');
    }
    return _safeEmitWithAck('game:use_special_power', {
      'cardIndex': cardIndex,
    });
  }

  /// Carte 10 : Espionner une carte adversaire
  Future<bool> usePower10SpyOpponent(
      int targetPlayerIndex, int targetCardIndex) {
    if (kDebugMode) {
      debugPrint(
          '🔍 Pouvoir 10 : Espionne joueur $targetPlayerIndex carte #${targetCardIndex + 1}');
    }
    return _safeEmitWithAck('game:use_special_power', {
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  /// Carte V (Valet) : Échange universel entre 2 joueurs
  Future<bool> usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    if (kDebugMode) {
      debugPrint(
          '🔄 Pouvoir Valet : Échange joueur $player1Index carte #${card1Index + 1} ↔ joueur $player2Index carte #${card2Index + 1}');
    }
    return _safeEmitWithAck('game:use_special_power', {
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  /// JOKER : Mélanger la main d'un joueur (y compris soi-même)
  Future<bool> usePowerJokerShuffle(int targetPlayerIndex) {
    if (kDebugMode) {
      debugPrint('🃏 Pouvoir Joker : Mélange joueur $targetPlayerIndex');
    }
    return _safeEmitWithAck('game:use_special_power', {
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

  Future<bool> skipSpecialPower() {
    if (kDebugMode) debugPrint('⏭️ Ignore le pouvoir spécial');
    return _safeEmitWithAck('game:skip_special_power', const {});
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
