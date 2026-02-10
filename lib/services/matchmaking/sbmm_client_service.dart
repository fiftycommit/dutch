import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../multiplayer/client_id_service.dart';

/// Client pour le nouveau système SBMM serveur.
/// Remplace la génération locale de bots "miroirs" par un appel serveur
/// qui détermine le mix de BotSkillLevel optimal pour le joueur.
class SBMMClientService {
  static const String _baseUrl = 'https://dutch-game.me/api/sbmm';
  static const Duration _timeout = Duration(seconds: 5);

  /// Demande au serveur le mix de BotSkillLevel pour ce joueur.
  /// Retourne une liste de niveaux de bots (ex: ['bronze', 'silver', 'silver']).
  /// En cas d'erreur, retourne null (le caller doit fallback).
  static Future<SBMMBotMixResult?> getBotMix({required int botCount}) async {
    try {
      final playerId = await ClientIdService.ensureClientId();

      final response = await http.get(
        Uri.parse('$_baseUrl/bot-mix?playerId=$playerId&botCount=$botCount'),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botLevels = (data['botLevels'] as List).cast<String>();
        final cursor = (data['cursor'] as num).toDouble();
        final mmr = (data['mmr'] as num).toInt();

        if (kDebugMode) {
          debugPrint('🎯 SBMM bot-mix: $botLevels (cursor: ${cursor.toStringAsFixed(2)}, MMR: $mmr)');
        }

        return SBMMBotMixResult(
          botLevels: botLevels,
          cursor: cursor,
          mmr: mmr,
        );
      }

      if (kDebugMode) debugPrint('⚠️ SBMM bot-mix erreur: ${response.statusCode}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ SBMM bot-mix exception: $e');
      return null;
    }
  }

  /// Enregistre le résultat d'une partie SBMM sur le serveur.
  /// Fire-and-forget : ne bloque pas, ne crash pas.
  static Future<void> recordGame({
    required String gameId,
    required int rank,
    required int score,
    required List<SBMMBotResult> botResults,
    required int totalPlayers,
    required bool dutchCalled,
    required bool dutchWon,
  }) async {
    try {
      final playerId = await ClientIdService.ensureClientId();

      final body = {
        'playerId': playerId,
        'gameId': gameId,
        'rank': rank,
        'score': score,
        'botResults': botResults.map((b) => b.toJson()).toList(),
        'totalPlayers': totalPlayers,
        'dutchCalled': dutchCalled,
        'dutchWon': dutchWon,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/record-game'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (kDebugMode) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('✅ SBMM record-game: newMMR=${data['newMMR']}, newCursor=${data['newCursor']}');
        } else {
          debugPrint('⚠️ SBMM record-game erreur: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ SBMM record-game exception: $e');
    }
  }
}

/// Résultat de l'appel bot-mix
class SBMMBotMixResult {
  final List<String> botLevels;
  final double cursor;
  final int mmr;

  const SBMMBotMixResult({
    required this.botLevels,
    required this.cursor,
    required this.mmr,
  });
}

/// Résultat d'un bot individuel pour record-game
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
