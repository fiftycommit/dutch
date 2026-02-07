import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/bot_learning_data.dart';
import '../../models/player.dart';
import '../../models/game_settings.dart';
import '../learning/player_learning_service.dart';
import '../learning/bot_learning_service.dart';
import '../learning/bot_training_service.dart';
import '../learning/ghost_clone_service.dart';
import 'bot/bot_config.dart';
import '../multiplayer/client_id_service.dart';

/// Fabrique de bots — extrait de GameSetupScreen pour respecter SRP.
/// Gère la création des bots en mode SBMM, manuel, élite et mix.
class BotFactory {
  static final math.Random _nameRandom = math.Random();

  static final List<String> _botNames = [
    'Max', 'Yanis', 'Rohi', 'Millie', 'Kellinho', 'Kifa', 'Zoe', 'VR6',
    'Ruben', 'Lisa', 'Clara', 'Frizou', 'Tony', 'Leon', 'Elodie', '2T',
    'Guy2', 'Poppa', 'Messboal', 'Bersa', 'Juwa', 'Manboy', 'Bramsou', 'Lil Uzi'
  ];

  static final Set<String> _usedNames = {};

  static String getBotName(BotBehavior behavior, BotSkillLevel level) {
    if (_usedNames.length >= _botNames.length) {
      _usedNames.clear();
    }
    final available = _botNames.where((n) => !_usedNames.contains(n)).toList();
    final name = available[_nameRandom.nextInt(available.length)];
    _usedNames.add(name);
    return name;
  }

  static void resetUsedNames() => _usedNames.clear();

  // ═══════════════════════════════════════════════════════════════════════════
  // SBMM BOTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crée les bots en mode SBMM (vrai matchmaking adaptatif)
  ///
  /// Les bots sont des "miroirs" du joueur : mêmes paramètres avec petite
  /// variance aléatoire. Pas de seuils MMR, pas de multiplicateur de skill.
  static Future<List<Player>> createSBMMBots({
    required int numberOfBots,
    required int saveSlot,
    required bool isTournament,
  }) async {
    final botTrainingService = BotTrainingService();
    final ghostCloneService = GhostCloneService();

    // Récupérer le profil joueur (une seule fois)
    final profile = await PlayerLearningService().getProfile(slotId: saveSlot);

    // Infos pour le ghost clone
    final ghostPlayerId = await ClientIdService.ensureClientId();
    final ghostPlayerName = profile.profileId;

    // Vrai SBMM : copier les params du joueur avec petite variance par bot
    final botParamsList = BotConfig.generateMatchmakingBotParams(
      playerProfile: profile,
      botCount: numberOfBots,
      forceChallenge: isTournament,
    );

    // Ghost profile (chargé une seule fois si nécessaire)
    GhostProfile? ghostProfile;

    final players = <Player>[];
    final skillLevel = _mmrToSkillLevel(profile.mmr);

    for (int i = 0; i < numberOfBots; i++) {
      final baseParams = botParamsList[i];

      // Récupérer le training state pour ce type de bot
      final botKey = BotTrainingService.buildBotKey(
        behavior: BotBehavior.balanced,
        skillLevel: skillLevel,
      );
      final trainingState = await botTrainingService.getStateForBot(
        botKey,
        consumeTrainingGame: true,
      );

      // Charger le ghost profile si nécessaire (une seule fois)
      if (trainingState.ghostInfluence > 0 && ghostProfile == null) {
        ghostProfile = await ghostCloneService.getGhostProfile(
          slotId: saveSlot,
          playerId: ghostPlayerId,
          playerName: ghostPlayerName,
        );
      }

      // Appliquer le ghost blending sur les paramètres de base
      final aiParameters = _applyGhostBlending(
        baseParams: baseParams,
        ghostProfile: ghostProfile,
        trainingState: trainingState,
      );

      players.add(Player(
        id: 'bot_$i',
        name: getBotName(BotBehavior.balanced, skillLevel),
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: skillLevel,
        aiParameters: aiParameters,
        position: i + 1,
      ));
    }

    return players;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MANUAL BOTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crée les bots en mode manuel (difficulté choisie par l'utilisateur)
  /// Bronze/Silver/Gold : sélection par winrate moyen cible
  /// Platinum : meilleurs bots absolus de la catégorie
  static Future<List<Player>> createManualBots({
    required int numberOfBots,
    required Difficulty difficulty,
  }) async {
    if (numberOfBots <= 0) return [];

    // Platinum : logique élite (meilleurs absolus)
    if (difficulty == Difficulty.platinum) {
      return _createEliteBots(numberOfBots, difficulty);
    }

    // Mix : logique spéciale (mélange de niveaux)
    if (difficulty == Difficulty.mix) {
      return _createMixBots(numberOfBots);
    }

    // Bronze / Silver / Gold : sélection par tranche de winrate
    return _createWinrateBots(numberOfBots, difficulty);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL BOT CREATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Winrate minimum par difficulté (pas de max, on prend les plus proches du min)
  static double _winrateMin(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:   return 0.0;  // Bronze : tous les bots, triés du plus faible
      case Difficulty.medium: return 0.50; // Argent : minimum 50%
      case Difficulty.hard:   return 0.70; // Or : minimum 70%
      default:                return 0.0;
    }
  }

  /// Sélectionne les bots dont le winrate moyen tombe dans la tranche cible
  static Future<List<Player>> _createWinrateBots(int numberOfBots, Difficulty difficulty) async {
    final botLearningService = BotLearningService();
    final allBots = await botLearningService.fetchTopBots(limit: 50);
    final targetSkill = difficultyToSkillLevel(difficulty);

    double avgWinrate(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;
    final minWr = _winrateMin(difficulty);
    final isBronze = difficulty == Difficulty.easy;

    // Filtrer par winrate minimum strict
    var candidates = allBots.where((b) => avgWinrate(b) >= minWr).toList();

    // Bronze : trier du plus faible au plus fort (on veut les plus nuls)
    // Argent/Or : trier du plus fort au plus faible (on veut les meilleurs au-dessus du min)
    if (isBronze) {
      candidates.sort((a, b) => avgWinrate(a).compareTo(avgWinrate(b)));
    } else {
      candidates.sort((a, b) => avgWinrate(b).compareTo(avgWinrate(a)));
    }

    if (kDebugMode) debugPrint('🎯 Min winrate: ${(minWr * 100).toStringAsFixed(0)}% → ${candidates.length} bots trouvés');
    for (final bot in candidates) {
      if (kDebugMode) debugPrint('  🤖 ${bot.botId} | WR: ${(avgWinrate(bot) * 100).toStringAsFixed(0)}%');
    }

    final isGold = difficulty == Difficulty.hard;
    final players = <Player>[];

    if (isGold) {
      // Or : 2/3 #1 + 1/3 #2 (duplication des meilleurs)
      final bestBot = candidates.isNotEmpty ? candidates.first : null;
      final secondBot = candidates.length >= 2 ? candidates[1] : bestBot;

      if (bestBot != null) {
        if (kDebugMode) debugPrint('⭐ #1: ${bestBot.botId} | WR: ${(avgWinrate(bestBot) * 100).toStringAsFixed(0)}%');
      }
      if (secondBot != null && secondBot != bestBot) {
        if (kDebugMode) debugPrint('⭐ #2: ${secondBot.botId} | WR: ${(avgWinrate(secondBot) * 100).toStringAsFixed(0)}%');
      }

      final secondBotCount = (numberOfBots / 3).ceil();
      final firstBotCount = numberOfBots - secondBotCount;

      for (int i = 0; i < numberOfBots; i++) {
        final source = i < firstBotCount ? bestBot : secondBot;
        players.add(_playerFromBotProfile(source, i, targetSkill));
      }
    } else {
      // Bronze / Argent : bots tous différents
      for (int i = 0; i < numberOfBots; i++) {
        final source = i < candidates.length ? candidates[i] : null;
        if (source != null) {
          if (kDebugMode) debugPrint('⭐ Bot $i: ${source.botId} | WR: ${(avgWinrate(source) * 100).toStringAsFixed(0)}%');
        }
        players.add(_playerFromBotProfile(source, i, targetSkill));
      }
    }

    return players;
  }

  /// Mode Mix : un bot de chaque tranche de winrate
  static Future<List<Player>> _createMixBots(int numberOfBots) async {
    final botLearningService = BotLearningService();
    final allBots = await botLearningService.fetchTopBots(limit: 50);

    double avgWinrate(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final mixTargets = [0.25, 0.50, 0.75];
    final mixSkills = [BotSkillLevel.bronze, BotSkillLevel.silver, BotSkillLevel.gold];
    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final target = mixTargets[i % mixTargets.length];
      final skill = mixSkills[i % mixSkills.length];

      // Trouver le bot le plus proche du winrate cible
      final sorted = List<BotProfile>.from(allBots)
        ..sort((a, b) =>
            (avgWinrate(a) - target).abs().compareTo((avgWinrate(b) - target).abs()));

      final source = sorted.isNotEmpty ? sorted.first : null;
      players.add(_playerFromBotProfile(source, i, skill));
    }

    return players;
  }

  /// Crée les bots élite pour Silver/Gold/Platinum :
  /// 3/4 = meilleur bot de la catégorie, 1/4 = second meilleur
  static Future<List<Player>> _createEliteBots(int numberOfBots, Difficulty difficulty) async {
    final botLearningService = BotLearningService();
    final targetSkill = difficultyToSkillLevel(difficulty);

    final allBots = await botLearningService.fetchTopBots(limit: 20);

    double eliteScore(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final targetSkillName = targetSkill.toString().split('.').last;
    final filteredBots = allBots.where((b) => b.skillLevel == targetSkillName).toList();

    for (final bot in allBots) {
      final marker = bot.skillLevel == targetSkillName ? '→' : ' ';
      if (kDebugMode) debugPrint('$marker 🤖 ${bot.botId} | MMR: ${bot.mmr} | Vs humain: ${(bot.avgPBeatHuman * 100).toStringAsFixed(0)}% | WinRate: ${(bot.winRate * 100).toStringAsFixed(0)}% | Score: ${(eliteScore(bot) * 100).toStringAsFixed(0)}%');
    }

    filteredBots.sort((a, b) => eliteScore(b).compareTo(eliteScore(a)));

    final bestBot = filteredBots.isNotEmpty ? filteredBots.first : (allBots.isNotEmpty ? allBots.first : null);
    final secondBot = filteredBots.length >= 2 ? filteredBots[1] : bestBot;

    if (bestBot != null) {
      if (kDebugMode) debugPrint('⭐ #1: ${bestBot.botId} | MMR: ${bestBot.mmr} | Score: ${(eliteScore(bestBot) * 100).toStringAsFixed(0)}%');
    }
    if (secondBot != null && secondBot != bestBot) {
      if (kDebugMode) debugPrint('⭐ #2: ${secondBot.botId} | MMR: ${secondBot.mmr} | Score: ${(eliteScore(secondBot) * 100).toStringAsFixed(0)}%');
    }

    final players = <Player>[];
    // 2/3 avec le #1, 1/3 avec le #2
    final secondBotCount = (numberOfBots / 3).ceil();
    final firstBotCount = numberOfBots - secondBotCount;

    for (int i = 0; i < numberOfBots; i++) {
      final source = i < firstBotCount ? bestBot : secondBot;
      players.add(_playerFromBotProfile(source, i, targetSkill));
    }

    return players;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Player _playerFromBotProfile(BotProfile? source, int index, BotSkillLevel targetSkill) {
    if (source != null) {
      final behavior = _parseBehavior(source.behavior);
      final aiParams = _extractAiParams(source.learnedParameters);
      aiParams['serverMMR'] = source.mmr.toDouble();
      aiParams['serverWinRateVsHuman'] = source.avgPBeatHuman;

      return Player(
        id: 'bot_$index',
        name: getBotName(behavior, targetSkill),
        isHuman: false,
        botBehavior: behavior,
        botSkillLevel: targetSkill,
        aiParameters: aiParams.isNotEmpty ? aiParams : null,
        position: index + 1,
      );
    }
    return Player(
      id: 'bot_$index',
      name: getBotName(BotBehavior.balanced, targetSkill),
      isHuman: false,
      botBehavior: BotBehavior.balanced,
      botSkillLevel: targetSkill,
      position: index + 1,
    );
  }

  static BotBehavior _parseBehavior(String? raw) {
    switch (raw) {
      case 'fast':
        return BotBehavior.fast;
      case 'aggressive':
        return BotBehavior.aggressive;
      case 'balanced':
      default:
        return BotBehavior.balanced;
    }
  }

  static Map<String, double> _extractAiParams(Map<String, dynamic> raw) {
    final params = <String, double>{};
    raw.forEach((key, value) {
      if (value is num) {
        params[key] = value.toDouble();
      }
    });
    return params;
  }

  /// Applique le ghost blending sur les paramètres de base
  static Map<String, double> _applyGhostBlending({
    required Map<String, double> baseParams,
    GhostProfile? ghostProfile,
    required BotTrainingState trainingState,
  }) {
    final ghostParams = ghostProfile?.params ?? const <String, double>{};
    final ghostInfluence = trainingState.ghostInfluence;

    double blend(String key, double baseValue) {
      final ghostValue = ghostParams[key];
      if (ghostValue == null || ghostInfluence <= 0) return baseValue;
      return baseValue + (ghostValue - baseValue) * ghostInfluence;
    }

    // Copier les paramètres de base et appliquer le blending
    final result = Map<String, double>.from(baseParams);

    // Appliquer le ghost blending sur les paramètres clés
    result['aggressiveness'] = blend('aggressiveness', result['aggressiveness'] ?? 0.5);
    result['caution'] = blend('caution', result['caution'] ?? 0.5);
    result['riskTolerance'] = blend('riskTolerance', result['riskTolerance'] ?? 0.5);
    result['powerUsageRate'] = blend('powerUsageRate', result['powerUsageRate'] ?? 0.5);
    result['decisionSpeed'] = blend('decisionSpeed', result['decisionSpeed'] ?? 2000.0).clamp(500.0, 10000.0);
    result['dutchThreshold'] = blend('dutchThreshold', result['dutchThreshold'] ?? 15.0).clamp(5.0, 30.0);

    // Ajouter les paramètres de training
    result['ghostInfluence'] = ghostInfluence;
    result['ghostDutchThreshold'] = ghostParams['dutchThreshold'] ?? result['dutchThreshold']!;
    result['rankPenalty'] = trainingState.rankPenalty;

    return result;
  }

  /// Convertit un MMR en BotSkillLevel (pour affichage/nom uniquement)
  static BotSkillLevel _mmrToSkillLevel(int mmr) {
    if (mmr >= 900) return BotSkillLevel.platinum;
    if (mmr >= 600) return BotSkillLevel.gold;
    if (mmr >= 300) return BotSkillLevel.silver;
    return BotSkillLevel.bronze;
  }

  static BotSkillLevel difficultyToSkillLevel(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:
        return BotSkillLevel.bronze;
      case Difficulty.medium:
        return BotSkillLevel.silver;
      case Difficulty.hard:
        return BotSkillLevel.gold;
      case Difficulty.platinum:
        return BotSkillLevel.platinum;
      case Difficulty.mix:
        return BotSkillLevel.silver;
    }
  }
}
