import 'package:flutter/foundation.dart';
import 'sbmm_local_service.dart';

/// Façade SBMM côté client.
///
/// Le SBMM est 100% local : pas de compte, pas de sync cross-device.
/// Ce service délègue à [SBMMLocalService] et préserve l'API utilisée par
/// le reste de l'app ([BotFactory], [GameProvider], setup screen).
class SBMMClientService {
  static Future<SBMMBotMixResult> getBotMix({
    required int botCount,
    required int slotId,
  }) async {
    final local = await SBMMLocalService.getBotMix(
      botCount: botCount,
      slotId: slotId,
    );
    if (kDebugMode) {
      debugPrint(
        '🎯 SBMM[slot $slotId]: ${local.botLevels} / ${local.botBehaviors} '
        '(cursor: ${local.cursor.toStringAsFixed(2)}, MMR: ${local.mmr}, '
        'archetype: ${local.archetype.name})',
      );
    }
    return SBMMBotMixResult(
      botLevels: local.botLevels,
      botBehaviors: local.botBehaviors,
      cursor: local.cursor,
      mmr: local.mmr,
      archetype: local.archetype,
    );
  }

  /// Enregistre le résultat d'une partie (ajuste le cursor local du slot).
  static Future<void> recordGame({
    required String gameId,
    required int slotId,
    required int rank,
    required int score,
    required List<SBMMBotResult> botResults,
    required int totalPlayers,
    required bool dutchCalled,
    required bool dutchWon,
  }) async {
    await SBMMLocalService.recordGame(
      slotId: slotId,
      rank: rank,
      totalPlayers: totalPlayers,
      dutchCalled: dutchCalled,
      dutchWon: dutchWon,
    );
  }
}

class SBMMBotMixResult {
  final List<String> botLevels;
  final List<String> botBehaviors;
  final double cursor;
  final int mmr;
  final PlayerArchetype archetype;

  const SBMMBotMixResult({
    required this.botLevels,
    required this.botBehaviors,
    required this.cursor,
    required this.mmr,
    required this.archetype,
  });
}

class SBMMBotResult {
  final String level;
  final int rank;
  final int score;
  final bool dutchCalled;
  final bool dutchWon;

  const SBMMBotResult({
    required this.level,
    required this.rank,
    required this.score,
    required this.dutchCalled,
    required this.dutchWon,
  });

  Map<String, dynamic> toJson() => {
        'level': level,
        'rank': rank,
        'score': score,
        'dutchCalled': dutchCalled,
        'dutchWon': dutchWon,
      };
}
