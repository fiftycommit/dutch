import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/services/multiplayer_service.dart';

class FakeMultiplayerService extends MultiplayerService {
  FakeMultiplayerService({
    this.fakePlayerId = 'p1',
    this.fakeClientId = 'c1',
    this.fakeLatencyMs = 0,
    int? fakeServerNowMs,
  }) : _serverNowMs =
            fakeServerNowMs ?? DateTime.now().millisecondsSinceEpoch;

  final String fakePlayerId;
  final String fakeClientId;
  int fakeLatencyMs;
  int _serverNowMs;

  bool focusedSent = false;
  bool presenceAcked = false;

  void setServerNowMs(int value) {
    _serverNowMs = value;
  }

  void emitGameState(GameState state) {
    onGameStateUpdate?.call(state);
  }

  void emitReactionConfig(int ms) {
    onReactionTimeConfig?.call(ms);
  }

  void emitPresenceUpdate(List<Map<String, dynamic>> players,
      {String hostPlayerId = 'p1'}) {
    onPresenceUpdate?.call({'hostPlayerId': hostPlayerId, 'players': players});
  }

  void emitPresenceCheck({String reason = 'AFK', int deadlineMs = 5000}) {
    onPresenceCheck?.call({'reason': reason, 'deadlineMs': deadlineMs});
  }

  @override
  bool get isConnected => true;

  @override
  String? get playerId => fakePlayerId;

  @override
  String? get clientId => fakeClientId;

  @override
  int get latencyMs => fakeLatencyMs;

  @override
  int get serverNowMs => _serverNowMs;

  @override
  Future<void> connect() async {}

  @override
  Future<String?> createRoom({
    required settings,
    required String playerName,
  }) async =>
      'ABC123';

  @override
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async =>
      null;

  @override
  Future<bool> startGame({bool fillBots = false}) async => true;

  @override
  void setFocused(bool focused) {
    focusedSent = focused;
  }

  @override
  void confirmPresence() {
    presenceAcked = true;
  }
}

GameState _reactionState({
  required DateTime reactionStart,
  required int reactionTimeRemaining,
}) {
  return GameState(
    players: [
      Player(id: 'p1', name: 'Me', isHuman: true, position: 0),
      Player(id: 'p2', name: 'You', isHuman: true, position: 1),
    ],
    deck: [],
    discardPile: [],
    currentPlayerIndex: 0,
    phase: GamePhase.reaction,
    reactionStartTime: reactionStart,
    reactionTimeRemaining: reactionTimeRemaining,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiplayerGameProvider', () {
    test('maps presence by id/clientId and clears presence check on confirm', () {
      final fakeService = FakeMultiplayerService();
      final provider = MultiplayerGameProvider(multiplayerService: fakeService);

      fakeService.emitPresenceUpdate([
        {
          'id': 'p1',
          'clientId': 'c1',
          'connected': true,
          'focused': true,
        },
        {
          'id': 'p2',
          'clientId': 'c2',
          'connected': true,
          'focused': false,
        },
      ]);

      expect(provider.presenceById['p1']?['connected'], isTrue);
      expect(provider.presenceByClientId['c2']?['focused'], isFalse);

      fakeService.emitPresenceCheck(reason: 'Temps de jeu écoulé', deadlineMs: 4000);
      expect(provider.presenceCheckActive, isTrue);
      expect(provider.presenceCheckReason, contains('Temps de jeu'));
      expect(provider.presenceCheckDeadlineMs, 4000);

      provider.confirmPresence();
      expect(fakeService.presenceAcked, isTrue);
      expect(provider.presenceCheckActive, isFalse);

      provider.dispose();
    });

    test('syncs reaction timer from server time and latency compensation', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final fakeService = FakeMultiplayerService(
        fakeLatencyMs: 200,
        fakeServerNowMs: nowMs,
      );
      final provider = MultiplayerGameProvider(multiplayerService: fakeService);

      fakeService.emitReactionConfig(3000);

      final start = DateTime.fromMillisecondsSinceEpoch(nowMs - 1000);
      fakeService.emitGameState(
        _reactionState(reactionStart: start, reactionTimeRemaining: 3000),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final remaining = provider.gameState?.reactionTimeRemaining ?? 0;
      // 3000 - 1000 elapsed - ~100ms latency compensation ~= 1900ms
      expect(remaining, inInclusiveRange(1700, 2100));

      provider.dispose();
    });
  });
}
