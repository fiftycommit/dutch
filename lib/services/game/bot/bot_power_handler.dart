import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import '../../../utils/action_history_messages.dart';
import '../../learning/ai_telemetry_service.dart';
import '../../logging/game_logger_service.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_memory_manager.dart';
import 'bot_threat_analyzer.dart';
import 'bot_dutch_strategy.dart';
import 'bot_gossip_service.dart';
import 'bot_personality.dart';
import 'discard_tracker.dart';
import 'duel_tuning.dart';
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
  // BRONZE : Compteur partagé des Valets sur l'humain (max 2 par manche)
  // ═══════════════════════════════════════════════════════════════════════════
  static const int _maxBronzeValetsOnHuman = 2;
  static int _bronzeValetsOnHumanThisRound = 0;
  static String _lastHumanIdForValetCount = '';

  /// Reset le compteur de Valets Bronze sur l'humain (nouvelle manche)
  static void resetBronzeValetCount() {
    _bronzeValetsOnHumanThisRound = 0;
    _lastHumanIdForValetCount = '';
  }

  /// Vérifie si les bots Bronze peuvent encore Valet l'humain
  static bool _canBronzeValetHuman(GameState gs) {
    final human = gs.players.where((p) => p.isHuman).firstOrNull;
    if (human == null) return false;
    // Reset si nouvel humain (nouvelle partie)
    if (_lastHumanIdForValetCount != human.id) {
      _bronzeValetsOnHumanThisRound = 0;
      _lastHumanIdForValetCount = human.id;
    }
    return _bronzeValetsOnHumanThisRound < _maxBronzeValetsOnHuman;
  }

  /// Incrémente le compteur de Valets sur l'humain
  static void _recordBronzeValetOnHuman() {
    _bronzeValetsOnHumanThisRound++;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRONZE : Mémoire du pouvoir 10 pour offrir un match à l'humain
  // ═══════════════════════════════════════════════════════════════════════════
  /// Association entre `botId` et l'index de carte à défausser
  /// pour offrir un match.
  static final Map<String, int> _pendingMatchFromSpy = {};

  /// Le bot Bronze a-t-il une carte à défausser pour offrir un match ?
  static int? getPendingMatchIndex(String botId) => _pendingMatchFromSpy[botId];

  /// Enregistre l'index de la carte à défausser pour match
  static void setPendingMatchIndex(String botId, int index) {
    _pendingMatchFromSpy[botId] = index;
  }

  /// Efface la mémoire du match pending (après défausse ou nouvelle manche)
  static void clearPendingMatch(String botId) {
    _pendingMatchFromSpy.remove(botId);
  }

  /// Reset toutes les mémoires Bronze pour nouvelle manche
  static void resetBronzeMemory() {
    _bronzeValetsOnHumanThisRound = 0;
    _lastHumanIdForValetCount = '';
    _pendingMatchFromSpy.clear();
  }

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
    if (gameState.phase != GamePhase.specialPower ||
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
      _skipPower(
        gameState,
        bot,
        reason: 'Argent étourdi: skip pouvoir 7 après pression récente',
      );
      return;
    }

    // Bronze "bête": rate souvent l'opportunité d'un pouvoir non critique.
    if (powerConclusions.passiveSkipChance > 0 &&
        !powerConclusions.hasImmediateThreat &&
        !powerConclusions.forceUsePower7 &&
        !powerConclusions.isSilverPower7 &&
        !powerConclusions.isOffensive &&
        _random.nextDouble() < powerConclusions.passiveSkipChance) {
      _skipPower(
        gameState,
        bot,
        reason: 'Inertie volontaire: pas de menace immédiate',
      );
      return;
    }

    if (!powerConclusions.shouldUsePower) {
      _skipPower(
        gameState,
        bot,
        reason: 'Contexte défavorable: fenêtre pouvoir fermée',
      );
      return;
    }

    // TÉLÉMÉTRIE : snapshot avantage AVANT le pouvoir
    final advantageBefore = _calculateTableAdvantage(
      gameState,
      bot,
      difficulty: difficulty,
    );

    bool powerExecuted = true;

    if (val == '7') {
      _usePower7(gameState, bot, difficulty);
    } else if (val == '10') {
      await _usePower10(gameState, bot, difficulty, context,
          personality: personality);
    } else if (val == 'V') {
      powerExecuted = await _usePowerValet(gameState, bot, difficulty, context,
          personality: personality);
    } else if (val == 'JOKER') {
      powerExecuted = await _usePowerJoker(gameState, bot, difficulty, context,
          personality: personality);
    }

    if (!powerExecuted) {
      _skipPower(
        gameState,
        bot,
        reason: 'Aucune cible valide au moment de l’exécution',
      );
      return;
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

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory(ActionHistoryMessages.powerUsed(bot.name));
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
    final isAdvancedPowerBot = isGold || isPlatinum;

    final hasImmediateThreat = report.hasOpponentWithOneCard ||
        report.minOpponentCards <= 2 ||
        (gameState.dutchCallerId != null && gameState.dutchCallerId != bot.id);

    final isOffensive = powerValue == 'V' || powerValue == 'JOKER';
    final hasUnknown = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;
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
    if (isAdvancedPowerBot) {
      // Règle métier: plus de "moment tranquille" sur les pouvoirs en Or/Platine.
      // Ils jouent toujours 7/10/V/JOKER quand le pouvoir est disponible.
      shouldUsePower = true;
    }
    final forceUsePower7 = powerValue == '7' && (isGold || isPlatinum);
    final isSilverPower7 = isSilver && powerValue == '7';
    final shouldSkipSilverPower7ByDizziness =
        isSilverPower7 && _shouldSilverSkipPower7(gameState, bot);

    final isDuel = gameState.players.length == 2;
    final passiveSkipChance = isBronze
        // Bronze skip souvent les pouvoirs, SAUF :
        // - Le 10 (spy) qui est intuitif même pour un débutant
        // - En 1v1 où les pouvoirs ont plus de valeur
        ? (powerValue == '10'
            ? 0.15
            : isDuel
                ? 0.55
                : 0.92)
        : isSilver
            // Argent reste distrait sur les pouvoirs "confort",
            // mais n'ignore pas arbitrairement un espionnage 10.
            ? (powerValue == '10' ? 0.0 : 0.26)
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
    final isHardcore = difficulty.name == "Difficile" ||
        difficulty.name == "Or" ||
        difficulty.name == "Platine" ||
        difficulty.name == "Hard" ||
        difficulty.name == "Insane" ||
        difficulty.name == "Nightmare" ||
        difficulty.name == "Impossible";

    int idx;
    if (isHardcore) {
      final publicSignal = _analyzePublicPowerSignal(target, difficulty);
      final myPerceived = _estimateBotPerceivedScore(bot);
      final shouldProbeDutchWeakness =
          publicSignal.readyThreat >= 0.55 || myPerceived <= 4;
      final shouldSetupFutureValet =
          !shouldProbeDutchWeakness && _canPlanValetSteal(bot, difficulty);
      if (shouldProbeDutchWeakness) {
        final alreadySpied = bot.getSpiedCards(target.id);
        // Si l'adversaire semble prêt à Dutch, le 10 sert d'abord à trouver
        // une carte qui casse sa fenêtre, donc on vise en priorité un slot
        // publiquement faible / peu optimisé plutôt qu'un slot "fort".
        final weakIdx = BotDutchStrategy.discardTracker
                .pickLikelyWeakUntouchedIndex(
                  target.id,
                  target.hand.length,
                ) ??
            (myPerceived <= 4
                ? null
                : BotDutchStrategy.discardTracker.pickStoppedTouchingIndex(
                    target.id,
                    target.hand.length,
                  ));
        final isAlreadyKnown = weakIdx != null &&
            alreadySpied != null &&
            alreadySpied.containsKey(weakIdx);
        if (weakIdx != null && !isAlreadyKnown) {
          idx = weakIdx;
        } else if (_random.nextDouble() < 0.7) {
          idx = _random.nextBool() ? 0 : target.hand.length - 1;
        } else {
          idx = _random.nextInt(target.hand.length);
        }
      } else if (shouldSetupFutureValet) {
        final alreadySpied = bot.getSpiedCards(target.id);
        final strongIdx = BotDutchStrategy.discardTracker
                .pickUntouchedInitiallyRevealedIndex(
                  target.id,
                  target.hand.length,
                ) ??
            BotDutchStrategy.discardTracker.pickStoppedTouchingIndex(
              target.id,
              target.hand.length,
            ) ??
            BotDutchStrategy.discardTracker.pickLikelyStrongIndex(
              target.id,
              target.hand.length,
            );
        final isAlreadyKnown = strongIdx != null &&
            alreadySpied != null &&
            alreadySpied.containsKey(strongIdx);
        if (strongIdx != null && !isAlreadyKnown) {
          idx = strongIdx;
        } else {
          final fallbackWeakIdx = BotDutchStrategy.discardTracker
              .pickLikelyWeakUntouchedIndex(target.id, target.hand.length);
          final weakAlreadyKnown = fallbackWeakIdx != null &&
              alreadySpied != null &&
              alreadySpied.containsKey(fallbackWeakIdx);
          if (fallbackWeakIdx != null && !weakAlreadyKnown) {
            idx = fallbackWeakIdx;
          } else {
            idx = _random.nextInt(target.hand.length);
          }
        }
      } else {
        // Par défaut, on cherche une faiblesse ou un slot encore flou.
        final weakIdx = BotDutchStrategy.discardTracker
            .pickLikelyWeakUntouchedIndex(target.id, target.hand.length);
        final alreadySpied = bot.getSpiedCards(target.id);
        final isAlreadyKnown = weakIdx != null &&
            alreadySpied != null &&
            alreadySpied.containsKey(weakIdx);

        if (weakIdx != null && !isAlreadyKnown) {
          idx = weakIdx;
        } else if (_random.nextDouble() < 0.7) {
          idx = _random.nextBool() ? 0 : target.hand.length - 1;
        } else {
          idx = _random.nextInt(target.hand.length);
        }
      }
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

      // BRONZE BIENVEILLANT : Si le bot a espionné une carte identique à une
      // des siennes, il mémorise l'index pour la défausser au prochain tour
      // → offre un match à l'humain
      for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
        final known = bot.mentalMap[i];
        if (known != null && known.value == spiedCard.value) {
          // Le bot a la même valeur → défausser cette carte au prochain tour
          setPendingMatchIndex(bot.id, i);
          break;
        }
      }
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

      final publicTargets = List<Player>.from(opponents)
        ..sort((a, b) {
          final sa = _analyzePublicPowerSignal(a, difficulty);
          final sb = _analyzePublicPowerSignal(b, difficulty);
          final aScore = (sa.readyThreat * 3.0) +
              ((4 - a.hand.length).clamp(0, 3) * 0.22) -
              (sa.vulnerability * 0.5);
          final bScore = (sb.readyThreat * 3.0) +
              ((4 - b.hand.length).clamp(0, 3) * 0.22) -
              (sb.vulnerability * 0.5);
          return bScore.compareTo(aScore);
        });
      if (publicTargets.isNotEmpty) {
        final topSignal = _analyzePublicPowerSignal(publicTargets.first, difficulty);
        if (topSignal.readyThreat >= 0.58) {
          return publicTargets.first;
        }
      }
    }

    if (_isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty)) {
      final canPlanValet = _canPlanValetSteal(bot, difficulty);
      final publicTargets = List<Player>.from(opponents)
        ..sort((a, b) {
          final sa = _analyzePublicPowerSignal(a, difficulty);
          final sb = _analyzePublicPowerSignal(b, difficulty);
          final aSetup =
              canPlanValet ? (sa.readyThreat * 3.2) + (sa.vulnerability * 0.4) : 0.0;
          final bSetup =
              canPlanValet ? (sb.readyThreat * 3.2) + (sb.vulnerability * 0.4) : 0.0;
          final aThreat = _adaptivePlatinumThreatScore(gs, bot, a, difficulty) +
              aSetup +
              (sa.readyThreat * 8.0) -
              (sa.vulnerability * 1.8);
          final bThreat = _adaptivePlatinumThreatScore(gs, bot, b, difficulty) +
              bSetup +
              (sb.readyThreat * 8.0) -
              (sb.vulnerability * 1.8);
          return bThreat.compareTo(aThreat);
        });
      if (publicTargets.isNotEmpty) {
        final topSignal = _analyzePublicPowerSignal(publicTargets.first, difficulty);
        if (topSignal.readyThreat >= 0.48 || publicTargets.first.hand.length <= 2) {
          return publicTargets.first;
        }
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

  static Future<bool> _usePowerValet(
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
    if (targets == null) {
      var duelPlan = _buildDuelValetPlan(gs, bot, difficulty);
      if (duelPlan == null &&
          (_isGoldDifficulty(difficulty) ||
              _isPlatinumDifficulty(difficulty))) {
        final duelOpponents = gs.players
            .where((p) => p.id != bot.id && p.hand.isNotEmpty)
            .toList(growable: false);
        if (duelOpponents.length == 1 && bot.hand.isNotEmpty) {
          final opponent = duelOpponents.first;
          final ownIdx = _chooseOwnCardForDuelDisruption(bot);
          final oppIdx = _chooseOpponentCardForDuelDisruption(bot, opponent);
          final thresholdTrace = _computeDuelValetThresholdTrace(gs, opponent);
          _logDuelValetDecision(
            bot,
            decision: 'VALET_DUEL_FORCE_USE_NO_CALM_SKIP',
            context: {
              'opponent': opponent.name,
              'ownIndex': ownIdx,
              'opponentIndex': oppIdx,
              'reason': 'advanced_bot_no_calm_skip',
              ...thresholdTrace.toLogContext(),
            },
          );
          duelPlan = _DuelValetPlan(
            opponent: opponent,
            ownCardIndex: ownIdx,
            opponentCardIndex: oppIdx,
          );
        }
      }
      if (duelPlan == null) return false;

      final opponent = duelPlan.opponent;
      final ownIdx = duelPlan.ownCardIndex;
      final oppIdx = duelPlan.opponentCardIndex;

      if (opponent.id != bot.id) {
        opponent.lastTargetedByPowerTurn = gs.turnCount;
      }

      GameLogic.swapCards(gs, opponent, oppIdx, bot, ownIdx);

      if (opponent.isHuman) {
        await power_notifications.showBotSwapNotification(
          context,
          bot,
          opponent.name,
          oppIdx,
          swapPartnerName: bot.name,
          receivedCardPosition: ownIdx + 1,
        );
      }
      return true;
    }

    var (target1, target2) = targets;
    if (_isPlatinumDifficulty(difficulty)) {
      final aggressivePlan = _resolvePlatinumValetAggressivePlan(
        gs,
        bot,
        target1,
        target2,
        difficulty,
      );
      if (aggressivePlan != null) {
        target1 = aggressivePlan.$1;
        target2 = aggressivePlan.$2;
      }
    }
    if (target1.hand.isEmpty || target2.hand.isEmpty) return false;

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
    return true;
  }

  /// Choisit DEUX cibles pour le pouvoir Valet (pas le bot lui-même)
  /// Bronze: comportement chaotique.
  /// Argent: ciblage menace existant.
  /// Or/Platine: cible les 2 joueurs les plus forts.
  /// Si choix ambigu, inclut un humain dans les cibles.
  /// Protection anti-focus humain:
  /// - Bronze: JAMAIS l'humain sauf s'il a ≤ 2 cartes ET quota de 2 Valets/manche pas atteint.
  /// - Argent: max 1 ciblage humain / 2 tours de table.
  static (Player, Player)? _chooseValetTargets(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    final isBronzeValet = bot.botSkillLevel == BotSkillLevel.bronze ||
        _isBronzeDifficulty(difficulty);

    if (isBronzeValet) {
      // BRONZE : Nouvelle logique bienveillante
      // L'humain n'est ciblable QUE si :
      // 1. Il a ≤ 2 cartes (dangereux, proche de Dutch)
      // 2. Le quota de 2 Valets/manche n'est pas atteint
      final human = gs.players.where((p) => p.isHuman).firstOrNull;
      final humanIsDangerous = human != null && human.hand.length <= 2;
      final canTargetHuman = humanIsDangerous && _canBronzeValetHuman(gs);

      // Construire le pool de cibles (exclure l'humain sauf s'il est ciblable)
      final allCandidates =
          gs.players.where((p) => p.hand.isNotEmpty).toList(growable: false);
      if (allCandidates.length < 2) return null;

      // Pool sans l'humain (sauf s'il est ciblable)
      List<Player> pool = allCandidates
          .where((p) => !p.isHuman || canTargetHuman)
          .toList(growable: false);
      
      if (pool.length < 2) {
        // Pas assez de cibles sans l'humain → skip le Valet
        return null;
      }

      final first = pool[_random.nextInt(pool.length)];
      List<Player> secondPool =
          pool.where((p) => p.id != first.id).toList(growable: false);
      if (secondPool.isEmpty) return null;

      final second = secondPool[_random.nextInt(secondPool.length)];
      
      // Si l'humain est ciblé, incrémenter le compteur
      if (first.isHuman || second.isHuman) {
        _recordBronzeValetOnHuman();
      }
      
      return (first, second);
    }

    final humanCooldownTurns = _humanValetCooldownTurns(bot, difficulty);
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

    final canUseIndexIntel =
        _isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty);
    if (canUseIndexIntel) {
      // Priorité 1 : index initialement révélé et jamais échangé depuis le départ.
      final untouchedRevealedIdx = BotDutchStrategy.discardTracker
          .pickUntouchedInitiallyRevealedIndex(target.id, target.hand.length);
      if (untouchedRevealedIdx != null) return untouchedRevealedIdx;

      // Priorité 2 : index que le joueur a amélioré puis arrêté de toucher.
      final stoppedTouchingIdx = BotDutchStrategy.discardTracker
          .pickStoppedTouchingIndex(target.id, target.hand.length);
      if (stoppedTouchingIdx != null) return stoppedTouchingIdx;

      // Priorité 3 : heuristique sur fréquence d'échange et plafond estimé.
      final likelyStrongIdx = BotDutchStrategy.discardTracker
          .pickLikelyStrongIndex(target.id, target.hand.length);
      if (likelyStrongIdx != null) return likelyStrongIdx;
    }

    // Sans info fiable, le bot ne voit pas les cartes cachées de la cible.
    return _random.nextInt(target.hand.length);
  }

  static _DuelValetPlan? _buildDuelValetPlan(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    bool logDecision = true,
  }) {
    final opponents =
        gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.length != 1) return null;
    if (!(_isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty))) {
      return null;
    }

    final opponent = opponents.first;
    final antiHumanLikeOpponent =
        opponent.isHuman || opponent.botBehavior == BotBehavior.moi;
    if (bot.hand.isEmpty || opponent.hand.isEmpty) return null;
    final duel = true;
    final hasUnknownOwn = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;
    final thresholdTrace = _computeDuelValetThresholdTrace(gs, opponent);
    final badCardThreshold = thresholdTrace.finalThreshold;

    // Si le bot connaît toute sa main et qu'elle est déjà "bonne" pour
    // le contexte courant, il skip le Valet — SAUF en duel Platine où
    // le swap a toujours une valeur de déstabilisation.
    if (!hasUnknownOwn && !(_isPlatinumDifficulty(difficulty) && duel)) {
      final worstKnown = _worstKnownCardPoints(bot);
      if (worstKnown >= 0 && worstKnown < badCardThreshold) {
        if (!antiHumanLikeOpponent) {
          if (logDecision) {
            _logDuelValetDecision(
              bot,
              decision: 'VALET_DUEL_SKIP_ALL_KNOWN_GOOD',
              context: {
                'opponent': opponent.name,
                'knownCards': bot.knownCardCount,
                'handCards': bot.hand.length,
                'worstKnown': worstKnown,
                ...thresholdTrace.toLogContext(),
              },
            );
          }
          return null;
        }
      }
    }

    // Mode "no mercy": en duel, si le bot ne connaît pas toute sa main,
    // il échange immédiatement pour déstabiliser l'adversaire:
    // - il donne une inconnue en priorité (sinon sa pire connue),
    // - il récupère si possible une carte adverse supposée basse (espionnée),
    //   sinon une carte aléatoire adverse.
    //
    // EXCEPTION: En début de partie (peu de cartes connues), le bot devrait
    // d'abord explorer ses inconnues avant de les donner. Donner une inconnue
    // au tour 0 risque d'envoyer un Joker ou As à l'adversaire.
    if (hasUnknownOwn) {
      final ownIdx = _chooseOwnCardForDuelDisruption(bot);
      final oppIdx = _chooseOpponentCardForDuelDisruption(bot, opponent);
      if (logDecision) {
        _logDuelValetDecision(
          bot,
          decision: 'VALET_DUEL_USE_UNKNOWN_DISRUPTION',
          context: {
            'opponent': opponent.name,
            'ownIndex': ownIdx,
            'opponentIndex': oppIdx,
            'knownCards': bot.knownCardCount,
            'handCards': bot.hand.length,
            ...thresholdTrace.toLogContext(),
          },
        );
      }
      return _DuelValetPlan(
        opponent: opponent,
        ownCardIndex: ownIdx,
        opponentCardIndex: oppIdx,
      );
    }


    final report = BotThreatAnalyzer.analyzeOpponents(
      gs,
      bot,
      difficulty: difficulty,
    );
    final spied = bot.getSpiedCards(opponent.id);
    final opponentEstimate = BotDutchStrategy.estimateOpponentForObserver(
        gs, bot, opponent, difficulty);
    final publicSignal = _analyzePublicPowerSignal(opponent, difficulty);
    final myPerceived = _estimateBotPerceivedScore(bot);
    final behind = myPerceived > opponentEstimate.estimatedScore;
    final isMoiStyle = bot.botBehavior == BotBehavior.moi;
    final underPressure = report.minOpponentCards <= 2 ||
        report.hasOpponentWithOneCard ||
        report.bestOpponentScore <= (myPerceived + 1.5) ||
        publicSignal.readyThreat >= 0.58;

    final opponentVelocity = BotDutchStrategy.discardTracker.getCardVelocity(
      opponent.id,
      gs.turnCount,
      currentCards: opponent.hand.length,
      windowTurns: 2,
    );
    final opponentBurst = BotDutchStrategy.discardTracker.hasMatchBurst(
      opponent.id,
      gs.turnCount,
      requiredMatches: 2,
      withinTurns: 3,
    );
    final raceRisk = opponent.hand.length <= 2 ||
        opponentVelocity >= 2 ||
        opponentBurst ||
        publicSignal.readyThreat >= 0.60;
    final earlyOpeningWindow =
        gs.turnCount <= 1 || gs.actionCount <= (gs.players.length * 2);
    final canOpeningDisruption = (isMoiStyle || antiHumanLikeOpponent) &&
        duel &&
        hasUnknownOwn &&
        opponent.hand.length >= 3 &&
        earlyOpeningWindow;
    final canEntropySabotage = hasUnknownOwn &&
        raceRisk &&
        opponent.hand.length <= 2 &&
        (underPressure || behind);

    int bestOwnIdx = 0;
    int bestOppIdx = 0;
    double bestGain = -9999.0;
    bool bestOwnKnown = false;
    bool bestOppKnown = false;

    // Récupérer les positions adverses déjà ciblées par un swap précédent.
    // Re-cibler la même position est risqué : l'adversaire a probablement
    // déjà remplacé cette carte, on risque de récupérer pire.
    final botSwapCounts = BotDutchStrategy.discardTracker
        .getVisibleSwapByIndexCount(opponent.id, opponent.hand.length);

    for (int ownIdx = 0; ownIdx < bot.hand.length; ownIdx++) {
      final ownKnown = _isKnownCardForBot(bot, ownIdx);
      final ownOut = _estimateOwnCardValueForDuelValet(bot, ownIdx);

      for (int oppIdx = 0; oppIdx < opponent.hand.length; oppIdx++) {
        final knownOpp =
            (spied != null && spied.containsKey(oppIdx)) ? spied[oppIdx] : null;
        final oppKnown = knownOpp != null;
        final oppOut = knownOpp != null ? knownOpp.points.toDouble() : 6.5;

        // Duel sous pression: même unknown↔unknown peut être utile pour
        // injecter de l'entropie et casser le mapping adverse.
        if (!ownKnown &&
            !oppKnown &&
            !canEntropySabotage &&
            !canOpeningDisruption) {
          continue;
        }

        // Gain relatif: on veut maximiser (carte donnée - carte reçue).
        double gain = ownOut - oppOut;

        // Pénalité pour recibler un index déjà swappé par le bot.
        // L'adversaire a probablement remplacé cette carte, on ne sait plus
        // ce qui s'y trouve → l'estimation à 6.5 est trop optimiste.
        final previousSwaps = botSwapCounts[oppIdx] ?? 0;
        if (previousSwaps > 0 && !oppKnown) {
          gain -= 2.0 * previousSwaps;
        }
        if (behind) {
          gain += ownOut * 0.35;
          gain -= oppOut * 0.10;
        } else {
          gain += (ownOut - 4.0) * 0.10;
        }
        if (raceRisk && ownKnown && ownOut >= badCardThreshold) {
          gain += 1.5;
        }
        if (raceRisk && oppKnown && oppOut <= 3) {
          gain += 0.8;
        }

        if (gain > bestGain) {
          bestGain = gain;
          bestOwnIdx = ownIdx;
          bestOppIdx = oppIdx;
          bestOwnKnown = ownKnown;
          bestOppKnown = oppKnown;
        }
      }
    }

    if (bestGain <= -9000) return null;

    final hasKnownPayload = _hasKnownHighPayloadForDuelValet(
      bot,
      minPoints: badCardThreshold,
    );

    // Pas d'échange "gratuit":
    // - on le fait en anti-burst quand la course devient fatale,
    // - ou en sabotage clair avec payload connu (grosse carte envoyée).
    final shouldSwapForRace = raceRisk &&
        (underPressure ||
            behind ||
            (isMoiStyle && hasKnownPayload) ||
            antiHumanLikeOpponent);
    final shouldSwapForSabotage = (behind && hasKnownPayload) ||
        (isMoiStyle &&
            hasKnownPayload &&
            (underPressure || opponent.hand.length <= bot.hand.length)) ||
        (antiHumanLikeOpponent && (hasKnownPayload || bestGain >= 0.2)) ||
        (publicSignal.vulnerability >= 0.50 && bestGain >= -0.10);
    final hasInformationEdge = bestOwnKnown || bestOppKnown;
    final shouldSwapForEntropy =
        canEntropySabotage && !hasInformationEdge && bestGain >= -0.05;
    final shouldSwapForOpeningDisruption =
        canOpeningDisruption && !hasInformationEdge && bestGain >= -0.05;
    final sabotageGainFloor = antiHumanLikeOpponent
        ? DuelTuning.duelHumanLikeSabotageGainFloor
        : (isMoiStyle ? 0.2 : 0.8);
    final unknownGainFloor = antiHumanLikeOpponent
        ? DuelTuning.duelHumanLikeUnknownGainFloor
        : (isMoiStyle ? 0.7 : 1.2);

    // CORRECTION 1v1: Échange offensif proactif en duel.
    // En 1v1, le Valet est une arme de déstabilisation même sans race risk.
    // Un joueur humain échange même une carte inconnue pour déstabiliser
    // l'adversaire — le bot devrait faire pareil. On autorise le swap dès que
    // le gain n'est pas catastrophique (>= -2.0). La déstabilisation elle-même
    // a de la valeur: l'adversaire perd sa carte connue, reçoit une inconnue.
    final shouldSwapForDuelDisruption = duel &&
        _isPlatinumDifficulty(difficulty) &&
        bestGain >= -2.0;

    final shouldSwap = hasInformationEdge &&
            (shouldSwapForRace ||
                (shouldSwapForSabotage && bestGain >= sabotageGainFloor) ||
                (hasUnknownOwn && bestGain >= unknownGainFloor)) ||
        shouldSwapForEntropy ||
        shouldSwapForOpeningDisruption ||
        shouldSwapForDuelDisruption;

    if (!shouldSwap) {
      if (logDecision) {
        _logDuelValetDecision(
          bot,
          decision: 'VALET_DUEL_SKIP_NO_EDGE',
          context: {
            'opponent': opponent.name,
            'behind': behind,
            'underPressure': underPressure,
            'raceRisk': raceRisk,
            'hasKnownPayload': hasKnownPayload,
            'hasInformationEdge': hasInformationEdge,
            'bestGain': bestGain.toStringAsFixed(3),
            'bestOwnKnown': bestOwnKnown,
            'bestOppKnown': bestOppKnown,
            'swapForRace': shouldSwapForRace,
            'swapForSabotage': shouldSwapForSabotage,
            'swapForEntropy': shouldSwapForEntropy,
            'swapForOpening': shouldSwapForOpeningDisruption,
            'swapForDuelDisruption': shouldSwapForDuelDisruption,
            ...thresholdTrace.toLogContext(),
          },
        );
      }
      return null;
    }

    if (logDecision) {
      _logDuelValetDecision(
        bot,
        decision: 'VALET_DUEL_USE_CONTEXTUAL_SWAP',
        context: {
          'opponent': opponent.name,
          'ownIndex': bestOwnIdx,
          'opponentIndex': bestOppIdx,
          'behind': behind,
          'underPressure': underPressure,
          'raceRisk': raceRisk,
          'hasKnownPayload': hasKnownPayload,
          'hasInformationEdge': hasInformationEdge,
          'bestGain': bestGain.toStringAsFixed(3),
          'bestOwnKnown': bestOwnKnown,
          'bestOppKnown': bestOppKnown,
          'swapForRace': shouldSwapForRace,
          'swapForSabotage': shouldSwapForSabotage,
          'swapForEntropy': shouldSwapForEntropy,
          'swapForOpening': shouldSwapForOpeningDisruption,
          'swapForDuelDisruption': shouldSwapForDuelDisruption,
          ...thresholdTrace.toLogContext(),
        },
      );
    }
    return _DuelValetPlan(
      opponent: opponent,
      ownCardIndex: bestOwnIdx,
      opponentCardIndex: bestOppIdx,
    );
  }

  static double _estimateOwnCardValueForDuelValet(Player bot, int ownIdx) {
    if (ownIdx >= 0 && ownIdx < bot.mentalMap.length) {
      final known = bot.mentalMap[ownIdx];
      if (known != null) return known.points.toDouble();
    }

    final quality = bot.getUnknownCardHintQuality(ownIdx);
    final confidence = bot.getUnknownCardHintConfidence(ownIdx);
    if (quality != null && confidence != null) {
      // quality > 0 => carte probablement bonne (basse), quality < 0 => mauvaise (haute)
      final estimated = 6.5 + ((-quality) * 5.0 * confidence);
      return estimated.clamp(0.0, 13.0);
    }

    return 6.5;
  }

  static int _chooseOwnCardForDuelDisruption(Player bot) {
    final unknown = BotMemoryManager.getUnknownIndices(bot);
    if (unknown.isNotEmpty) {
      return unknown.first;
    }

    int worstIdx = 0;
    int worstPoints = -1;
    for (int i = 0; i < bot.hand.length; i++) {
      final known = (i < bot.mentalMap.length) ? bot.mentalMap[i] : null;
      if (known == null) continue;
      if (known.points > worstPoints) {
        worstPoints = known.points;
        worstIdx = i;
      }
    }
    return worstIdx.clamp(0, bot.hand.length - 1);
  }

  static int _chooseOpponentCardForDuelDisruption(Player bot, Player opponent) {
    if (opponent.hand.length <= 1) return 0;

    final spied = bot.getSpiedCards(opponent.id);
    if (spied != null && spied.isNotEmpty) {
      final knownEntries = spied.entries
          .where((e) => e.key >= 0 && e.key < opponent.hand.length)
          .toList(growable: false);
      if (knownEntries.isNotEmpty) {
        knownEntries.sort((a, b) => a.value.points.compareTo(b.value.points));
        return knownEntries.first.key;
      }
    }

    // Priorité 1 : index initialement révélé et jamais échangé depuis le départ.
    final untouchedRevealedIdx = BotDutchStrategy.discardTracker
        .pickUntouchedInitiallyRevealedIndex(opponent.id, opponent.hand.length);
    if (untouchedRevealedIdx != null) return untouchedRevealedIdx;

    // Priorité 2 : index que le joueur a amélioré puis arrêté de toucher.
    final stoppedTouchingIdx = BotDutchStrategy.discardTracker
        .pickStoppedTouchingIndex(opponent.id, opponent.hand.length);
    if (stoppedTouchingIdx != null) return stoppedTouchingIdx;

    // Priorité 3 : heuristique sur fréquence d'échange et plafond estimé.
    final likelyStrongIdx = BotDutchStrategy.discardTracker
        .pickLikelyStrongIndex(opponent.id, opponent.hand.length);
    if (likelyStrongIdx != null) return likelyStrongIdx;

    return _random.nextInt(opponent.hand.length);
  }

  static bool _isKnownCardForBot(Player bot, int index) {
    if (index < 0 || index >= bot.mentalMap.length) return false;
    return bot.mentalMap[index] != null;
  }

  static bool _hasKnownHighPayloadForDuelValet(
    Player bot, {
    int minPoints = 10,
  }) {
    for (final card in bot.mentalMap) {
      if (card == null) continue;
      if (card.points >= minPoints) return true;
    }
    return false;
  }

  static int _worstKnownCardPoints(Player bot) {
    int worst = -1;
    for (int i = 0; i < bot.hand.length; i++) {
      final known = (i < bot.mentalMap.length) ? bot.mentalMap[i] : null;
      if (known == null) continue;
      if (known.points > worst) {
        worst = known.points;
      }
    }
    return worst;
  }

  static _DuelValetThresholdTrace _computeDuelValetThresholdTrace(
    GameState gs,
    Player opponent,
  ) {
    final tracker = BotDutchStrategy.discardTracker;
    final readTier = OpponentReadTier.strong;
    tracker.observePublicMemorizedIndices(
      opponent.id,
      opponent.memorizedCardIndices,
      opponent.hand.length,
    );
    final decisions = tracker.getObservedDecisionCount(opponent.id);
    final exchangeRate = tracker.getExchangeRate(opponent.id);
    final avgInstantDiscard =
        tracker.getAverageDrawnDiscardPoints(opponent.id, lookback: 6);
    final avgExchangeDiscard =
        tracker.getAverageExchangeDiscardPoints(opponent.id, lookback: 6);
    final lowInstantRate =
        tracker.getLowDrawnDiscardRate(opponent.id, maxPoints: 4, lookback: 6);
    final recentLowInstant = tracker.hasRecentLowDrawnDiscard(
      opponent.id,
      maxPoints: 4,
      lookback: 4,
    );
    final style = tracker.estimateOpponentStyle(
      opponent.id,
      readTier: readTier,
    );
    final estimate = tracker.estimateOpponentHand(
      opponent.id,
      opponent.hand.length,
      readTier: readTier,
    );
    final indexIntel = tracker.estimateOpponentIndexIntel(
      opponent.id,
      opponent.hand.length,
      readTier: readTier,
    );
    final powerUses = tracker.getPowerUseCount(opponent.id);
    final recentPowerUses = tracker.getRecentPowerUseCountInTurns(
      opponent.id,
      gs.turnCount,
      windowTurns: 4,
    );
    final deckLowChance = tracker.probabilityDrawAtOrBelow(4);
    final deckExpectedPoints = tracker.expectedDrawnPoints();
    final targetedRecently = opponent.lastTargetedByPowerTurn >= 0 &&
        (gs.turnCount - opponent.lastTargetedByPowerTurn) <= 2;
    final adjustments = <String>[];
    final antiHumanLikeOpponent =
        opponent.isHuman || opponent.botBehavior == BotBehavior.moi;

    int baseThreshold;
    if (opponent.hand.length <= 2) {
      baseThreshold = 8;
    } else if (opponent.hand.length == 3) {
      baseThreshold = 9;
    } else {
      baseThreshold = 10;
    }
    int threshold = baseThreshold;

    if (antiHumanLikeOpponent) {
      threshold -= DuelTuning.duelAntiHumanLikeThresholdDrop;
      adjustments
          .add('anti_human_like:-${DuelTuning.duelAntiHumanLikeThresholdDrop}');
    }
    if (targetedRecently) {
      threshold -= 1;
      adjustments.add('targeted_recently:-1');
    }

    // Peu d'observations: garder une base prudente.
    if (decisions <= 0) {
      return _DuelValetThresholdTrace(
        baseThreshold: baseThreshold,
        finalThreshold: threshold.clamp(2, 10),
        observedDecisions: decisions,
        exchangeRate: exchangeRate,
        avgInstantDiscard: avgInstantDiscard,
        avgExchangeDiscard: avgExchangeDiscard,
        lowInstantRate: lowInstantRate,
        recentLowInstant: recentLowInstant,
        styleOptimization: style.optimization,
        styleConfidence: style.confidence,
        estimatedScore: estimate.estimatedScore,
        estimateConfidence: estimate.confidence,
        indexIntelCeiling: indexIntel.estimatedScoreCeiling,
        indexIntelConfidence: indexIntel.confidence,
        startKnownRatio: indexIntel.startKnownRatio,
        powerUses: powerUses,
        recentPowerUses: recentPowerUses,
        adjustments: const <String>['fallback_no_observation'],
      );
    }

    // Signal fort: l'adversaire jette instantanément des petites cartes.
    // On réduit le seuil de payload pour le déstabiliser plus tôt.
    if (recentLowInstant || lowInstantRate >= 0.45) {
      final inferred = (avgInstantDiscard + 1.0).round().clamp(3, 8);
      threshold = min(threshold, inferred);
      adjustments.add(
        'low_instant_discards-><=${inferred.toString()}',
      );
    }

    // S'il remplace souvent et défausse haut, il optimise agressivement.
    // Même une carte moyenne peut alors casser son tempo.
    if (exchangeRate >= 0.62 && avgExchangeDiscard >= 8.0) {
      threshold = min(threshold, 7);
      adjustments.add('high_exchange_discards-><=7');
    }

    final likelyStrongHand = estimate.confidence >= 0.30 &&
        estimate.estimatedScore <= (opponent.hand.length * 4.5);
    final strongOptimizer =
        style.confidence >= 0.30 && style.optimization >= 0.65;
    if (likelyStrongHand) {
      threshold -= 1;
      adjustments.add('likely_strong_hand:-1');
    }
    if (strongOptimizer) {
      threshold -= 1;
      adjustments.add('strong_optimizer:-1');
    }

    final intelIndicatesStrongHand = indexIntel.confidence >= 0.22 &&
        indexIntel.estimatedScoreCeiling <= (opponent.hand.length * 5.2);
    if (intelIndicatesStrongHand) {
      threshold = min(threshold, DuelTuning.duelIntelStrongCapThreshold);
      adjustments.add(
          'index_intel_strong-><=${DuelTuning.duelIntelStrongCapThreshold}');
    }

    if (indexIntel.startKnownRatio >= 0.45) {
      threshold -= 1;
      adjustments.add('start_known_ratio:-1');
    }

    if (powerUses >= 3 || recentPowerUses >= 2) {
      threshold -= 1;
      adjustments.add('power_pressure:-1');
    }
    if (deckLowChance <= 0.25 || deckExpectedPoints >= 7.2) {
      threshold -= 1;
      adjustments.add('deck_dry:-1');
    } else if (deckLowChance >= 0.46 && deckExpectedPoints <= 5.8) {
      threshold += 1;
      adjustments.add('deck_rich:+1');
    }

    return _DuelValetThresholdTrace(
      baseThreshold: baseThreshold,
      finalThreshold: threshold.clamp(2, 10),
      observedDecisions: decisions,
      exchangeRate: exchangeRate,
      avgInstantDiscard: avgInstantDiscard,
      avgExchangeDiscard: avgExchangeDiscard,
      lowInstantRate: lowInstantRate,
      recentLowInstant: recentLowInstant,
      styleOptimization: style.optimization,
      styleConfidence: style.confidence,
      estimatedScore: estimate.estimatedScore,
      estimateConfidence: estimate.confidence,
      indexIntelCeiling: indexIntel.estimatedScoreCeiling,
      indexIntelConfidence: indexIntel.confidence,
      startKnownRatio: indexIntel.startKnownRatio,
      powerUses: powerUses,
      recentPowerUses: recentPowerUses,
      adjustments: adjustments,
    );
  }

  static void _logDuelValetDecision(
    Player bot, {
    required String decision,
    required Map<String, dynamic> context,
  }) {
    GameLoggerService.instance.logBotDecision(
      bot: bot,
      decision: decision,
      context: context,
    );
  }

  /// Mode "animal acculé" (Platine):
  /// en fin de course quand le bot est derrière, le Valet bascule en
  /// sabotage de variance: empoisonner la cible la plus dangereuse avec la
  /// plus grosse carte connue disponible chez un donneur.
  static (Player, Player)? _resolvePlatinumValetAggressivePlan(
    GameState gs,
    Player observer,
    Player firstTarget,
    Player secondTarget,
    BotDifficulty difficulty,
  ) {
    if (!_isPlatinumDifficulty(difficulty)) return null;
    if (firstTarget.hand.isEmpty || secondTarget.hand.isEmpty) return null;

    final s1 =
        _adaptivePlatinumThreatScore(gs, observer, firstTarget, difficulty);
    final s2 =
        _adaptivePlatinumThreatScore(gs, observer, secondTarget, difficulty);
    final primary = s1 >= s2 ? firstTarget : secondTarget;

    final myPerceived = _estimateBotPerceivedScore(observer);
    final primaryEstimate = BotDutchStrategy.estimateOpponentForObserver(
      gs,
      observer,
      primary,
      difficulty,
    );
    final behindPrimary = myPerceived > (primaryEstimate.estimatedScore + 1);

    final activeOpponents = gs.players
        .where((p) => p.id != observer.id && p.hand.isNotEmpty)
        .length;
    final nearDuel = activeOpponents <= 3;

    final primaryVelocity = BotDutchStrategy.discardTracker.getCardVelocity(
      primary.id,
      gs.turnCount,
      currentCards: primary.hand.length,
      windowTurns: 2,
    );
    final primaryBurst = BotDutchStrategy.discardTracker.hasMatchBurst(
      primary.id,
      gs.turnCount,
      requiredMatches: 2,
      withinTurns: 3,
    );
    final raceOn =
        primary.hand.length <= 3 || primaryVelocity >= 2 || primaryBurst;

    if (!behindPrimary || !nearDuel || !raceOn) {
      return null;
    }

    final donorCandidates = gs.players
        .where((p) =>
            p.id != observer.id && p.id != primary.id && p.hand.isNotEmpty)
        .toList(growable: false);
    if (donorCandidates.isEmpty) return null;

    final scored = donorCandidates
        .map((p) {
          final knownHigh = _bestKnownSpiedCardPoints(observer, p);
          final donorThreat =
              _adaptivePlatinumThreatScore(gs, observer, p, difficulty);
          // On cherche un payload élevé sans "buff" un autre leader.
          final score = (knownHigh * 3.0) - donorThreat;
          return (player: p, knownHigh: knownHigh, score: score);
        })
        .where((e) => e.knownHigh >= 10)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) return null;

    return (primary, scored.first.player);
  }

  static int _estimateBotPerceivedScore(Player bot) {
    if (bot.isHuman) return bot.calculateScore();
    final known = bot.getKnownScore();
    final unknown = (bot.hand.length - bot.knownCardCount).clamp(0, 20);
    return known + (unknown * 6.5).round();
  }

  static int _bestKnownSpiedCardPoints(Player observer, Player target) {
    final spied = observer.getSpiedCards(target.id);
    if (spied == null || spied.isEmpty) return -1;
    int best = -1;
    for (final entry in spied.entries) {
      final idx = entry.key;
      if (idx < 0 || idx >= target.hand.length) continue;
      final points = entry.value.points;
      if (points > best) best = points;
    }
    return best;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR JOKER : Mélanger la main d'un joueur
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> _usePowerJoker(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    Object? context, {
    BotPersonality? personality,
  }) async {
    Player? target =
        _chooseJokerTarget(gs, bot, difficulty, personality: personality);

    // Silver+ : jamais s'attaquer soi-même. Si aucune cible valide → skip.
    // Bronze : fallback sur soi-même autorisé (conséquence de la règle
    // "Bronze ne cible jamais l'humain" en 1v1, design volontaire).
    if (target == null) {
      if (!_isBronzeDifficulty(difficulty)) return false;
      target = bot;
    }

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

    return true;
  }

  /// Choisit la cible du Joker selon l'analyse de menace contextuelle
  /// Règles :
  /// Bronze: JAMAIS l'humain. Cible uniquement les autres bots.
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
    // BRONZE : JAMAIS cibler l'humain avec le Joker
    if (_isBronzeDifficulty(difficulty)) {
      // Ne cibler que les autres bots, jamais l'humain
      final candidates = gs.players
          .where((p) => p.id != bot.id && !p.isHuman && p.hand.length > 1)
          .toList(growable: false);
      if (candidates.isEmpty) return null; // Skip si aucun bot disponible
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

    // Alliance : si ce bot est allié, prioriser la cible commune.
    final allianceTargetId =
        BotGossipService.instance.allianceTargetFor(bot.id, gs.turnCount);
    if (allianceTargetId != null) {
      final allianceTarget = possibleTargets
          .where((p) => p.id == allianceTargetId)
          .firstOrNull;
      if (allianceTarget != null) return allianceTarget;
    }

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

    if (validThreats.isNotEmpty) {
      // RÈGLE : Si l'humain est dans le top 2 des menaces, le cibler
      final humanInTop2 = validThreats.take(2).any((o) => o.isHuman);
      if (humanInTop2) {
        final humanThreat = validThreats.firstWhere((o) => o.isHuman);
        return humanThreat.player;
      }
      return validThreats.first.player;
    }

    // Fallback : l'analyse de menace n'a rien retourné mais on avait bien
    // des cibles dans le filtre simple. Cibler le premier venu plutôt que
    // laisser tomber le pouvoir.
    return possibleTargets.isNotEmpty ? possibleTargets.first : null;
  }

  static void _skipPower(
    GameState gameState,
    Player bot, {
    String reason = 'Pas d\'avantage à utiliser ce pouvoir',
  }) {
    final powerVal = gameState.specialCardToActivate?.value ?? '?';
    if (powerVal != '?') {
      BotDutchStrategy.discardTracker.recordPowerSkip(
        bot.id,
        powerVal,
        turnCount: gameState.turnCount,
      );
    }

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    // gameState.addToHistory("⏭️ ${bot.name} ignore son pouvoir. ($reason)");

    // Log
    GameLoggerService.instance.logPowerSkip(
      player: bot,
      powerValue: _powerValueForLog(powerVal),
      reason: reason,
    );
  }

  static int _powerValueForLog(String rawValue) {
    switch (rawValue) {
      case '7':
        return 7;
      case '10':
        return 10;
      case 'V':
        return 11;
      case 'JOKER':
        return 0;
      default:
        return int.tryParse(rawValue) ?? -1;
    }
  }

  static bool _isPlatinumDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Difficile':
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
      case 'Difficile':
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

  static OpponentReadTier _publicReadTierForDifficulty(
    BotDifficulty difficulty,
  ) {
    if (_isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty)) {
      return OpponentReadTier.strong;
    }
    return OpponentReadTier.medium;
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
      '🤯 ${bot.name} a confondu l\'info espionnée avec sa propre carte.',
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
    gs.addToHistory('😵 ${bot.name} s\'est distrait et a oublié une de ses cartes.');
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
        .map((p) {
          final signal = _analyzePublicPowerSignal(p, difficulty);
          return (
            player: p,
            score: _adaptivePlatinumThreatScore(gs, observer, p, difficulty) +
                (signal.readyThreat * 8.5) -
                (signal.vulnerability * 1.6)
          );
        })
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
    final readTier = _publicReadTierForDifficulty(difficulty);
    BotDutchStrategy.discardTracker.observePublicMemorizedIndices(
      player.id,
      player.memorizedCardIndices,
      player.hand.length,
    );
    final handEstimate = BotDutchStrategy.estimateOpponentForObserver(
      gs,
      observer,
      player,
      difficulty,
    );
    final style = BotDutchStrategy.discardTracker.estimateOpponentStyle(
      player.id,
      readTier: readTier,
    );
    final indexIntel = BotDutchStrategy.discardTracker
        .estimateOpponentIndexIntel(
      player.id,
      player.hand.length,
      readTier: readTier,
    );
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
    final publicSignal = _analyzePublicPowerSignal(player, difficulty);
    final intelGap =
        ((player.hand.length * 6.5) - indexIntel.estimatedScoreCeiling)
            .clamp(0.0, 18.0);

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

    if (indexIntel.confidence >= 0.18) {
      score += intelGap * 0.65 * indexIntel.confidence;
      score += indexIntel.startKnownRatio * 4.0 * indexIntel.confidence;
      score += indexIntel.lowRejectRate * 2.6 * indexIntel.confidence;
    }
    if (indexIntel.powerUses >= 2) {
      score += (min(indexIntel.powerUses, 6) * 0.55);
    }
    score += publicSignal.readyThreat * 8.0;
    score -= publicSignal.vulnerability * 2.2;

    if (player.isHuman && player.hand.length <= 2) {
      score += 14.0;
    }
    if (player.isHuman || player.botBehavior == BotBehavior.moi) {
      score += player.hand.length <= 3
          ? DuelTuning.humanLikeThreatBonusLowCards
          : DuelTuning.humanLikeThreatBonusNormalCards;
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
    final style = BotDutchStrategy.discardTracker.estimateOpponentStyle(
      playerId,
      readTier: OpponentReadTier.strong,
    );
    return (style.optimization * 0.8 + style.aggression * 0.2).clamp(0.0, 1.0);
  }

  static bool _canPlanValetSteal(Player bot, BotDifficulty difficulty) {
    if (!(_isGoldDifficulty(difficulty) || _isPlatinumDifficulty(difficulty))) {
      return false;
    }
    final unknownOwn = BotMemoryManager.getUnknownIndices(bot);
    if (unknownOwn.isNotEmpty) return true;
    return _worstKnownCardPoints(bot) >= 8;
  }

  static _PublicPowerSignal _analyzePublicPowerSignal(
    Player player,
    BotDifficulty difficulty,
  ) {
    final cards = player.hand.length;
    final readTier = _publicReadTierForDifficulty(difficulty);
    final handEstimate = BotDutchStrategy.discardTracker.estimateOpponentHand(
      player.id,
      cards,
      readTier: readTier,
    );
    final style = BotDutchStrategy.discardTracker.estimateOpponentStyle(
      player.id,
      readTier: readTier,
    );
    final indexIntel = BotDutchStrategy.discardTracker.estimateOpponentIndexIntel(
      player.id,
      cards,
      readTier: readTier,
    );
    final ceiling =
        BotDutchStrategy.discardTracker.getCurrentHandMaxCardCeiling(player.id);
    final minUpper =
        BotDutchStrategy.discardTracker.getCurrentMinCardUpperBound(player.id);
    final skipped7 = BotDutchStrategy.discardTracker.getPowerSkipCount(
      player.id,
      powerValue: '7',
    );
    final recentLooks =
        BotDutchStrategy.discardTracker.getRecentSelfLookCount(player.id);
    final recentSpies =
        BotDutchStrategy.discardTracker.getRecentSpyCount(player.id);
    final recentFails =
        BotDutchStrategy.discardTracker.getRecentMatchFailCount(player.id);
    final disruptions =
        BotDutchStrategy.discardTracker.getVisibleDisruptionCount(player.id);

    double readyThreat = 0.0;
    if (ceiling != null) readyThreat += 0.24;
    if (minUpper != null) readyThreat += 0.14;
    if (skipped7 > 0) {
      readyThreat += readTier == OpponentReadTier.strong ? 0.26 : 0.12;
    }
    if (recentLooks > 0) readyThreat += 0.12;
    if (recentSpies > 0 && cards <= 2) readyThreat += 0.15;
    if (cards <= 2) readyThreat += 0.14;
    readyThreat +=
        (style.optimization * 0.18 * style.confidence).clamp(0.0, 0.18);
    if (cards > 0) {
      final avgCard = (handEstimate.estimatedScore / cards).clamp(1.0, 10.0);
      readyThreat += ((5.0 - avgCard) / 10.0).clamp(0.0, 0.22);
    }
    readyThreat += ((cards * 6.5 - indexIntel.estimatedScoreCeiling) / 20.0)
        .clamp(0.0, 0.16);
    readyThreat -= disruptions * 0.16;
    readyThreat -= recentFails * 0.12;
    readyThreat = readyThreat.clamp(0.0, 1.0);

    double vulnerability = 0.0;
    vulnerability += disruptions * 0.32;
    vulnerability += recentFails * 0.26;
    if (cards <= 2 && ceiling == null && recentLooks == 0) {
      vulnerability += 0.08;
    }
    vulnerability -= readyThreat * 0.20;
    vulnerability = vulnerability.clamp(0.0, 1.0);

    return _PublicPowerSignal(
      readyThreat: readyThreat,
      vulnerability: vulnerability,
    );
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

    final handEstimate = BotDutchStrategy.discardTracker.estimateOpponentHand(
      player.id,
      cards,
      readTier: OpponentReadTier.strong,
    );
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
    BotDutchStrategy.discardTracker.observePublicMemorizedIndices(
      player.id,
      player.memorizedCardIndices,
      player.hand.length,
    );
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
    final indexIntel = BotDutchStrategy.discardTracker
        .estimateOpponentIndexIntel(
      player.id,
      cards,
      readTier: OpponentReadTier.strong,
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

    if (indexIntel.confidence >= 0.20 && cards > 0) {
      final capThreat = ((cards * 6.0) - indexIntel.estimatedScoreCeiling)
          .clamp(0.0, cards * 6.0);
      final normalizedCapThreat =
          cards <= 0 ? 0.0 : (capThreat / (cards * 6.0)).clamp(0.0, 1.0);
      probability += normalizedCapThreat * 0.20 * indexIntel.confidence;
      probability += indexIntel.startKnownRatio * 0.10 * indexIntel.confidence;
      probability += indexIntel.lowRejectRate * 0.08 * indexIntel.confidence;
      if (indexIntel.powerUses >= 2) {
        probability += 0.05;
      }
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
      if (lower.contains('a raté son match') ||
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

class _DuelValetPlan {
  final Player opponent;
  final int ownCardIndex;
  final int opponentCardIndex;

  const _DuelValetPlan({
    required this.opponent,
    required this.ownCardIndex,
    required this.opponentCardIndex,
  });
}

class _PublicPowerSignal {
  final double readyThreat;
  final double vulnerability;

  const _PublicPowerSignal({
    required this.readyThreat,
    required this.vulnerability,
  });
}

class _DuelValetThresholdTrace {
  final int baseThreshold;
  final int finalThreshold;
  final int observedDecisions;
  final double exchangeRate;
  final double avgInstantDiscard;
  final double avgExchangeDiscard;
  final double lowInstantRate;
  final bool recentLowInstant;
  final double styleOptimization;
  final double styleConfidence;
  final double estimatedScore;
  final double estimateConfidence;
  final double indexIntelCeiling;
  final double indexIntelConfidence;
  final double startKnownRatio;
  final int powerUses;
  final int recentPowerUses;
  final List<String> adjustments;

  const _DuelValetThresholdTrace({
    required this.baseThreshold,
    required this.finalThreshold,
    required this.observedDecisions,
    required this.exchangeRate,
    required this.avgInstantDiscard,
    required this.avgExchangeDiscard,
    required this.lowInstantRate,
    required this.recentLowInstant,
    required this.styleOptimization,
    required this.styleConfidence,
    required this.estimatedScore,
    required this.estimateConfidence,
    required this.indexIntelCeiling,
    required this.indexIntelConfidence,
    required this.startKnownRatio,
    required this.powerUses,
    required this.recentPowerUses,
    required this.adjustments,
  });

  Map<String, dynamic> toLogContext() {
    return <String, dynamic>{
      'threshold.base': baseThreshold,
      'threshold.final': finalThreshold,
      'threshold.adjustments':
          adjustments.isEmpty ? 'none' : adjustments.join(' | '),
      'obs.decisions': observedDecisions,
      'obs.exchangeRate': exchangeRate.toStringAsFixed(2),
      'obs.avgInstantDiscard': avgInstantDiscard.toStringAsFixed(2),
      'obs.avgExchangeDiscard': avgExchangeDiscard.toStringAsFixed(2),
      'obs.lowInstantRate': lowInstantRate.toStringAsFixed(2),
      'obs.recentLowInstant': recentLowInstant,
      'obs.styleOptimization': styleOptimization.toStringAsFixed(2),
      'obs.styleConfidence': styleConfidence.toStringAsFixed(2),
      'obs.estimatedScore': estimatedScore.toStringAsFixed(2),
      'obs.estimateConfidence': estimateConfidence.toStringAsFixed(2),
      'obs.indexIntelCeiling': indexIntelCeiling.toStringAsFixed(2),
      'obs.indexIntelConfidence': indexIntelConfidence.toStringAsFixed(2),
      'obs.startKnownRatio': startKnownRatio.toStringAsFixed(2),
      'obs.powerUses': powerUses,
      'obs.recentPowerUses': recentPowerUses,
    };
  }
}
