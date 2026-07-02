import 'package:flutter/widgets.dart';
import 'package:dutch_game/core/interfaces/i_haptic_service.dart';
import 'package:dutch_game/core/interfaces/i_stats_service.dart';
import 'package:dutch_game/core/interfaces/i_bot_ai_service.dart';
import 'package:dutch_game/services/game/bot/hardcore_bot_config.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';

/// Mock HapticService for testing
class MockHapticService implements IHapticService {
  bool _enabled = true;
  int cardTapCount = 0;
  int buttonTapCount = 0;
  int importantActionCount = 0;
  int errorCount = 0;
  int successCount = 0;

  @override
  Future<void> cardTap() async => cardTapCount++;

  @override
  Future<void> buttonTap() async => buttonTapCount++;

  @override
  Future<void> importantAction() async => importantActionCount++;

  @override
  Future<void> error() async => errorCount++;

  @override
  Future<void> success() async => successCount++;

  @override
  void setEnabled(bool enabled) => _enabled = enabled;

  @override
  bool get isEnabled => _enabled;

  void reset() {
    cardTapCount = 0;
    buttonTapCount = 0;
    importantActionCount = 0;
    errorCount = 0;
    successCount = 0;
  }
}

/// Mock StatsService for testing
class MockStatsService implements IStatsService {
  Map<String, dynamic> mockStats = {
    'gamesPlayed': 10,
    'gamesWon': 5,
    'mmr': 500,
    'winStreak': 2,
    'bestScore': 5,
  };

  List<Map<String, dynamic>> savedResults = [];
  int resetCount = 0;

  @override
  Future<Map<String, dynamic>> getStats({int slotId = 1}) async {
    return Map.from(mockStats);
  }

  @override
  Future<void> saveGameResult({
    required int playerRank,
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    bool hasEmptyHand = false,
    int slotId = 1,
    bool isSBMM = false,
    int totalPlayers = 4,
    bool isTournament = false,
    int tournamentRound = 1,
    String? tournamentId,
    List<String>? actionHistory,
    String? gameLog,
    String? scoreDetail,
  }) async {
    savedResults.add({
      'playerRank': playerRank,
      'score': score,
      'calledDutch': calledDutch,
      'wonDutch': wonDutch,
      'hasEmptyHand': hasEmptyHand,
      'slotId': slotId,
      'isSBMM': isSBMM,
    });
  }

  @override
  Future<void> resetStats({int slotId = 1}) async {
    resetCount++;
    mockStats = {
      'gamesPlayed': 0,
      'gamesWon': 0,
      'mmr': 0,
      'winStreak': 0,
      'bestScore': 0,
    };
  }

  @override
  Future<Difficulty> getRecommendedDifficulty({int slotId = 1}) async {
    final mmr = mockStats['mmr'] ?? 0;
    if (mmr < 300) return Difficulty.easy;
    if (mmr < 600) return Difficulty.medium;
    return Difficulty.hard;
  }

  @override
  String getRankName(int mmr) {
    if (mmr < 300) return 'Bronze';
    if (mmr < 600) return 'Argent';
    if (mmr < 900) return 'Or';
    return 'Platine';
  }

  void reset() {
    savedResults.clear();
    resetCount = 0;
    mockStats = {
      'gamesPlayed': 10,
      'gamesWon': 5,
      'mmr': 500,
      'winStreak': 2,
      'bestScore': 5,
    };
  }

  // Télémétrie AI
  List<Map<String, dynamic>> aiTelemetryRecords = [];

  @override
  Future<void> recordAiTelemetry(Map<String, dynamic> telemetry,
      {int slotId = 1}) async {
    aiTelemetryRecords.add(telemetry);
  }
}

/// Mock BotAIService for testing
class MockBotAIService implements IBotAIService {
  int playBotTurnCount = 0;
  int tryReactionMatchCount = 0;
  int useBotSpecialPowerCount = 0;
  bool reactionMatchResult = false;
  bool callDutchOnPlay = false;

  @override
  Future<void> playBotTurn(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    playBotTurnCount++;
    if (callDutchOnPlay) {
      gameState.dutchCallerId = gameState.currentPlayer.id;
      gameState.phase = GamePhase.dutchCalled;
    }
  }

  @override
  Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot, {
    int? playerMMR,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    tryReactionMatchCount++;
    return reactionMatchResult;
  }

  @override
  Future<void> useBotSpecialPower(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    useBotSpecialPowerCount++;
  }

  void reset() {
    playBotTurnCount = 0;
    tryReactionMatchCount = 0;
    useBotSpecialPowerCount = 0;
    reactionMatchResult = false;
    callDutchOnPlay = false;
  }
}
