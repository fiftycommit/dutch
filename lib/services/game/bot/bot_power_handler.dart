import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import '../../learning/ai_telemetry_service.dart';
import '../../logging/game_logger_service.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_memory_manager.dart';
import 'bot_threat_analyzer.dart';
import 'bot_dutch_strategy.dart';
import 'bot_personality.dart';
import 'bot_power_notifications_stub.dart'
    if (dart.library.ui) 'bot_power_notifications_flutter.dart'
    as power_notifications;

/// Gestion des pouvoirs spéciaux des bots
/// Principe GRASP: Controller - Orchestre l'utilisation des pouvoirs
class BotPowerHandler {
  static final Random _random = Random();
  static const int _bronzeHumanValetCooldownTurns = 4;
  static const int _silverHumanValetCooldownTurns = 2;
  static _PlatinumKillWindow? _platinumKillWindow;
  static String _platinumKillWindowTableKey = '';
  static int _platinumKillWindowLastTurn = -1;

  // ═══════════════════════════════════════════════════════════════════════════
  // TÉLÉMÉTRIE : Mesure d'impact des pouvoirs
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcule l'avantage de table actuel du bot
  /// Positif = bot devant, Négatif = bot derrière
  static double _calculateTableAdvantage(
    GameState gs,
    Player bot, {
    BotDifficulty? difficulty,
  }) {
    final report =
        BotThreatAnalyzer.analyzeOpponents(gs, bot, difficulty: difficulty);
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

    if (_isPlatinumDifficulty(difficulty)) {
      _refreshPlatinumKillWindow(gameState, bot);
    }

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
    final report = BotThreatAnalyzer.analyzeOpponents(
      gameState,
      bot,
      difficulty: difficulty,
    );
    final powerConclusions = _buildPowerUseConclusions(
      gameState: gameState,
      bot: bot,
      difficulty: difficulty,
      report: report,
      powerValue: val,
    );

    // Argent (medium): le 7 est utilisé sauf étourdissement contextuel.
    if (powerConclusions.shouldSkipSilverPower7ByDizziness) {
      _skipPower(gameState, bot);
      return;
    }

    // Bronze "bête": rate souvent l'opportunité d'un pouvoir non critique.
    if (powerConclusions.passiveSkipChance > 0 &&
        !powerConclusions.hasImmediateThreat &&
        !powerConclusions.forceUsePower7 &&
        !powerConclusions.isSilverPower7 &&
        !powerConclusions.isOffensive &&
        _random.nextDouble() < powerConclusions.passiveSkipChance) {
      _skipPower(gameState, bot);
      return;
    }

    if (!powerConclusions.shouldUsePower) {
      _skipPower(gameState, bot);
      return;
    }

    // TÉLÉMÉTRIE : snapshot avantage AVANT le pouvoir
    final advantageBefore = _calculateTableAdvantage(
      gameState,
      bot,
      difficulty: difficulty,
    );

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
    final advantageAfter = _calculateTableAdvantage(
      gameState,
      bot,
      difficulty: difficulty,
    );
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

  static _PowerUseConclusions _buildPowerUseConclusions({
    required GameState gameState,
    required Player bot,
    required BotDifficulty difficulty,
    required ThreatReport report,
    required String powerValue,
  }) {
    final diffName = difficulty.name;
    final isPlatinum = _isPlatinumDifficulty(difficulty);
    final isGold = _isGoldDifficulty(difficulty);
    final isBronze = diffName == 'Bronze';
    final isSilver = diffName == 'Argent';

    final hasImmediateThreat = report.hasOpponentWithOneCard ||
        report.minOpponentCards <= 2 ||
        (gameState.dutchCallerId != null && gameState.dutchCallerId != bot.id);

    final isOffensive = powerValue == 'V' || powerValue == 'JOKER';
    final hasUnknown = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;
    final hasPlatinumKillWindow =
        isPlatinum && _hasActivePlatinumKillWindow(gameState);

    bool shouldUsePower10 = true;
    if (powerValue == '10') {
      final allCardsLow = BotMemoryManager.allKnownCardsBelow(bot, 10);
      if (allCardsLow && !hasUnknown && !hasImmediateThreat && !isPlatinum) {
        shouldUsePower10 = false;
      }
    }

    final shouldUseInfo =
        (powerValue == '7' && (hasUnknown || isGold || isPlatinum)) ||
            (powerValue == '10' && (shouldUsePower10 || isPlatinum));
    bool shouldUsePower = isOffensive || shouldUseInfo || hasImmediateThreat;
    if (isPlatinum && isOffensive) {
      // Réserve Valet/Joker pour la fenêtre de kill ou les urgences.
      shouldUsePower = hasPlatinumKillWindow || hasImmediateThreat;
    }
    final forceUsePower7 = powerValue == '7' && (isGold || isPlatinum);
    final isSilverPower7 = isSilver && powerValue == '7';
    final shouldSkipSilverPower7ByDizziness =
        isSilverPower7 && _shouldSilverSkipPower7(gameState, bot);

    final passiveSkipChance = isBronze
        ? 0.92
        : isSilver
            // Argent reste distrait sur les pouvoirs "confort",
            // mais n'ignore pas arbitrairement un espionnage 10.
            ? (powerValue == '10' ? 0.0 : 0.26)
            : isGold
                ? 0.12
                : 0.0;

    return _PowerUseConclusions(
      hasImmediateThreat: hasImmediateThreat,
      isOffensive: isOffensive,
      shouldUsePower: shouldUsePower,
      forceUsePower7: forceUsePower7,
      isSilverPower7: isSilverPower7,
      shouldSkipSilverPower7ByDizziness: shouldSkipSilverPower7ByDizziness,
      passiveSkipChance: passiveSkipChance,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 7 : Regarder sa propre carte
  // ═══════════════════════════════════════════════════════════════════════════

  static void _usePower7(
      GameState gameState, Player bot, BotDifficulty difficulty) {
    if (bot.hand.isEmpty) return;

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
      if (_isSilverDifficulty(difficulty)) {
        return unknownIndices.first;
      }
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

    final spiedCard = target.hand[idx];
    if (_isSilverDifficulty(difficulty)) {
      // Argent: oublie souvent l'info espionnée.
      final remembersSpy = _random.nextDouble() >= 0.60;
      if (remembersSpy) {
        bot.rememberSpiedCard(target.id, idx, spiedCard);
      } else {
        bot.spyMemory[target.id]?.remove(idx);
      }

      // Argent: peut confondre l'info adverse avec une de ses propres cartes.
      if (_random.nextDouble() < 0.33) {
        _applySilverSpyConfusion(gameState, bot, spiedCard);
      }
    } else {
      // AMÉLIORATION : Le bot mémorise la carte espionnée
      // Cela lui permet de mieux estimer le score adverse pour Dutch
      bot.rememberSpiedCard(target.id, idx, spiedCard);
    }

    if (target.id != bot.id) {
      target.lastTargetedByPowerTurn = gameState.turnCount;
    }

    if (_isBronzeDifficulty(difficulty)) {
      _applyBronzeSpyDistraction(gameState, bot);
    }

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

    // Argent: si un humain est à 1 carte, priorité d'info immédiate.
    // Évite les runs non déterministes où le bot ignore la cible critique.
    if (_isSilverDifficulty(difficulty)) {
      final urgentHumans = opponents
          .where((p) => p.isHuman && p.hand.length <= 1)
          .toList(growable: false);
      if (urgentHumans.isNotEmpty) {
        urgentHumans.sort((a, b) => a.hand.length.compareTo(b.hand.length));
        return urgentHumans.first;
      }
    }

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

    final humanCooldownTurns = _humanValetCooldownTurns(bot, difficulty);
    if (humanCooldownTurns > 0) {
      if (target1.isHuman) {
        target1.lastBronzeValetTargetTurn = gs.turnCount;
      }
      if (target2.isHuman) {
        target2.lastBronzeValetTargetTurn = gs.turnCount;
      }
    }

    if (target1.id != bot.id) {
      target1.lastTargetedByPowerTurn = gs.turnCount;
    }
    if (target2.id != bot.id) {
      target2.lastTargetedByPowerTurn = gs.turnCount;
    }

    // Choisir les indices des cartes à échanger
    int idx1 = _chooseValetTargetCardIndex(
      target1,
      difficulty,
      bot.botBehavior,
      observer: bot,
      preferLowIfKnown: true,
    );
    int idx2 = _chooseValetTargetCardIndex(
      target2,
      difficulty,
      bot.botBehavior,
      observer: bot,
      preferLowIfKnown: false,
    );

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
  /// Or/Platine: cible les 2 joueurs les plus forts.
  /// Si choix ambigu, inclut un humain dans les cibles.
  /// Protection anti-focus humain:
  /// - Bronze: max 1 ciblage humain / 4 tours de table.
  /// - Argent: max 1 ciblage humain / 2 tours de table.
  static (Player, Player)? _chooseValetTargets(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    final isBronzeValet = bot.botSkillLevel == BotSkillLevel.bronze ||
        _isBronzeDifficulty(difficulty);
    final humanCooldownTurns = _humanValetCooldownTurns(bot, difficulty);

    if (isBronzeValet) {
      final candidates =
          gs.players.where((p) => p.hand.isNotEmpty).toList(growable: false);
      if (candidates.length < 2) return null;

      final protectedHumanIds =
          _protectedHumanIds(gs, candidates, humanCooldownTurns);

      List<Player> pool = candidates
          .where((p) => !protectedHumanIds.contains(p.id))
          .toList(growable: false);
      if (pool.length < 2) {
        pool = List<Player>.from(candidates);
      }

      final first = pool[_random.nextInt(pool.length)];
      List<Player> secondPool =
          pool.where((p) => p.id != first.id).toList(growable: false);
      if (secondPool.isEmpty) {
        secondPool =
            candidates.where((p) => p.id != first.id).toList(growable: false);
      }
      if (secondPool.isEmpty) return null;

      final second = secondPool[_random.nextInt(secondPool.length)];
      return (first, second);
    }

    final opponents =
        gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.length < 2) return null;

    final isAdvancedValet =
        _isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty);
    if (!isAdvancedValet) {
      // Argent: conserver l'ancien ciblage par menace.
      List<Player> threatPool = opponents;
      final protectedHumanIds =
          _protectedHumanIds(gs, opponents, humanCooldownTurns);
      final unprotectedPool = opponents
          .where((p) => !protectedHumanIds.contains(p.id))
          .toList(growable: false);
      if (unprotectedPool.length >= 2) {
        threatPool = unprotectedPool;
      }

      final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
      final report = BotThreatAnalyzer.analyzeOpponents(gs, bot,
          isHardcoreMode: isHardcore, difficulty: difficulty);

      final poolIds = threatPool.map((p) => p.id).toSet();
      final sorted = report.sortedByThreat
          .map((entry) => entry.player)
          .where((p) => poolIds.contains(p.id))
          .toList(growable: false);
      if (sorted.length >= 2) {
        return (sorted[0], sorted[1]);
      }
      return (threatPool[0], threatPool[1]);
    }

    if (_isPlatinumDifficulty(difficulty)) {
      _refreshPlatinumKillWindow(gs, bot);
      final lockedTarget =
          _getActivePlatinumKillTarget(gs, candidates: opponents);
      if (lockedTarget != null) {
        final second = opponents
            .where((p) => p.id != lockedTarget.id)
            .toList(growable: false)
          ..sort((a, b) {
            final sa = _adaptivePlatinumThreatScore(gs, bot, a, difficulty);
            final sb = _adaptivePlatinumThreatScore(gs, bot, b, difficulty);
            return sb.compareTo(sa);
          });
        if (second.isNotEmpty) {
          Player secondTarget = second.first;
          final isAmbiguous =
              _isValetChoiceAmbiguous(opponents, lockedTarget, secondTarget);
          if (isAmbiguous && !lockedTarget.isHuman && !secondTarget.isHuman) {
            final humans = second.where((p) => p.isHuman).toList();
            if (humans.isNotEmpty) {
              secondTarget = humans.first;
            }
          }
          if (lockedTarget.id != secondTarget.id) {
            return (lockedTarget, secondTarget);
          }
        }
      }
    }

    if (_isPlatinumDifficulty(difficulty)) {
      final adaptiveTargets = _chooseAdaptivePlatinumValetTargets(
        gs,
        bot,
        opponents,
        difficulty,
      );
      if (adaptiveTargets != null) return adaptiveTargets;
    }

    final ranked = List<Player>.from(opponents)..sort(_compareByValetStrength);
    Player first = ranked[0];
    Player second = ranked[1];

    final isAmbiguous = _isValetChoiceAmbiguous(opponents, first, second);
    if (isAmbiguous && !first.isHuman && !second.isHuman) {
      final humans = opponents.where((p) => p.isHuman).toList()
        ..sort(_compareByValetStrength);

      if (humans.isNotEmpty) {
        final preferredHuman = humans.first;
        if (preferredHuman.id != first.id) {
          second = preferredHuman;
        } else if (humans.length >= 2) {
          second = humans[1];
        }
      }
    }

    if (first.id == second.id) {
      final fallback = ranked.firstWhere(
        (p) => p.id != first.id,
        orElse: () => first,
      );
      if (fallback.id != first.id) {
        second = fallback;
      } else {
        return null;
      }
    }

    return (first, second);
  }

  static int _chooseValetTargetCardIndex(
    Player target,
    BotDifficulty difficulty,
    BotBehavior? behavior, {
    Player? observer,
    required bool preferLowIfKnown,
  }) {
    if (target.hand.isEmpty) return 0;
    if (target.hand.length == 1) return 0;

    // Si le bot a espionné des cartes sur cette cible, il exploite cette info.
    // - preferLowIfKnown=true  : extraire une carte probablement bonne (basse)
    //   pour l'échanger et potentiellement "empoisonner" le joueur ciblé.
    // - preferLowIfKnown=false : choisir une carte probablement haute.
    final spied = observer?.getSpiedCards(target.id);
    if (spied != null && spied.isNotEmpty) {
      final knownEntries = spied.entries
          .where((e) => e.key >= 0 && e.key < target.hand.length)
          .toList(growable: false);
      if (knownEntries.isNotEmpty) {
        knownEntries.sort((a, b) {
          if (preferLowIfKnown) {
            return a.value.points.compareTo(b.value.points);
          }
          return b.value.points.compareTo(a.value.points);
        });
        return knownEntries.first.key;
      }
    }

    // Sans info fiable, le bot ne voit pas les cartes cachées de la cible.
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

    if (target.id != bot.id) {
      target.lastTargetedByPowerTurn = gs.turnCount;
    }

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
  /// Bronze: cible le joueur (hors bot) avec le moins de cartes > 1.
  /// Aucune distinction humain/bot: seulement la dangerosité.
  /// Silver/Gold/Platinum:
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
      final candidates = gs.players
          .where((p) => p.id != bot.id && p.hand.length > 1)
          .toList(growable: false);
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) {
        final byCards = a.hand.length.compareTo(b.hand.length);
        if (byCards != 0) return byCards;
        final byHistory =
            _historicalRankingScore(b).compareTo(_historicalRankingScore(a));
        if (byHistory != 0) return byHistory;
        return a.id.compareTo(b.id);
      });
      return candidates.first;
    }

    List<Player> possibleTargets =
        gs.players.where((p) => p.id != bot.id && p.hand.length >= 2).toList();
    if (possibleTargets.isEmpty) return null;

    if (_isPlatinumDifficulty(difficulty)) {
      _refreshPlatinumKillWindow(gs, bot);
      final lockedTarget =
          _getActivePlatinumKillTarget(gs, candidates: possibleTargets);
      if (lockedTarget != null) {
        return lockedTarget;
      }

      final scored = possibleTargets
          .map((p) => (
                player: p,
                score: _adaptivePlatinumThreatScore(gs, bot, p, difficulty)
              ))
          .toList(growable: false)
        ..sort((a, b) => b.score.compareTo(a.score));
      if (scored.isNotEmpty) {
        return scored.first.player;
      }
    }

    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    final report = BotThreatAnalyzer.analyzeOpponents(
      gs,
      bot,
      isHardcoreMode: isHardcore,
      difficulty: difficulty,
    );

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
      case 'Argent':
      case 'Or':
      case 'Platine':
      case 'Hard':
      case 'Insane':
      case 'Nightmare':
      case 'Impossible':
        return false;
      default:
        // Fallback "bronze-like" pour difficultés dynamiques:
        // volontairement plus bas que Silver pour éviter le recouvrement.
        return difficulty.matchAccuracy < 0.55 &&
            difficulty.reactionSpeed < 0.45;
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

  static bool _isSilverDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Argent':
        return true;
      default:
        return !_isBronzeDifficulty(difficulty) &&
            !_isGoldDifficulty(difficulty) &&
            !_isPlatinumDifficulty(difficulty);
    }
  }

  static bool _shouldSilverSkipPower7(GameState gs, Player bot) {
    final attackedRecently = (gs.turnCount - bot.lastTargetedByPowerTurn) <= 3;
    final myTurnsPlayed = gs.actionCount ~/ gs.players.length;
    final opponentsCards = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => p.hand.length)
        .toList(growable: false);
    final minOpponentCards = opponentsCards.isEmpty
        ? 4
        : opponentsCards.reduce((a, b) => a < b ? a : b);
    final earlyAndRelaxed = myTurnsPlayed <= 3 && minOpponentCards >= 3;
    return attackedRecently || earlyAndRelaxed;
  }

  static void _applySilverSpyConfusion(
    GameState gs,
    Player bot,
    PlayingCard spiedCard,
  ) {
    if (bot.isHuman || bot.hand.isEmpty) return;

    while (bot.mentalMap.length < bot.hand.length) {
      bot.mentalMap.add(null);
    }
    while (bot.knownCards.length < bot.hand.length) {
      bot.knownCards.add(false);
    }

    final idx = _random.nextInt(bot.hand.length);
    bot.mentalMap[idx] =
        PlayingCard.create(bot.hand[idx].suit, spiedCard.value);
    bot.knownCards[idx] = true;
    bot.clearUnknownCardHint(idx);
    gs.addToHistory(
      '🤯 ${bot.name} confond l\'info espionnée avec sa propre carte.',
    );
  }

  static void _applyBronzeSpyDistraction(GameState gs, Player bot) {
    if (bot.isHuman || bot.botSkillLevel != BotSkillLevel.bronze) return;

    final knownIndices = <int>[];
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      if (bot.mentalMap[i] != null) {
        knownIndices.add(i);
      }
    }
    if (knownIndices.isEmpty) return;

    final idx = knownIndices[_random.nextInt(knownIndices.length)];
    bot.forgetCard(idx);
    gs.addToHistory('😵 ${bot.name} se distrait et oublie une de ses cartes.');
  }

  static int _compareByValetStrength(Player a, Player b) {
    final byStrength = _valetStrengthKey(a).compareTo(_valetStrengthKey(b));
    if (byStrength != 0) return byStrength;
    return a.id.compareTo(b.id);
  }

  static int _valetStrengthKey(Player player) {
    // Plus petit = plus fort.
    // Priorité au nombre de cartes, puis ranking historique.
    // Règle métier: un humain à 2 cartes ou moins est TOUJOURS
    // la menace prioritaire.
    if (player.isHuman && player.hand.length <= 2) {
      return -1000 + player.hand.length;
    }

    final history = _historicalRankingScore(player);
    return (player.hand.length * 10) + (4 - history);
  }

  static bool _isValetChoiceAmbiguous(
      List<Player> opponents, Player first, Player second) {
    final firstKey = _valetStrengthKey(first);
    final secondKey = _valetStrengthKey(second);

    final firstTies =
        opponents.where((p) => _valetStrengthKey(p) == firstKey).length;
    final secondTies =
        opponents.where((p) => _valetStrengthKey(p) == secondKey).length;

    return firstTies > 1 || secondTies > 1;
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

  static (Player, Player)? _chooseAdaptivePlatinumValetTargets(
    GameState gs,
    Player observer,
    List<Player> opponents,
    BotDifficulty difficulty,
  ) {
    if (opponents.length < 2) return null;

    final scored = opponents
        .map((p) => (
              player: p,
              score: _adaptivePlatinumThreatScore(gs, observer, p, difficulty)
            ))
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    Player first = scored[0].player;
    Player second = scored[1].player;
    final gap = scored[0].score - scored[1].score;

    // Si le choix est ambigu, injecter un humain pour augmenter
    // la perturbation perçue (règle métier existante).
    if (gap <= 2.0 && !first.isHuman && !second.isHuman) {
      final humanScored = scored.where((e) => e.player.isHuman).toList();
      if (humanScored.isNotEmpty && humanScored.first.player.id != first.id) {
        second = humanScored.first.player;
      }
    }

    // Déstabilisation adaptative:
    // si un autre joueur "optimise vite", le forcer dans l'échange.
    final opportunist = scored
        .where((e) =>
            e.player.id != first.id &&
            e.player.id != second.id &&
            e.player.hand.length <= 3 &&
            _opponentOptimizationSignal(e.player.id) >= 0.58)
        .firstOrNull;
    if (opportunist != null) {
      final closeRace = gap <= 3.0 || first.hand.length <= 2;
      final opportunistCloseToSecond = opportunist.score >= scored[1].score - 1;
      if (closeRace || opportunistCloseToSecond) {
        second = opportunist.player;
      }
    }

    final isAmbiguous = _isValetChoiceAmbiguous(opponents, first, second);
    if (isAmbiguous && !first.isHuman && !second.isHuman) {
      final humanScored = scored.where((e) => e.player.isHuman).toList();
      if (humanScored.isNotEmpty && humanScored.first.player.id != first.id) {
        second = humanScored.first.player;
      }
    }

    if (first.id == second.id) {
      final fallback = scored
          .map((e) => e.player)
          .firstWhere((p) => p.id != first.id, orElse: () => first);
      if (fallback.id != first.id) {
        second = fallback;
      } else {
        return null;
      }
    }

    return (first, second);
  }

  static double _adaptivePlatinumThreatScore(
    GameState gs,
    Player observer,
    Player player,
    BotDifficulty difficulty,
  ) {
    final handEstimate = BotDutchStrategy.estimateOpponentForObserver(
      gs,
      observer,
      player,
      difficulty,
    );
    final style =
        BotDutchStrategy.discardTracker.estimateOpponentStyle(player.id);
    final cardsThreat = ((6 - player.hand.length).clamp(0, 5)).toDouble();
    final scoreThreat = (18.0 - handEstimate.estimatedScore).clamp(0.0, 18.0);
    final uncertaintyThreat =
        (1.0 - handEstimate.confidence) * (player.hand.length <= 2 ? 8.0 : 3.5);
    final styleThreat =
        (style.optimization * 1.0 + style.aggression * 0.45) * style.confidence;
    final historyBias = _historicalRankingScore(player) * 0.35;
    final matchCount = BotDutchStrategy.discardTracker.getMatchDiscardCount(
      player.id,
    );
    final observedActions =
        BotDutchStrategy.discardTracker.getObservedDecisionCount(player.id) +
            matchCount;
    final matchRate = observedActions <= 0
        ? 0.0
        : (matchCount / observedActions).clamp(0.0, 1.0);
    final recentMatches = _recentSuccessfulMatchesForPlayer(gs, player);
    final cardVelocity = BotDutchStrategy.discardTracker.getCardVelocity(
      player.id,
      gs.turnCount,
      currentCards: player.hand.length,
      windowTurns: 2,
    );
    final projectedFinishRisk =
        _computeProjectedFinishRiskForPlayer(gs, player);
    final trajectoryClean = _isTrajectoryClean(gs, player);

    double score = cardsThreat * 3.2 +
        scoreThreat * 1.35 +
        styleThreat * 8.0 +
        uncertaintyThreat;
    score += historyBias;
    score += recentMatches * 2.6;
    score += cardVelocity * 2.2;
    score += projectedFinishRisk * 8.5;
    if (observedActions >= 3) {
      score += matchRate * 6.0;
    }
    if (trajectoryClean && (cardVelocity >= 2 || recentMatches >= 2)) {
      score += 1.2;
    } else if (!trajectoryClean) {
      score -= 1.0;
    }

    if (player.isHuman && player.hand.length <= 2) {
      score += 14.0;
    }
    if (BotDutchStrategy.discardTracker.lastActionWasExchange(player.id)) {
      score += 1.8;
    }

    final targetedRecently = player.lastTargetedByPowerTurn >= 0 &&
        (gs.turnCount - player.lastTargetedByPowerTurn) <= 1;
    if (targetedRecently) {
      score -= 1.6;
    }

    return score;
  }

  static double _opponentOptimizationSignal(String playerId) {
    final style =
        BotDutchStrategy.discardTracker.estimateOpponentStyle(playerId);
    return (style.optimization * 0.8 + style.aggression * 0.2).clamp(0.0, 1.0);
  }

  static void _refreshPlatinumKillWindow(GameState gs, Player bot) {
    final tableKey = _tableSignature(gs);
    final tableChanged = tableKey != _platinumKillWindowTableKey;
    final turnReset = gs.turnCount < _platinumKillWindowLastTurn;
    if (tableChanged || turnReset) {
      _platinumKillWindow = null;
      _platinumKillWindowTableKey = tableKey;
    }
    _platinumKillWindowLastTurn = gs.turnCount;

    if (_platinumKillWindow != null &&
        gs.turnCount > _platinumKillWindow!.expiresTurn) {
      _platinumKillWindow = null;
    }

    final candidates = gs.players
        .where((p) => p.id != bot.id && p.hand.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) {
      _platinumKillWindow = null;
      return;
    }

    final scoredTargets = candidates.map((p) {
      final projectedRisk = _computeProjectedFinishRiskForPlayer(gs, p);
      final pressure = _computePlatinumKillPressure(
        gs,
        p,
        projectedFinishRisk: projectedRisk,
      );
      return _ScoredKillTarget(
        player: p,
        pressure: pressure,
        projectedFinishRisk: projectedRisk,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.pressure.compareTo(a.pressure));

    if (scoredTargets.isEmpty) {
      return;
    }

    final best = scoredTargets.first;
    final existing = _getActivePlatinumKillTarget(gs, candidates: candidates);
    if (existing != null) {
      final existingScore =
          scoredTargets.where((e) => e.player.id == existing.id).firstOrNull;
      if (existingScore != null) {
        final existingStillHot = existingScore.player.hand.length <= 2 ||
            existingScore.projectedFinishRisk >= 0.58;
        final challengerClearlyBetter = best.player.id != existing.id &&
            (best.pressure >= (existingScore.pressure * 1.20) ||
                best.projectedFinishRisk >=
                    (existingScore.projectedFinishRisk + 0.18));
        if (existingStillHot && !challengerClearlyBetter) {
          _platinumKillWindow = _PlatinumKillWindow(
            targetId: existing.id,
            expiresTurn: gs.turnCount + 2,
          );
          return;
        }
      }
    }

    final canLockHighCardTarget =
        best.player.hand.length <= 4 || best.projectedFinishRisk >= 0.72;
    final shouldLock = (best.pressure >= 3.2 ||
            best.player.hand.length <= 2 ||
            best.projectedFinishRisk >= 0.62) &&
        canLockHighCardTarget;
    if (shouldLock) {
      _platinumKillWindow = _PlatinumKillWindow(
        targetId: best.player.id,
        expiresTurn: gs.turnCount + 2,
      );
    }
  }

  static double _computePlatinumKillPressure(
    GameState gs,
    Player player, {
    required double projectedFinishRisk,
  }) {
    final cards = player.hand.length;
    final velocity = BotDutchStrategy.discardTracker.getCardVelocity(
      player.id,
      gs.turnCount,
      currentCards: cards,
      windowTurns: 2,
    );
    final recentMatches =
        BotDutchStrategy.discardTracker.getRecentMatchCountInTurns(
      player.id,
      gs.turnCount,
      windowTurns: 3,
    );
    final burstByMatches = BotDutchStrategy.discardTracker.hasMatchBurst(
      player.id,
      gs.turnCount,
      requiredMatches: 2,
      withinTurns: 3,
    );
    final latentLeader = burstByMatches || velocity >= 2;
    final trajectoryClean = _isTrajectoryClean(gs, player);

    double burstRisk = 0.08;
    burstRisk += velocity >= 2
        ? 0.42
        : velocity == 1
            ? 0.16
            : 0.0;
    burstRisk += burstByMatches
        ? 0.30
        : recentMatches >= 2
            ? 0.14
            : 0.0;
    if (cards <= 1) {
      burstRisk += 0.35;
    } else if (cards == 2) {
      burstRisk += 0.25;
    } else if (cards == 3) {
      burstRisk += 0.12;
    }
    burstRisk = burstRisk.clamp(0.0, 1.0);

    final handEstimate =
        BotDutchStrategy.discardTracker.estimateOpponentHand(player.id, cards);
    final avgCardEstimate = cards <= 0
        ? 0.0
        : (handEstimate.estimatedScore / cards).clamp(1.0, 10.0);
    final deltaScoreEst = (velocity * avgCardEstimate).clamp(0.0, 18.0);
    final tempoScore =
        (velocity + (0.35 * deltaScoreEst) + recentMatches).clamp(0.0, 9.0);

    double pressure = tempoScore;
    pressure += burstRisk * 2.6;
    pressure += projectedFinishRisk * 4.2;
    pressure += latentLeader ? 1.5 : 0.0;
    if (trajectoryClean && (velocity >= 2 || recentMatches >= 2)) {
      pressure += 1.2;
    } else if (!trajectoryClean) {
      pressure -= 0.8;
    }
    pressure += cards <= 2
        ? 2.2
        : cards == 3
            ? 0.7
            : 0.0;

    if (cards >= 6) {
      pressure *= 0.40;
    } else if (cards >= 5) {
      pressure *= 0.55;
    } else if (cards == 4) {
      pressure *= 0.78;
    }
    return pressure;
  }

  static double _computeProjectedFinishRiskForPlayer(
    GameState gs,
    Player player,
  ) {
    final cards = player.hand.length;
    final actionsUntilTurn = _actionsUntilNextTurn(gs, player.id);
    final velocity = BotDutchStrategy.discardTracker.getCardVelocity(
      player.id,
      gs.turnCount,
      currentCards: cards,
      windowTurns: 2,
    );
    final recentMatches =
        BotDutchStrategy.discardTracker.getRecentMatchCountInTurns(
      player.id,
      gs.turnCount,
      windowTurns: 3,
    );
    final burstByMatches = BotDutchStrategy.discardTracker.hasMatchBurst(
      player.id,
      gs.turnCount,
      requiredMatches: 2,
      withinTurns: 3,
    );
    final trajectoryClean = _isTrajectoryClean(gs, player);

    double probability = 0.05;
    if (cards <= 1) {
      probability += 0.75;
    } else if (cards == 2) {
      probability += 0.42;
    } else if (cards == 3) {
      probability += 0.18;
    }

    if (velocity >= 2) {
      probability += 0.28;
    } else if (velocity == 1) {
      probability += 0.12;
    }

    if (recentMatches >= 2) {
      probability += 0.22;
    } else if (recentMatches == 1) {
      probability += 0.10;
    }

    if (burstByMatches) {
      probability += 0.16;
    }
    if (actionsUntilTurn <= 1) {
      probability += 0.20;
    } else if (actionsUntilTurn == 2) {
      probability += 0.10;
    } else if (actionsUntilTurn >= 4) {
      probability -= 0.12;
    }

    if (cards >= 6) {
      probability *= 0.32;
    } else if (cards >= 5) {
      probability *= 0.45;
    } else if (cards == 4) {
      probability *= 0.65;
    }
    probability += trajectoryClean ? 0.08 : -0.08;

    return probability.clamp(0.0, 1.0);
  }

  static bool _isTrajectoryClean(GameState gs, Player player) {
    final lowerName = player.name.toLowerCase();
    final limit = gs.actionHistory.length < 12 ? gs.actionHistory.length : 12;
    for (int i = 0; i < limit; i++) {
      final lower = gs.actionHistory[i].toLowerCase();
      if (!lower.contains(lowerName)) continue;
      if (lower.contains('rate son match') ||
          lower.contains('pénalité') ||
          lower.contains('penalite')) {
        return false;
      }
    }
    return true;
  }

  static int _actionsUntilNextTurn(GameState gs, String playerId) {
    final activePlayers = gs.players
        .where((p) => !gs.eliminatedPlayerIds.contains(p.id))
        .toList(growable: false);
    if (activePlayers.isEmpty) return 99;

    final currentId = gs.currentPlayer.id;
    int currentIdx = activePlayers.indexWhere((p) => p.id == currentId);
    if (currentIdx < 0) currentIdx = 0;
    final targetIdx = activePlayers.indexWhere((p) => p.id == playerId);
    if (targetIdx < 0) return 99;

    final distance =
        (targetIdx - currentIdx + activePlayers.length) % activePlayers.length;
    return distance == 0 ? activePlayers.length : distance;
  }

  static Player? _getActivePlatinumKillTarget(
    GameState gs, {
    List<Player>? candidates,
  }) {
    final window = _platinumKillWindow;
    if (window == null) return null;
    if (gs.turnCount > window.expiresTurn) return null;
    final pool = candidates ?? gs.players;
    final target = pool
        .where((p) => p.id == window.targetId && p.hand.isNotEmpty)
        .firstOrNull;
    return target;
  }

  static bool _hasActivePlatinumKillWindow(GameState gs) {
    return _getActivePlatinumKillTarget(gs) != null;
  }

  static String _tableSignature(GameState gs) {
    final ids = gs.players.map((p) => p.id).toList(growable: false)..sort();
    return ids.join('|');
  }

  static int _recentSuccessfulMatchesForPlayer(
    GameState gs,
    Player player, {
    int lookback = 14,
  }) {
    final playerName = player.name.trim().toLowerCase();
    final maxEntries =
        gs.actionHistory.length < lookback ? gs.actionHistory.length : lookback;
    int count = 0;
    for (int i = 0; i < maxEntries; i++) {
      final lower = gs.actionHistory[i].toLowerCase();
      if (lower.contains('match !') && lower.contains(playerName)) {
        count++;
      }
    }
    return count;
  }

  static int _humanValetCooldownTurns(Player bot, BotDifficulty difficulty) {
    if (bot.botSkillLevel == BotSkillLevel.bronze ||
        _isBronzeDifficulty(difficulty)) {
      return _bronzeHumanValetCooldownTurns;
    }
    if (bot.botSkillLevel == BotSkillLevel.silver ||
        _isSilverDifficulty(difficulty)) {
      return _silverHumanValetCooldownTurns;
    }
    return 0;
  }

  static Set<String> _protectedHumanIds(
    GameState gs,
    List<Player> candidates,
    int cooldownTurns,
  ) {
    if (cooldownTurns <= 0) return const <String>{};
    return candidates
        .where((p) =>
            p.isHuman &&
            p.lastBronzeValetTargetTurn >= 0 &&
            (gs.turnCount - p.lastBronzeValetTargetTurn) < cooldownTurns)
        .map((p) => p.id)
        .toSet();
  }
}

class _PowerUseConclusions {
  final bool hasImmediateThreat;
  final bool isOffensive;
  final bool shouldUsePower;
  final bool forceUsePower7;
  final bool isSilverPower7;
  final bool shouldSkipSilverPower7ByDizziness;
  final double passiveSkipChance;

  const _PowerUseConclusions({
    required this.hasImmediateThreat,
    required this.isOffensive,
    required this.shouldUsePower,
    required this.forceUsePower7,
    required this.isSilverPower7,
    required this.shouldSkipSilverPower7ByDizziness,
    required this.passiveSkipChance,
  });
}

class _PlatinumKillWindow {
  final String targetId;
  final int expiresTurn;

  const _PlatinumKillWindow({
    required this.targetId,
    required this.expiresTurn,
  });
}

class _ScoredKillTarget {
  final Player player;
  final double pressure;
  final double projectedFinishRisk;

  const _ScoredKillTarget({
    required this.player,
    required this.pressure,
    required this.projectedFinishRisk,
  });
}
