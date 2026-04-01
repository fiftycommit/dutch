import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/bot_learning_data.dart';
import '../../models/player.dart';
import '../../models/player_learning_data.dart';
import '../../models/game_settings.dart';
import '../learning/player_learning_service.dart';
import '../learning/bot_learning_service.dart';
import '../network/network_probe_service.dart';
import 'bot/bot_config.dart';
import '../matchmaking/sbmm_client_service.dart';

/// Fabrique de bots — extrait de GameSetupScreen pour respecter SRP.
/// Gère la création des bots en mode SBMM, manuel, élite et mix.
class BotFactory {
  static final math.Random _nameRandom = math.Random();
  static const Duration _networkProbeTimeout = Duration(milliseconds: 700);

  static final List<String> _botNames = [
    'Max',
    'Yanis',
    'Rohino',
    'Millie',
    'Kellinho',
    'Ikfa',
    'Nessa',
    'VR6',
    'Kanan Stark',
    'Mucong',
    'Irfat',
    'Frizou',
    'Tony',
    'Leon',
    '2004 Boosté',
    '2T',
    'Guy2',
    'Avon Barksdale',
    'Messball',
    'Balkhis',
    'Marlo Stanfield',
    'Manboy',
    'Bramsou',
    'Keyser Söze'
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

  static Difficulty _normalizeStrongDifficulty(Difficulty difficulty) {
    return difficulty == Difficulty.hard ? Difficulty.platinum : difficulty;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SBMM BOTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crée les bots en mode SBMM (matchmaking adaptatif serveur)
  ///
  /// Appelle le serveur pour obtenir le mix optimal de BotSkillLevel
  /// basé sur le MMR et l'historique du joueur. Fallback local si serveur
  /// indisponible.
  static Future<List<Player>> createSBMMBots({
    required int numberOfBots,
    required int saveSlot,
    required bool isTournament,
  }) async {
    final isOnline = await _canReachBackendQuickly();
    final sbmmResult = isOnline
        ? await SBMMClientService.getBotMix(botCount: numberOfBots)
        : null;

    if (sbmmResult != null) {
      // Stocker les niveaux pour les passer au serveur via les settings
      _lastSBMMBotLevels = sbmmResult.botLevels;

      return _buildBotsFromLevels(sbmmResult.botLevels, numberOfBots);
    }

    // Fallback : utiliser le MMR local pour déterminer le niveau
    if (kDebugMode) {
      debugPrint(isOnline
          ? '⚠️ SBMM fallback local (bot-mix indisponible)'
          : '⚠️ SBMM offline détecté, fallback local immédiat');
    }
    final profile = await PlayerLearningService().getProfile(slotId: saveSlot);
    final skillLevel = _mmrToSkillLevel(profile.mmr);
    _lastSBMMBotLevels = List.generate(numberOfBots, (_) => skillLevel.name);

    return List.generate(
        numberOfBots,
        (i) => Player(
              id: 'bot_$i',
              name: getBotName(BotBehavior.balanced, skillLevel),
              isHuman: false,
              botBehavior: BotBehavior.balanced,
              botSkillLevel: skillLevel,
              position: i + 1,
            ));
  }

  /// Derniers niveaux SBMM retournés par le serveur (pour les passer dans les settings)
  static List<String>? _lastSBMMBotLevels;
  static List<String>? get lastSBMMBotLevels => _lastSBMMBotLevels;

  /// Convertit une liste de noms de niveaux en Players
  static List<Player> _buildBotsFromLevels(List<String> levels, int count) {
    return List.generate(count, (i) {
      final level = i < levels.length
          ? _parseSkillLevel(levels[i])
          : BotSkillLevel.silver;
      return Player(
        id: 'bot_$i',
        name: getBotName(BotBehavior.balanced, level),
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: level,
        position: i + 1,
      );
    });
  }

  static BotSkillLevel _parseSkillLevel(String raw) {
    switch (raw) {
      case 'bronze':
        return BotSkillLevel.bronze;
      case 'gold':
      case 'platinum':
        return BotSkillLevel.platinum;
      case 'silver':
      default:
        return BotSkillLevel.silver;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MANUAL BOTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crée les bots en mode manuel (difficulté choisie par l'utilisateur)
  /// Bronze/Argent : bots par défaut (pas de sélection serveur)
  /// Or/Platine : sélection serveur par winrate / élite
  static Future<List<Player>> createManualBots({
    required int numberOfBots,
    required Difficulty difficulty,
    int? saveSlot,
  }) async {
    if (numberOfBots <= 0) return [];
    final normalizedDifficulty = _normalizeStrongDifficulty(difficulty);

    // Mix : logique spéciale (mélange de niveaux)
    if (normalizedDifficulty == Difficulty.mix) {
      return _createMixBots(numberOfBots);
    }

    // Niveau fort unique : logique élite (anciens Or/Platine fusionnés)
    if (normalizedDifficulty == Difficulty.platinum) {
      return _createEliteBots(
        numberOfBots,
        normalizedDifficulty,
        saveSlot: saveSlot,
      );
    }

    // Bronze / Argent : bots par défaut, pas de sélection serveur
    final targetSkill = difficultyToSkillLevel(normalizedDifficulty);
    return List.generate(
      numberOfBots,
      (i) => Player(
        id: 'bot_$i',
        name: getBotName(BotBehavior.balanced, targetSkill),
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: targetSkill,
        position: i + 1,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL BOT CREATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mode Mix : un bot de chaque tranche de winrate
  static Future<List<Player>> _createMixBots(int numberOfBots) async {
    final botLearningService = BotLearningService();
    final allBots = await _fetchTopBotsOfflineFirst(
      botLearningService: botLearningService,
      limit: 50,
    );

    double avgWinrate(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final mixTargets = [0.25, 0.50, 0.75];
    final mixSkills = [
      BotSkillLevel.bronze,
      BotSkillLevel.silver,
      BotSkillLevel.platinum,
    ];
    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final target = mixTargets[i % mixTargets.length];
      final skill = mixSkills[i % mixSkills.length];

      // Trouver le bot le plus proche du winrate cible
      final sorted = List<BotProfile>.from(allBots)
        ..sort((a, b) => (avgWinrate(a) - target)
            .abs()
            .compareTo((avgWinrate(b) - target).abs()));

      final source = sorted.isNotEmpty ? sorted.first : null;
      players.add(_playerFromBotProfile(source, i, skill));
    }

    return players;
  }

  /// Crée les bots élite pour Silver/Gold/Platinum :
  /// 3/4 = meilleur bot de la catégorie, 1/4 = second meilleur
  static Future<List<Player>> _createEliteBots(
      int numberOfBots, Difficulty difficulty,
      {int? saveSlot}) async {
    final botLearningService = BotLearningService();
    final targetSkill = difficultyToSkillLevel(difficulty);

    final allBots = await _fetchTopBotsOfflineFirst(
      botLearningService: botLearningService,
      limit: 20,
    );

    double eliteScore(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final targetSkillName = targetSkill.toString().split('.').last;
    final filteredBots =
        allBots.where((b) => b.skillLevel == targetSkillName).toList();

    for (final bot in allBots) {
      final marker = bot.skillLevel == targetSkillName ? '→' : ' ';
      if (kDebugMode) {
        debugPrint(
            '$marker 🤖 ${bot.botId} | MMR: ${bot.mmr} | Vs humain: ${(bot.avgPBeatHuman * 100).toStringAsFixed(0)}% | WinRate: ${(bot.winRate * 100).toStringAsFixed(0)}% | Score: ${(eliteScore(bot) * 100).toStringAsFixed(0)}%');
      }
    }

    filteredBots.sort((a, b) => eliteScore(b).compareTo(eliteScore(a)));

    final bestBot = filteredBots.isNotEmpty
        ? filteredBots.first
        : (allBots.isNotEmpty ? allBots.first : null);
    final secondBot = filteredBots.length >= 2 ? filteredBots[1] : bestBot;

    if (bestBot != null) {
      if (kDebugMode) {
        debugPrint(
            '⭐ #1: ${bestBot.botId} | MMR: ${bestBot.mmr} | Score: ${(eliteScore(bestBot) * 100).toStringAsFixed(0)}%');
      }
    }
    if (secondBot != null && secondBot != bestBot) {
      if (kDebugMode) {
        debugPrint(
            '⭐ #2: ${secondBot.botId} | MMR: ${secondBot.mmr} | Score: ${(eliteScore(secondBot) * 100).toStringAsFixed(0)}%');
      }
    }

    final players = <Player>[];
    // 2/3 avec le #1, 1/3 avec le #2
    final secondBotCount = (numberOfBots / 3).ceil();
    final firstBotCount = numberOfBots - secondBotCount;

    for (int i = 0; i < numberOfBots; i++) {
      final source = i < firstBotCount ? bestBot : secondBot;
      players.add(_playerFromBotProfile(source, i, targetSkill));
    }

    return _validateAndFallback(
      serverBots: players,
      numberOfBots: numberOfBots,
      difficulty: difficulty,
      saveSlot: saveSlot,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATION & FALLBACK (Gold/Platinum uniquement)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vérifie que les bots serveur sont assez forts pour le joueur.
  /// Si non, retry avec filtres plus larges, puis fallback SBMM boosté.
  static Future<List<Player>> _validateAndFallback({
    required List<Player> serverBots,
    required int numberOfBots,
    required Difficulty difficulty,
    required int? saveSlot,
  }) async {
    final normalizedDifficulty = _normalizeStrongDifficulty(difficulty);
    // Validation uniquement pour Gold/Platinum avec saveSlot connu
    if (saveSlot == null) return serverBots;
    if (normalizedDifficulty != Difficulty.platinum) {
      return serverBots;
    }

    final profile = await PlayerLearningService().getProfile(slotId: saveSlot);
    final playerMMR = profile.mmr;

    final isGold = normalizedDifficulty == Difficulty.hard;
    final minMMR = isGold ? playerMMR - 100 : playerMMR;
    final minPBeatHuman = isGold ? 0.45 : 0.55;

    // Vérifier si les bots actuels passent la validation
    if (_botsPassValidation(
        bots: serverBots, minMMR: minMMR, minPBeatHuman: minPBeatHuman)) {
      if (kDebugMode) {
        debugPrint(
            '✅ Bots serveur validés pour $difficulty (playerMMR: $playerMMR)');
      }
      return serverBots;
    }

    if (kDebugMode) {
      debugPrint(
          '⚠️ Bots serveur trop faibles pour le joueur (MMR: $playerMMR). Retry avec filtres plus larges...');
    }

    // Retry avec filtres plus larges
    final retryBots = await _retryWithBroaderFilters(
      numberOfBots: numberOfBots,
      difficulty: normalizedDifficulty,
      minMMR: minMMR,
      minPBeatHuman: minPBeatHuman,
    );

    if (retryBots != null) {
      if (kDebugMode) debugPrint('✅ Retry a trouvé des bots assez forts');
      return retryBots;
    }

    if (kDebugMode) {
      debugPrint('⚠️ Aucun bot serveur assez fort. Fallback SBMM boosté');
    }
    return _createBoostedSBMMBots(
      numberOfBots: numberOfBots,
      difficulty: normalizedDifficulty,
      playerProfile: profile,
    );
  }

  /// Vérifie que au moins la moitié des bots passent les critères de force.
  static bool _botsPassValidation({
    required List<Player> bots,
    required int minMMR,
    required double minPBeatHuman,
  }) {
    if (bots.isEmpty) return false;

    int strongCount = 0;
    for (final bot in bots) {
      final params = bot.aiParameters;
      if (params == null) continue;

      final botMMR = (params['serverMMR'] ?? 0).toInt();
      final botPBeatHuman = params['serverWinRateVsHuman'] ?? 0.0;

      if (botMMR >= minMMR && botPBeatHuman >= minPBeatHuman) {
        strongCount++;
      }
    }

    return strongCount >= (bots.length / 2).ceil();
  }

  /// Retry en fetchant plus de bots sans filtre de skillLevel.
  static Future<List<Player>?> _retryWithBroaderFilters({
    required int numberOfBots,
    required Difficulty difficulty,
    required int minMMR,
    required double minPBeatHuman,
  }) async {
    try {
      final allBots = await _fetchTopBotsOfflineFirst(
        botLearningService: BotLearningService(),
        limit: 100,
      );

      double eliteScore(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

      final strongBots = allBots
          .where((b) => b.mmr >= minMMR && b.avgPBeatHuman >= minPBeatHuman)
          .toList();

      if (strongBots.length < 2) return null;

      strongBots.sort((a, b) => eliteScore(b).compareTo(eliteScore(a)));

      final targetSkill = difficultyToSkillLevel(difficulty);
      final bestBot = strongBots.first;
      final secondBot = strongBots.length >= 2 ? strongBots[1] : bestBot;

      final players = <Player>[];
      final secondBotCount = (numberOfBots / 3).ceil();
      final firstBotCount = numberOfBots - secondBotCount;

      for (int i = 0; i < numberOfBots; i++) {
        final source = i < firstBotCount ? bestBot : secondBot;
        players.add(_playerFromBotProfile(source, i, targetSkill));
      }

      // Valider le résultat du retry
      final valid = _botsPassValidation(
          bots: players, minMMR: minMMR, minPBeatHuman: minPBeatHuman);
      return valid ? players : null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Retry broader fetch failed: $e');
      return null;
    }
  }

  /// Crée des bots SBMM boostés : profil joueur avec paramètres améliorés.
  /// Ces bots sont strictement plus forts que le joueur.
  static List<Player> _createBoostedSBMMBots({
    required int numberOfBots,
    required Difficulty difficulty,
    required PlayerProfile playerProfile,
  }) {
    final normalizedDifficulty = _normalizeStrongDifficulty(difficulty);
    final isGold = normalizedDifficulty == Difficulty.hard;
    final targetSkill = difficultyToSkillLevel(normalizedDifficulty);

    final baseParamsList = BotConfig.generateMatchmakingBotParams(
      playerProfile: playerProfile,
      botCount: numberOfBots,
      forceChallenge: true,
    );

    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final params = baseParamsList[i];

      // Mémoire : Gold → ~0.90, Platinum → 0.99 (quasi parfait)
      params['memoryAccuracy'] = isGold ? 0.90 : 0.99;
      params['memoryRetention'] = isGold ? 0.88 : 0.99;

      // Dutch threshold : plus bas = dutch plus tôt
      final currentDutch = params['dutchThreshold'] ?? 15.0;
      params['dutchThreshold'] = isGold
          ? (currentDutch - 3.0).clamp(5.0, 12.0)
          : (currentDutch - 5.0).clamp(5.0, 8.0);

      // Dutch quality
      params['dutchQuality'] = isGold ? 0.76 : 0.95;

      // Agressivité
      params['aggressiveness'] =
          _boostParam(params['aggressiveness'] ?? 0.5, isGold ? 0.60 : 0.68);

      // Pouvoirs
      params['powerDefensiveRate'] = _boostParam(
          params['powerDefensiveRate'] ?? 0.5, isGold ? 0.64 : 0.78);
      params['powerOffensiveRate'] = _boostParam(
          params['powerOffensiveRate'] ?? 0.5, isGold ? 0.60 : 0.73);

      // Vitesse de décision : plus rapide
      final currentSpeed = params['decisionSpeed'] ?? 2000.0;
      params['decisionSpeed'] = isGold
          ? (currentSpeed * 0.7).clamp(500.0, 1500.0)
          : (currentSpeed * 0.5).clamp(500.0, 1000.0);

      // Marqueur pour télémétrie
      params['isBoostedSBMM'] = 1.0;

      players.add(Player(
        id: 'bot_$i',
        name: getBotName(BotBehavior.balanced, targetSkill),
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: targetSkill,
        aiParameters: params,
        position: i + 1,
      ));
    }

    if (kDebugMode) {
      debugPrint('🔥 Créé $numberOfBots bots SBMM boostés pour $difficulty');
      for (final p in players) {
        final pr = p.aiParameters!;
        debugPrint(
            '  🤖 ${p.name} | mem: ${(pr['memoryAccuracy']! * 100).toStringAsFixed(0)}% '
            '| dutch: ${pr['dutchThreshold']!.toStringAsFixed(0)} '
            '| speed: ${pr['decisionSpeed']!.toStringAsFixed(0)}ms');
      }
    }

    return players;
  }

  /// Boost un paramètre : prend le max entre la valeur actuelle et la cible.
  static double _boostParam(double current, double target) {
    return math.max(current, target);
  }

  static Future<bool> _canReachBackendQuickly() {
    return NetworkProbeService.canReachBackend(timeout: _networkProbeTimeout);
  }

  static Future<List<BotProfile>> _fetchTopBotsOfflineFirst({
    required BotLearningService botLearningService,
    required int limit,
  }) async {
    final isOnline = await _canReachBackendQuickly();
    if (!isOnline) {
      if (kDebugMode) {
        debugPrint('⚠️ Offline détecté, skip fetchTopBots (fallback local)');
      }
      return [];
    }
    return botLearningService.fetchTopBots(limit: limit);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Player _playerFromBotProfile(
      BotProfile? source, int index, BotSkillLevel targetSkill) {
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
      case 'moi':
      case 'mirror':
      case 'max_style':
        return BotBehavior.moi;
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

  /// Convertit un MMR en BotSkillLevel (pour affichage/nom uniquement)
  static BotSkillLevel _mmrToSkillLevel(int mmr) {
    if (mmr >= 900) return BotSkillLevel.platinum;
    if (mmr >= 600) return BotSkillLevel.platinum;
    if (mmr >= 300) return BotSkillLevel.silver;
    return BotSkillLevel.bronze;
  }

  static BotSkillLevel difficultyToSkillLevel(Difficulty difficulty) {
    switch (_normalizeStrongDifficulty(difficulty)) {
      case Difficulty.easy:
        return BotSkillLevel.bronze;
      case Difficulty.medium:
        return BotSkillLevel.silver;
      case Difficulty.hard:
      case Difficulty.platinum:
        return BotSkillLevel.platinum;
      case Difficulty.mix:
        return BotSkillLevel.silver;
    }
  }
}
