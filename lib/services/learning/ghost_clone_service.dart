import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/player_learning_data.dart';
import '../network/secure_api_headers.dart';
import '../network/network_probe_service.dart';
import 'player_learning_service.dart';

class GhostProfile {
  final String cloneId;
  final Map<String, double> params;
  final bool isOffline; // Indique si c'est un profil généré localement

  GhostProfile({
    required this.cloneId,
    required this.params,
    this.isOffline = false,
  });
}

class GhostCloneService {
  static const String _serverUrl = 'https://dutch-game.me/api/bot-learning';
  static const String _cloneKeyPrefix = 'ghost_clone_id_slot_';
  static const String _offlineClonePrefix = 'offline_ghost_slot_';
  static const Duration _apiTimeout = Duration(seconds: 2);
  static const Duration _networkProbeTimeout = Duration(milliseconds: 700);

  Future<bool> _canReachBackendQuickly() {
    return NetworkProbeService.canReachBackend(timeout: _networkProbeTimeout);
  }

  /// Récupère ou crée un profil ghost pour le joueur
  ///
  /// Tente d'abord de récupérer depuis le serveur.
  /// En cas d'échec (offline, timeout, erreur), génère un profil local.
  Future<GhostProfile?> getGhostProfile({
    required int slotId,
    required String playerId,
    required String playerName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingId = prefs.getString('$_cloneKeyPrefix$slotId');
    final isOnline = await _canReachBackendQuickly();

    // Essayer de récupérer un clone existant depuis le serveur
    if (existingId != null && existingId.isNotEmpty) {
      if (isOnline) {
        final fetched = await _fetchClone(existingId);
        if (fetched != null) return fetched;
      }
      // Si le fetch échoue, basculer directement en offline pour éviter le double délai.
      return _generateOfflineProfile(slotId: slotId, playerId: playerId);
    }

    // Essayer de créer un nouveau clone sur le serveur
    if (isOnline) {
      final created = await _createClone(
        slotId: slotId,
        playerId: playerId,
        playerName: playerName,
      );
      if (created != null) {
        await prefs.setString('$_cloneKeyPrefix$slotId', created.cloneId);
        return created;
      }
    }

    // FALLBACK OFFLINE : générer un profil local basé sur l'historique du joueur
    return _generateOfflineProfile(slotId: slotId, playerId: playerId);
  }

  /// Génère un profil ghost local en analysant l'historique du joueur
  Future<GhostProfile?> _generateOfflineProfile({
    required int slotId,
    required String playerId,
  }) async {
    try {
      final history = await PlayerLearningService().getHistory(slotId: slotId);
      final profile = await PlayerLearningService().getProfile(slotId: slotId);

      // Générer un ID unique pour ce ghost offline
      final offlineId =
          '$_offlineClonePrefix${playerId}_${DateTime.now().millisecondsSinceEpoch}';

      if (history.isEmpty) {
        // Pas d'historique : utiliser les paramètres par défaut du profil
        return _profileFromPlayerParams(offlineId, profile.learnedParameters);
      }

      // Analyser l'historique pour extraire des patterns
      final patterns = _analyzeLocalHistory(history);

      return GhostProfile(
        cloneId: offlineId,
        params: patterns,
        isOffline: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Analyse l'historique local pour extraire des patterns de jeu
  Map<String, double> _analyzeLocalHistory(List<PlayerGameRecord> history) {
    if (history.isEmpty) {
      return _defaultGhostParams();
    }

    final recentGames = history.take(20).toList();

    // Calculer les statistiques à partir de l'historique
    double totalAggressiveness = 0;
    double totalRiskTaking = 0;
    double totalDecisionTime = 0;
    int dutchCount = 0;
    int dutchWins = 0;
    double totalDutchScore = 0;
    int actionCount = 0;
    int powerUseCount = 0;

    for (final game in recentGames) {
      if (game.calledDutch) {
        dutchCount++;
        totalDutchScore += game.finalScore;
        if (game.wonDutch) dutchWins++;
      }

      for (final action in game.actions) {
        actionCount++;

        // Analyser les actions risquées
        if (action.isRiskyAction == true) {
          totalRiskTaking += 1;
        }

        // Temps de décision
        if (action.decisionTimeMs != null) {
          totalDecisionTime += action.decisionTimeMs!;
        }

        // Utilisation des pouvoirs
        if (action.actionType == 'power' || action.powerType != null) {
          powerUseCount++;
        }

        // Agressivité basée sur le ciblage
        if (action.targetStrategy == 'leader') {
          totalAggressiveness += 0.8;
        } else if (action.targetStrategy == 'weak') {
          totalAggressiveness += 0.3;
        } else {
          totalAggressiveness += 0.5;
        }
      }
    }

    // Normaliser les valeurs
    final gameCount = recentGames.length.toDouble();
    final avgActionsPerGame = actionCount > 0 ? actionCount / gameCount : 10;

    double aggressiveness = actionCount > 0
        ? (totalAggressiveness / actionCount).clamp(0.0, 1.0)
        : 0.5;

    double riskTolerance =
        actionCount > 0 ? (totalRiskTaking / actionCount).clamp(0.0, 1.0) : 0.5;

    double powerUsageRate = avgActionsPerGame > 0
        ? (powerUseCount / (gameCount * avgActionsPerGame * 0.3))
            .clamp(0.0, 1.0)
        : 0.5;

    double avgDecisionTime = actionCount > 0
        ? (totalDecisionTime / actionCount).clamp(500.0, 10000.0)
        : 2000.0;

    double dutchThreshold =
        dutchCount > 0 ? (totalDutchScore / dutchCount).clamp(5.0, 30.0) : 15.0;

    // Ajuster la prudence inversement à l'agressivité
    double caution = (1.0 - aggressiveness).clamp(0.0, 1.0);

    // Bonus/malus basé sur le taux de victoire Dutch
    if (dutchCount >= 3) {
      final dutchWinRate = dutchWins / dutchCount;
      if (dutchWinRate > 0.6) {
        // Bon joueur Dutch : plus agressif sur les Dutch
        dutchThreshold = (dutchThreshold - 2).clamp(5.0, 30.0);
      } else if (dutchWinRate < 0.3) {
        // Mauvais timing Dutch : plus conservateur
        dutchThreshold = (dutchThreshold + 3).clamp(5.0, 30.0);
      }
    }

    return {
      'aggressiveness': aggressiveness,
      'caution': caution,
      'riskTolerance': riskTolerance,
      'powerUsageRate': powerUsageRate,
      'decisionSpeed': avgDecisionTime,
      'dutchThreshold': dutchThreshold,
    };
  }

  /// Crée un profil ghost à partir des paramètres appris du joueur
  GhostProfile _profileFromPlayerParams(
    String cloneId,
    Map<String, dynamic> params,
  ) {
    double numValue(String key, double fallback) {
      final v = params[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    return GhostProfile(
      cloneId: cloneId,
      params: {
        'aggressiveness': numValue('aggressiveness', 0.5).clamp(0.0, 1.0),
        'caution': numValue('caution', 0.5).clamp(0.0, 1.0),
        'riskTolerance': numValue('riskTolerance', 0.5).clamp(0.0, 1.0),
        'powerUsageRate': numValue('powerUsageRate', 0.5).clamp(0.0, 1.0),
        'decisionSpeed':
            numValue('decisionSpeed', 2000.0).clamp(500.0, 10000.0),
        'dutchThreshold': numValue('dutchThreshold', 15.0).clamp(5.0, 30.0),
      },
      isOffline: true,
    );
  }

  /// Paramètres par défaut pour un ghost sans données
  Map<String, double> _defaultGhostParams() {
    return {
      'aggressiveness': 0.5,
      'caution': 0.5,
      'riskTolerance': 0.5,
      'powerUsageRate': 0.5,
      'decisionSpeed': 2000.0,
      'dutchThreshold': 15.0,
    };
  }

  Future<GhostProfile?> _fetchClone(String cloneId) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return null;

      final uri = Uri.parse('$_serverUrl/clone/$cloneId');
      final response = await http
          .get(
            uri,
            headers: await SecureApiHeaders.authorizedJson(),
          )
          .timeout(_apiTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      return _profileFromJson(json);
    } catch (_) {
      // Timeout, erreur réseau, ou autre : retourne null pour déclencher le fallback
      return null;
    }
  }

  Future<GhostProfile?> _createClone({
    required int slotId,
    required String playerId,
    required String playerName,
  }) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return null;

      final history = await PlayerLearningService().getHistory(slotId: slotId);
      if (history.isEmpty) return null;

      final games =
          history.take(30).map(_mapGameRecord).toList(growable: false);

      final body = jsonEncode({
        'playerId': playerId,
        'playerName': playerName,
        'games': games,
      });

      final uri = Uri.parse('$_serverUrl/clone-player');
      final response = await http
          .post(
            uri,
            headers: await SecureApiHeaders.authorizedJson(),
            body: body,
          )
          .timeout(_apiTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      return _profileFromJson(json);
    } catch (_) {
      // Timeout, erreur réseau, ou autre : retourne null pour déclencher le fallback
      return null;
    }
  }

  GhostProfile? _profileFromJson(Map<String, dynamic> json) {
    final cloneId = json['clonedBotId']?.toString();
    final pattern = json['pattern'];
    if (cloneId == null || pattern is! Map<String, dynamic>) return null;

    double numValue(String key, double fallback) {
      final v = pattern[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    double clamp01(double v) => v.clamp(0.0, 1.0);

    double aggressiveness = clamp01(numValue('aggressivenessScore', 0.5));
    double riskTolerance = clamp01(numValue('riskTakingScore', 0.5));
    double powerUsage = clamp01(numValue('powerUsageFrequency', 0.5));
    double decisionSpeed =
        numValue('avgDecisionTime', 2000.0).clamp(500.0, 10000.0);
    double dutchThreshold =
        numValue('dutchThresholdPattern', 15.0).clamp(5.0, 30.0);

    double caution = clamp01(1.0 - aggressiveness);
    final playStyle = pattern['playStyle']?.toString() ?? 'balanced';
    if (playStyle == 'defensive') {
      caution = caution.clamp(0.6, 1.0);
      aggressiveness = aggressiveness.clamp(0.0, 0.5);
    } else if (playStyle == 'aggressive') {
      aggressiveness = aggressiveness.clamp(0.6, 1.0);
      caution = caution.clamp(0.0, 0.4);
    } else if (playStyle == 'opportunistic') {
      riskTolerance = riskTolerance.clamp(0.6, 1.0);
    }

    return GhostProfile(
      cloneId: cloneId,
      params: {
        'aggressiveness': aggressiveness,
        'caution': caution,
        'riskTolerance': riskTolerance,
        'powerUsageRate': powerUsage,
        'decisionSpeed': decisionSpeed,
        'dutchThreshold': dutchThreshold,
      },
    );
  }

  Map<String, dynamic> _mapGameRecord(PlayerGameRecord record) {
    return {
      'calledDutch': record.calledDutch,
      'scoreAtDutch': record.calledDutch ? record.finalScore : 0,
      'actions': record.actions.map(_mapAction).toList(),
    };
  }

  Map<String, dynamic> _mapAction(PlayerAction action) {
    String actionType = action.actionType;
    if (actionType == 'draw') {
      final source = action.actionDetails['source'];
      actionType = source == 'discard' ? 'draw_from_discard' : 'draw_from_deck';
    } else if (actionType == 'replace') {
      actionType = 'replace_card';
    } else if (actionType == 'power') {
      actionType = 'use_power';
    } else if (actionType == 'power_skip') {
      actionType = 'skip_power';
    }

    final gameState = Map<String, dynamic>.from(action.gameState);
    if (!gameState.containsKey('myScore')) {
      final score = gameState['humanEstimatedScore'] ?? gameState['humanScore'];
      if (score != null) {
        gameState['myScore'] = score;
      }
    }

    return {
      'actionType': actionType,
      'actionDetails': action.actionDetails,
      'decisionTime': action.decisionTimeMs,
      'gameState': gameState,
    };
  }
}
