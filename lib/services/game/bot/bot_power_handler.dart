import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../learning/ai_telemetry_service.dart';
import '../../logging/game_logger_service.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_memory_manager.dart';
import 'bot_threat_analyzer.dart';
import 'bot_personality.dart';
import 'bot_power_notifications_stub.dart'
    if (dart.library.ui) 'bot_power_notifications_flutter.dart'
    as power_notifications;

/// Gestion des pouvoirs spéciaux des bots
/// Principe GRASP: Controller - Orchestre l'utilisation des pouvoirs
class BotPowerHandler {
  static final Random _random = Random();

  // ═══════════════════════════════════════════════════════════════════════════
  // TÉLÉMÉTRIE : Mesure d'impact des pouvoirs
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcule l'avantage de table actuel du bot
  /// Positif = bot devant, Négatif = bot derrière
  static double _calculateTableAdvantage(GameState gs, Player bot) {
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot);
    return report.bestOpponentScore - report.botExpectedScore;
  }

  /// Utilise le pouvoir spécial du bot
  static Future<void> useBotSpecialPower(
    GameState gameState,
    BotDifficulty difficulty,
    Object? context, {
    BotPersonality? personality,
    bool skipDelay = false,
  }) async {
    if (!gameState.isWaitingForSpecialPower ||
        gameState.specialCardToActivate == null) {
      return;
    }

    Player bot = gameState.currentPlayer;
    String val = gameState.specialCardToActivate!.value;

    final baseDelay = personality != null
        ? (personality.decisionSpeedMs * 0.35).round().clamp(150, 700)
        : 400;
    if (!skipDelay) {
      await Future.delayed(Duration(milliseconds: baseDelay));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOGIQUE DÉTERMINISTE : plus de "skip random" !
    // V et JOKER = toujours utilisés (mort subite)
    // 7 et 10 = utilisés si ça apporte de l'info utile
    // ═══════════════════════════════════════════════════════════════════════

    final report = BotThreatAnalyzer.analyzeOpponents(gameState, bot);
    final diffName = difficulty.name;
    final isPlatinum = _isPlatinumDifficulty(difficulty);
    final isGold = _isGoldDifficulty(difficulty);
    final isBronze = diffName == 'Bronze';
    final isSilver = diffName == 'Argent';

    // Détection de menace immédiate
    final hasImmediateThreat = report.hasOpponentWithOneCard ||
        report.minOpponentCards <= 2 ||
        (gameState.dutchCallerId != null && gameState.dutchCallerId != bot.id);

    // Pouvoirs offensifs = JAMAIS skip (peuvent retourner la partie)
    final isOffensive = (val == 'V' || val == 'JOKER');

    // ═══════════════════════════════════════════════════════════════════════
    // POUVOIR 10 INTELLIGENT
    // Skip si toutes nos cartes connues sont < 10 (on n'a pas besoin d'info)
    // SAUF si urgence (quelqu'un a 1 carte) → on veut savoir si Dutch est viable
    // ═══════════════════════════════════════════════════════════════════════
    bool shouldUsePower10 = true;
    if (val == '10') {
      final allCardsLow = BotMemoryManager.allKnownCardsBelow(bot, 10);
      final hasUnknownCards =
          BotMemoryManager.getUnknownIndices(bot).isNotEmpty;

      if (allCardsLow &&
          !hasUnknownCards &&
          !hasImmediateThreat &&
          !isPlatinum) {
        // Nos cartes sont bonnes, on connaît tout, pas d'urgence → skip
        shouldUsePower10 = false;
      }
    }

    // Pouvoirs d'info = utilisés si ça apporte quelque chose
    final hasUnknown = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;
    final shouldUseInfo =
        (val == '7' && (hasUnknown || isGold || isPlatinum)) ||
            (val == '10' && (shouldUsePower10 || isPlatinum));

    final shouldUsePower = isOffensive || shouldUseInfo || hasImmediateThreat;
    final forceUsePower7 = val == '7' && (isGold || isPlatinum);

    // Bronze "bête": rate souvent l'opportunité d'un pouvoir non critique.
    final passiveSkipChance = isBronze
        ? 0.92
        : isSilver
            ? 0.82
            : isGold
                ? 0.35
                : 0.0;
    if (passiveSkipChance > 0 &&
        !hasImmediateThreat &&
        !forceUsePower7 &&
        !isOffensive &&
        _random.nextDouble() < passiveSkipChance) {
      _skipPower(gameState, bot);
      return;
    }

    if (!shouldUsePower) {
      _skipPower(gameState, bot);
      return;
    }

    // TÉLÉMÉTRIE : snapshot avantage AVANT le pouvoir
    final advantageBefore = _calculateTableAdvantage(gameState, bot);

    if (val == '7') {
      _usePower7(gameState, bot, difficulty);
    } else if (val == '10') {
      await _usePower10(gameState, bot, difficulty, context,
          personality: personality);
    } else if (val == 'V') {
      await _usePowerValet(gameState, bot, difficulty, context,
          personality: personality);
    } else if (val == 'JOKER') {
      await _usePowerJoker(gameState, bot, difficulty, context,
          personality: personality);
    }

    // TÉLÉMÉTRIE : snapshot avantage APRÈS le pouvoir
    final advantageAfter = _calculateTableAdvantage(gameState, bot);
    final impactDelta = advantageAfter - advantageBefore;

    // Enregistrer l'impact du pouvoir
    final powerName = val == '7'
        ? 'look_own'
        : val == '10'
            ? 'spy'
            : val == 'V'
                ? 'swap'
                : 'shuffle';
    AiTelemetryService().onPowerUsed(bot.id, powerName, impactDelta);

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 7 : Regarder sa propre carte
  // ═══════════════════════════════════════════════════════════════════════════

  static void _usePower7(
      GameState gameState, Player bot, BotDifficulty difficulty) {
    final idx = _choosePower7TargetIndex(gameState, bot, difficulty);
    GameLogic.lookAtCard(gameState, bot, idx);
    bot.updateMentalMap(idx, bot.hand[idx]);

    // Log
    GameLoggerService.instance.logPowerUse(
      player: bot,
      powerValue: 7,
      powerName: 'Regarder',
      description:
          'Regarde sa carte position $idx (${bot.hand[idx].displayName})',
    );
  }

  static int _choosePower7TargetIndex(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
  ) {
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    final isAdvanced =
        _isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty);

    if (isAdvanced && unknownIndices.isNotEmpty) {
      int? swappedIndex;
      int latestSwapAction = -1;
      double bestSwapConfidence = -1.0;

      for (final idx in unknownIndices) {
        final hintAction = bot.getUnknownCardHintAction(idx);
        if (hintAction == null) continue;

        final confidence = bot.getUnknownCardHintConfidence(idx) ?? 0.0;
        if (hintAction > latestSwapAction ||
            (hintAction == latestSwapAction &&
                confidence > bestSwapConfidence)) {
          latestSwapAction = hintAction;
          bestSwapConfidence = confidence;
          swappedIndex = idx;
        }
      }

      if (swappedIndex != null) return swappedIndex;
    }

    if (_isPlatinumDifficulty(difficulty) && unknownIndices.isNotEmpty) {
      int? bestIndex;
      double bestPriority = -9999;

      for (final idx in unknownIndices) {
        final quality = bot.getUnknownCardHintQuality(idx);
        final confidence = bot.getUnknownCardHintConfidence(idx);
        if (quality == null || confidence == null) continue;

        final hintAction = bot.getUnknownCardHintAction(idx);
        final age = hintAction == null
            ? 0
            : (gameState.actionCount - hintAction).clamp(0, 20);
        final freshness = pow(0.90, age).toDouble();
        final weightedConfidence = confidence * freshness;

        // Priorité sur les inconnues stratégiques:
        // - carte supposée bonne à sécuriser
        // - ou carte suspecte à valider vite.
        final priority = quality >= 0
            ? weightedConfidence * (1.10 + quality)
            : weightedConfidence * (0.85 + (-quality * 0.45));

        if (priority > bestPriority) {
          bestPriority = priority;
          bestIndex = idx;
        }
      }

      if (bestIndex != null) return bestIndex;
    }

    if (unknownIndices.isNotEmpty) {
      return unknownIndices[_random.nextInt(unknownIndices.length)];
    }

    if (isAdvanced) {
      int worstIdx = 0;
      int worstValue = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        final known = bot.mentalMap[i];
        if (known != null && known.points > worstValue) {
          worstValue = known.points;
          worstIdx = i;
        }
      }
      return worstIdx;
    }

    return BotMemoryManager.chooseCardToLook(bot, difficulty);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 10 : Espionner une carte adverse
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePower10(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    Object? context, {
    BotPersonality? personality,
  }) async {
    Player? target =
        _chooseSpyTarget(gameState, bot, difficulty, personality: personality);
    if (target == null || target.hand.isEmpty) return;

    // HARDCORE FIX: Les niveaux hardcore ciblent intelligemment
    final isHardcore = difficulty.name == "Or" ||
        difficulty.name == "Platine" ||
        difficulty.name == "Hard" ||
        difficulty.name == "Insane" ||
        difficulty.name == "Nightmare" ||
        difficulty.name == "Impossible";

    int idx;
    if (isHardcore && _random.nextDouble() < 0.7) {
      idx = _random.nextBool() ? 0 : target.hand.length - 1;
    } else {
      idx = _random.nextInt(target.hand.length);
    }
    GameLogic.lookAtCard(gameState, target, idx);

    // AMÉLIORATION : Le bot mémorise la carte espionnée
    // Cela lui permet de mieux estimer le score adverse pour Dutch
    final spiedCard = target.hand[idx];
    bot.rememberSpiedCard(target.id, idx, spiedCard);

    // Log
    GameLoggerService.instance.logPowerUse(
      player: bot,
      powerValue: 10,
      powerName: 'Espionner',
      description:
          'Espionne ${target.name} position $idx (${spiedCard.displayName})',
    );

    if (target.isHuman) {
      await power_notifications.showBotSpyNotification(
        context,
        bot,
        target.name,
        idx,
      );
    }
  }

  static Player? _chooseSpyTarget(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    if (_isBronzeDifficulty(difficulty)) {
      final candidates =
          gs.players.where((p) => p.hand.isNotEmpty).toList(growable: false);
      if (candidates.isEmpty) return null;

      final human = candidates.where((p) => p.isHuman).firstOrNull;
      final protectHuman = human != null && human.hand.length > 1;
      if (protectHuman) {
        final nonHumanCandidates =
            candidates.where((p) => !p.isHuman).toList(growable: false);
        if (nonHumanCandidates.isNotEmpty) {
          return nonHumanCandidates[_random.nextInt(nonHumanCandidates.length)];
        }
      }

      if (human != null &&
          human.hand.length <= 1 &&
          _random.nextDouble() < 0.55) {
        return human;
      }
      return candidates[_random.nextInt(candidates.length)];
    }

    List<Player> opponents =
        gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    // Utiliser le système de ciblage unifié basé sur la menace réelle
    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    final target = BotThreatAnalyzer.pickBestTarget(
      gs,
      bot,
      TargetMode.gatherInfo,
      difficulty: difficulty,
      isHardcoreMode: isHardcore,
    );
    if (target != null) return target;

    return opponents[_random.nextInt(opponents.length)];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR VALET : Échange de cartes
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerValet(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    Object? context, {
    BotPersonality? personality,
  }) async {
    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE VALET : Échanger entre DEUX AUTRES joueurs (pas soi-même)
    // Cela permet de déstabiliser les adversaires sans perdre sa propre mémoire
    // ═══════════════════════════════════════════════════════════════════════

    // Trouver deux cibles différentes (pas le bot lui-même)
    final targets =
        _chooseValetTargets(gs, bot, difficulty, personality: personality);
    if (targets == null) return;

    final (target1, target2) = targets;
    if (target1.hand.isEmpty || target2.hand.isEmpty) return;

    // Choisir les indices des cartes à échanger
    int idx1 =
        _chooseValetTargetCardIndex(target1, difficulty, bot.botBehavior);
    int idx2 =
        _chooseValetTargetCardIndex(target2, difficulty, bot.botBehavior);

    // Effectuer l'échange entre les deux AUTRES joueurs
    GameLogic.swapCards(gs, target1, idx1, target2, idx2);

    // Notifier si l'humain est impliqué — le jeu attend que l'humain clique OK
    if (target1.isHuman) {
      // L'humain est target1 : sa carte #idx1 a été échangée avec target2
      // Après le swap, target1.hand[idx1] = ancienne carte de target2
      await power_notifications.showBotSwapNotification(
        context,
        bot,
        target1.name,
        idx1,
        swapPartnerName: target2.name,
        receivedCardPosition: idx2 + 1,
      );
    } else if (target2.isHuman) {
      // L'humain est target2 : sa carte #idx2 a été échangée avec target1
      await power_notifications.showBotSwapNotification(
        context,
        bot,
        target2.name,
        idx2,
        swapPartnerName: target1.name,
        receivedCardPosition: idx1 + 1,
      );
    }
  }

  /// Choisit DEUX cibles pour le pouvoir Valet (pas le bot lui-même)
  /// Bronze: comportement chaotique.
  /// Argent: ciblage menace existant.
  /// Or/Platine: règles contextuelles demandées (cartes d'abord, puis ranking).
  static (Player, Player)? _chooseValetTargets(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    if (_isBronzeDifficulty(difficulty)) {
      final candidates =
          gs.players.where((p) => p.hand.isNotEmpty).toList(growable: false);
      if (candidates.length < 2) return null;

      final human = candidates.where((p) => p.isHuman).firstOrNull;
      final protectHuman = human != null && human.hand.length > 1;

      if (protectHuman) {
        final nonHuman =
            candidates.where((p) => !p.isHuman).toList(growable: false);
        if (nonHuman.isEmpty) return null;
        if (nonHuman.length == 1) {
          return (nonHuman.first, nonHuman.first);
        }

        final first = nonHuman[_random.nextInt(nonHuman.length)];
        if (_random.nextDouble() < 0.25) {
          return (first, first);
        }
        final others = nonHuman.where((p) => p.id != first.id).toList();
        final second = others.isEmpty
            ? nonHuman[_random.nextInt(nonHuman.length)]
            : others[_random.nextInt(others.length)];
        return (first, second);
      }

      final first = (human != null &&
              human.hand.length <= 1 &&
              _random.nextDouble() < 0.65)
          ? human
          : candidates[_random.nextInt(candidates.length)];

      // Bronze peut même se "viser" lui-même ou refaire le même choix.
      if (_random.nextDouble() < 0.22) {
        return (first, first);
      }

      final others = candidates.where((p) => p.id != first.id).toList();
      final second = others.isEmpty
          ? candidates[_random.nextInt(candidates.length)]
          : others[_random.nextInt(others.length)];
      return (first, second);
    }

    final opponents =
        gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.length < 2) return null;

    final isAdvancedValet =
        _isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty);
    if (!isAdvancedValet) {
      // Argent: conserver l'ancien ciblage par menace.
      final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
      final report = BotThreatAnalyzer.analyzeOpponents(gs, bot,
          isHardcoreMode: isHardcore);

      final sorted = report.sortedByThreat;
      if (sorted.length >= 2) {
        return (sorted[0].player, sorted[1].player);
      }
      return (opponents[0], opponents[1]);
    }

    final bots = opponents.where((p) => !p.isHuman).toList();
    final humans = opponents.where((p) => p.isHuman).toList();

    final allSorted = List<Player>.from(opponents)
      ..sort(_compareByCardsThenHistory);
    final botsSorted = List<Player>.from(bots)
      ..sort(_compareByCardsThenHistory);
    final humansSorted = List<Player>.from(humans)
      ..sort(_compareByCardsThenHistory);

    // 1) Priorité: bots "boostés" (moins de cartes que le max des bots),
    // puis on garde seulement ceux au minimum de cartes.
    if (botsSorted.isNotEmpty) {
      final maxBotCards =
          botsSorted.map((p) => p.hand.length).reduce((a, b) => a > b ? a : b);
      final boostedCandidates =
          botsSorted.where((p) => p.hand.length < maxBotCards).toList();

      if (boostedCandidates.isNotEmpty) {
        final minBoostedCards = boostedCandidates
            .map((p) => p.hand.length)
            .reduce((a, b) => a < b ? a : b);
        final boosted = boostedCandidates
            .where((p) => p.hand.length == minBoostedCards)
            .toList()
          ..sort(_compareByHistoryThenCards);

        if (boosted.length >= 2) {
          return (boosted[0], boosted[1]);
        }

        if (boosted.length == 1) {
          final j1 = boosted.first;
          final j2 = botsSorted.firstWhere(
            (p) => p.id != j1.id,
            orElse: () {
              final fallback = humansSorted.firstWhere(
                (p) => p.id != j1.id,
                orElse: () => allSorted.firstWhere(
                  (p) => p.id != j1.id,
                  orElse: () => j1,
                ),
              );
              return fallback;
            },
          );

          if (j2.id != j1.id) {
            return (j1, j2);
          }
        }
      }
    }

    // 2) Si le bot connaît toute sa main: perturber le bot "historique fort"
    // avec un humain prioritaire.
    final knowsAllCards = BotMemoryManager.getUnknownIndices(bot).isEmpty;
    if (knowsAllCards && botsSorted.isNotEmpty && humansSorted.isNotEmpty) {
      return (botsSorted.first, humansSorted.first);
    }

    // 3) Fallback déterministe: cartes ASC puis historique DESC.
    if (allSorted.length >= 2) {
      return (allSorted[0], allSorted[1]);
    }

    return null;
  }

  static int _chooseValetTargetCardIndex(
      Player target, BotDifficulty difficulty, BotBehavior? behavior) {
    if (target.hand.isEmpty) return 0;
    if (target.hand.length == 1) return 0;

    // Le bot ne voit PAS les cartes cachées de la cible
    // Il choisit un index aléatoire (comme un humain le ferait)
    return _random.nextInt(target.hand.length);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR JOKER : Mélanger la main d'un joueur
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerJoker(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    Object? context, {
    BotPersonality? personality,
  }) async {
    Player? target =
        _chooseJokerTarget(gs, bot, difficulty, personality: personality);
    target ??= bot;

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
    }

    if (target.isHuman) {
      await power_notifications.showBotJokerNotification(
        context,
        bot,
        target.name,
      );
    }
  }

  /// Choisit la cible du Joker selon l'analyse de menace contextuelle
  /// Règles :
  /// 1. Le joueur le plus menaçant selon le score de menace unifié
  /// 2. À menace égale, l'humain est préféré (via tiebreaker +3)
  /// 3. Si l'humain est dans le top 2 menace, il est ciblé
  /// 4. Ne cible que les joueurs avec >= 2 cartes (mélanger 1 carte est inutile)
  static Player? _chooseJokerTarget(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    if (_isBronzeDifficulty(difficulty)) {
      final candidates =
          gs.players.where((p) => p.hand.length >= 2).toList(growable: false);
      if (candidates.isEmpty) return null;

      final human = candidates.where((p) => p.isHuman).firstOrNull;
      final protectHuman = human != null && human.hand.length > 1;
      if (protectHuman) {
        final nonHuman =
            candidates.where((p) => !p.isHuman).toList(growable: false);
        if (nonHuman.isNotEmpty) {
          if (_random.nextDouble() < 0.35) {
            return bot;
          }
          return nonHuman[_random.nextInt(nonHuman.length)];
        }
      }

      if (human != null &&
          human.hand.length <= 1 &&
          _random.nextDouble() < 0.55) {
        return human;
      }
      if (_random.nextDouble() < 0.30) {
        return bot;
      }
      return candidates[_random.nextInt(candidates.length)];
    }

    List<Player> possibleTargets =
        gs.players.where((p) => p.id != bot.id && p.hand.length >= 2).toList();
    if (possibleTargets.isEmpty) return null;

    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    final report =
        BotThreatAnalyzer.analyzeOpponents(gs, bot, isHardcoreMode: isHardcore);

    // Filtrer les menaces pour ne garder que ceux avec >= 2 cartes
    final validThreats =
        report.sortedByThreat.where((o) => o.cardsLeft >= 2).toList();

    if (validThreats.isEmpty) return null;

    // RÈGLE : Si l'humain est dans le top 2 des menaces, le cibler
    final humanInTop2 = validThreats.take(2).any((o) => o.isHuman);
    if (humanInTop2) {
      final humanThreat = validThreats.firstWhere((o) => o.isHuman);
      return humanThreat.player;
    }

    // Sinon : cibler le joueur le plus menaçant
    return validThreats.first.player;
  }

  static void _skipPower(GameState gameState, Player bot) {
    final powerVal = gameState.specialCardToActivate?.value ?? '?';

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("⏭️ ${bot.name} ignore son pouvoir.");

    // Log
    GameLoggerService.instance.logPowerSkip(
      player: bot,
      powerValue: int.tryParse(powerVal) ?? 0,
      reason: 'Pas d\'avantage à utiliser ce pouvoir',
    );
  }

  static bool _isPlatinumDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Platine':
      case 'Nightmare':
      case 'Impossible':
        return true;
      default:
        return difficulty.matchAccuracy >= 0.99 &&
            difficulty.reactionSpeed >= 0.98;
    }
  }

  static bool _isBronzeDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Bronze':
        return true;
      default:
        return difficulty.matchAccuracy <= 0.7 &&
            difficulty.reactionSpeed <= 0.5;
    }
  }

  static bool _isGoldDifficulty(BotDifficulty difficulty) {
    if (_isPlatinumDifficulty(difficulty)) return false;
    switch (difficulty.name) {
      case 'Or':
      case 'Hard':
      case 'Insane':
        return true;
      default:
        return difficulty.matchAccuracy >= 0.95 &&
            difficulty.reactionSpeed >= 0.9;
    }
  }

  static int _compareByCardsThenHistory(Player a, Player b) {
    final byCards = a.hand.length.compareTo(b.hand.length);
    if (byCards != 0) return byCards;

    final byHistory =
        _historicalRankingScore(b).compareTo(_historicalRankingScore(a));
    if (byHistory != 0) return byHistory;

    return a.id.compareTo(b.id);
  }

  static int _compareByHistoryThenCards(Player a, Player b) {
    final byHistory =
        _historicalRankingScore(b).compareTo(_historicalRankingScore(a));
    if (byHistory != 0) return byHistory;

    final byCards = a.hand.length.compareTo(b.hand.length);
    if (byCards != 0) return byCards;

    return a.id.compareTo(b.id);
  }

  static int _historicalRankingScore(Player player) {
    final level = player.botSkillLevel;
    if (level == null) return 0;
    switch (level) {
      case BotSkillLevel.bronze:
        return 1;
      case BotSkillLevel.silver:
        return 2;
      case BotSkillLevel.gold:
        return 3;
      case BotSkillLevel.platinum:
        return 4;
    }
  }
}
