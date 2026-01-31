import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player_learning_data.dart';
import 'package:dutch_game/providers/game_tracking_provider.dart';

/// Mock GameTrackingProvider for testing
class MockGameTrackingProvider extends GameTrackingProvider {
  String? currentGameId;
  int humanActionCounter = 0;
  List<Map<String, dynamic>> recordedActions = [];
  int initTrackingCount = 0;
  int finalizeBotRecordingsCount = 0;

  @override
  void startGameRecording({
    required GameState gameState,
    required int slotId,
    required bool useSBMM,
  }) {
    currentGameId = DateTime.now().millisecondsSinceEpoch.toString();
    humanActionCounter = 0;
  }

  @override
  void recordPlayerAction({
    required String actionType,
    required GameState gameState,
    required Map<String, dynamic> actionDetails,
    String? powerType,
    String? targetStrategy,
  }) {
    recordedActions.add({
      'actionType': actionType,
      'actionDetails': actionDetails,
      'powerType': powerType,
      'targetStrategy': targetStrategy,
    });
    humanActionCounter++;
  }

  @override
  void updateLastActionResult({required Map<String, dynamic> result}) {
    if (recordedActions.isNotEmpty) {
      recordedActions.last['result'] = result;
    }
  }

  @override
  void recordPlayerActionWithResult({
    required String actionType,
    required GameState gameState,
    required Map<String, dynamic> actionDetails,
    required Map<String, dynamic> result,
    String? powerType,
    String? targetStrategy,
  }) {
    recordedActions.add({
      'actionType': actionType,
      'actionDetails': actionDetails,
      'result': result,
      'powerType': powerType,
      'targetStrategy': targetStrategy,
    });
    humanActionCounter++;
  }

  @override
  void incrementBotTurns(GameState gameState) {}

  @override
  void recordBotDiscards(GameState gameState) {}

  @override
  Future<void> endBotRecording({
    required String botPlayerId,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
    required int cardsAtDutch,
    required int scoreAtDutch,
    required int humanFinalScore,
    required int humanFinalHandSize,
    required int botFinalHandSize,
  }) async {}

  @override
  Future<PlayerProfile> endPlayerRecording({
    required int slotId,
    required bool usedSBMM,
    required GameState gameState,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
  }) async {
    return PlayerProfile.defaultProfile(profileId: 'slot_$slotId');
  }

  @override
  void initTracking(GameState gameState, bool useSBMM) {
    initTrackingCount++;
    currentGameId = DateTime.now().millisecondsSinceEpoch.toString();
    humanActionCounter = 0;
  }

  @override
  Future<void> finalizeBotRecordings(GameState gameState) async {
    finalizeBotRecordingsCount++;
  }

  @override
  void reset() {
    currentGameId = null;
    humanActionCounter = 0;
    recordedActions.clear();
    initTrackingCount = 0;
    finalizeBotRecordingsCount = 0;
  }
}
