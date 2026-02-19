import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_config.dart';
import 'bot_memory_manager.dart';
import 'bot_personality.dart';
import 'human_threat_tracker.dart';

/// Stratégie de gestion des cartes
/// Principe GRASP: Information Expert - Décide quoi faire avec les cartes
class BotCardStrategy {
  static final Random _random = Random();

  /// Vérifie si la carte piochée est meilleure (points inférieurs) qu'une autre carte
  /// Retourne true si drawnPoints < existingPoints
  static bool isCardBetter(int drawnPoints, int existingPoints) {
    return drawnPoints < existingPoints;
  }

  /// Vérifie si la carte piochée vaut la peine d'être gardée
  /// Une carte est "bonne" si elle est <= seuil (typiquement 4-5)
  static bool isCardWorthKeeping(int drawnPoints, int threshold) {
    return drawnPoints <= threshold;
  }

  /// Décide quoi faire avec la carte piochée
  static Future<void> decideCardAction(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) async {
    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) return;

    int drawnVal = drawn.points;
    final decisionProfile = _decisionProfileForDifficulty(difficulty);
    _maybeTriggerBronzeBlackout(gs, bot, decisionProfile);

    // ═══════════════════════════════════════════════════════════════════════
    // 🎯 ANALYSE DE LA MENACE HUMAINE
    // Les bots doivent réagir quand l'humain devient dangereux
    // ═══════════════════════════════════════════════════════════════════════
    final threatTracker = HumanThreatTracker();
    final tableConclusions = _buildTableConclusions(gs, bot, threatTracker);
    final isTenseEndgame = tableConclusions.isTenseEndgame;

    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);

    if (decisionProfile.tier == _CardTier.bronze) {
      _handleBronzeReplacementByContext(
        gs,
        bot,
        drawn,
        drawnVal,
        difficulty,
        unknownIndices,
      );
      return;
    }

    if (decisionProfile.tier == _CardTier.silver) {
      _handleSilverReplacementByContext(
        gs,
        bot,
        drawn,
        drawnVal,
        difficulty,
        unknownIndices,
      );
      return;
    }

    if (decisionProfile.tier == _CardTier.gold) {
      _handleGoldReplacementByContext(
        gs,
        bot,
        drawn,
        drawnVal,
        difficulty,
        unknownIndices,
        phase,
        threatTracker: threatTracker,
        tableConclusions: tableConclusions,
      );
      return;
    }

    // RÈGLE PLATINE SUR LE 7 :
    // - S'il reste des inconnues, on défausse le 7 pour activer le pouvoir.
    // - Sinon, on garde le 7 uniquement pour remplacer une carte > 7.
    // - Si aucune carte > 7, on défausse quand même le 7 pour re-vérifier une carte.
    if (drawn.value == '7' && _isAdvancedCardTier(decisionProfile.tier)) {
      if (unknownIndices.isNotEmpty) {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
        return;
      }

      int worstKnownValue = -1;
      int worstKnownIdx = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        final known = bot.mentalMap[i];
        if (known != null && known.points > worstKnownValue) {
          worstKnownValue = known.points;
          worstKnownIdx = i;
        }
      }

      if (worstKnownIdx != -1 && worstKnownValue > 7) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
      return;
    }

    // PRIORITE INFO (Platine) :
    // tant qu'il reste des inconnues, on les résout d'abord.
    // Exception: en forte pression de table, le tempo-match immédiat reste autorisé.
    if (unknownIndices.isNotEmpty) {
      final prioritizeInfo =
          _shouldPrioritizeInfoWhenUnknowns(tableConclusions);
      if (!prioritizeInfo &&
          _tryAdvancedTempoSelfMatchPlay(
            gs,
            bot,
            drawn,
            phase,
            decisionProfile,
            tableConclusions,
            onlyWhenForceTempo: true,
          )) {
        return;
      }

      final replaceIdx = _chooseUnknownReplacementIndex(
        gs,
        bot,
        unknownIndices,
        decisionProfile,
        phase,
      );

      if (decisionProfile.unknownReplaceSkipChance > 0 &&
          drawnVal >= 7 &&
          _random.nextDouble() < decisionProfile.unknownReplaceSkipChance) {
        // Bot faible: il "panique" et jette une carte moyenne/haute
        // au lieu d'explorer une inconnue.
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
        return;
      }
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      GameLogic.replaceCard(gs, replaceIdx);
      bot.consecutiveBadDraws = 0;
      return;
    }

    if (_tryAdvancedTempoSelfMatchPlay(
      gs,
      bot,
      drawn,
      phase,
      decisionProfile,
      tableConclusions,
    )) {
      return;
    }

    // Note: En endgame tendu ou si l'humain est dangereux,
    // on désactive la stratégie doublons (voir ci-dessous)

    // ═══════════════════════════════════════════════════════════════════════
    // STRATÉGIE DOUBLONS (priorité haute) - Désactivée en endgame tendu
    // Si le bot a un doublon et que la carte piochée est > valeur doublon,
    // échanger un des doublons → puis matcher l'autre pendant défausse collective
    // ═══════════════════════════════════════════════════════════════════════
    final allowDoublonPlay = !decisionProfile.greedyImmediate &&
        (!isTenseEndgame || decisionProfile.tier == _CardTier.platinum);
    final doublonInfo = allowDoublonPlay
        ? BotMemoryManager.getBestDoublonForExchange(bot, drawnVal)
        : null;
    if (doublonInfo != null) {
      final (exchangeIdx, _, doublonValue) = doublonInfo;
      // Vérifier que l'échange est rentable : on perd (drawnVal - doublonValue)
      // mais on gagne doublonValue via le match → net = 2×doublonValue - drawnVal
      // C'est rentable si 2×doublonValue > drawnVal
      if (2 * doublonValue > drawnVal) {
        bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
        if (!confused) {
          bot.updateMentalMap(exchangeIdx, drawn);
        }
        GameLogic.replaceCard(gs, exchangeIdx);
        return;
      }
    }

    // OPTIMIZATION : Aucun inconnu -> seule règle
    // Ne pas prendre une carte au-dessus de toutes mes cartes connues
    int maxKnownValue = -1;
    int worstKnownValue = -1;
    int worstKnownIdx = -1;

    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        final cardValue = bot.mentalMap[i]!.points;
        if (cardValue > maxKnownValue) {
          maxKnownValue = cardValue;
        }
        if (cardValue > worstKnownValue) {
          worstKnownValue = cardValue;
          worstKnownIdx = i;
        }
      }
    }

    final bronzeBlackoutActive = _isBronzeBlackoutActive(bot, gs) &&
        decisionProfile.tier == _CardTier.bronze;
    if (bronzeBlackoutActive) {
      // Bronze en blackout: comportement impulsif, sans calcul réel.
      if (worstKnownIdx != -1 && _random.nextDouble() < 0.55) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
      return;
    }

    bool isBadDraw = false;
    final requiredImprovement = _requiredImprovement(
      decisionProfile,
      phase,
      isTenseEndgame,
      personality,
    );
    final improvement = worstKnownValue - drawnVal;

    // Bronze "glouton": court-terme uniquement.
    // Il garde seulement si l'amélioration immédiate est stricte.
    if (decisionProfile.greedyImmediate) {
      if (worstKnownIdx != -1 &&
          improvement >= decisionProfile.greedyMinImmediateImprovement) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
      return;
    }

    if (maxKnownValue >= 0 && drawnVal > maxKnownValue) {
      if (worstKnownIdx != -1 &&
          _shouldAvoidHelpingHumanByKeeping(
            threatTracker,
            gs,
            drawnVal,
            worstKnownValue,
            decisionProfile,
          )) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        // Carte piochée pire que toutes les cartes connues -> on défausse
        GameLogic.discardDrawnCard(gs);
        isBadDraw = true;
      }
    } else if (worstKnownIdx != -1 &&
        _shouldReplaceKnownCard(
          improvement,
          requiredImprovement,
          phase,
          isTenseEndgame,
          decisionProfile,
        )) {
      // Remplacer la pire carte connue si le gain est suffisant.
      _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else if (worstKnownIdx != -1 &&
        _shouldAvoidHelpingHumanByKeeping(
          threatTracker,
          gs,
          drawnVal,
          worstKnownValue,
          decisionProfile,
        )) {
      // En table tendue, mieux vaut parfois garder une carte moyenne
      // plutôt que d'offrir une carte "matchable" à l'humain.
      _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else {
      // Pas d'amélioration -> on défausse
      GameLogic.discardDrawnCard(gs);
      isBadDraw = true;
    }

    if (isBadDraw) {
      bot.consecutiveBadDraws++;
    }
  }

  static int _chooseUnknownReplacementIndex(
    GameState gs,
    Player bot,
    List<int> unknownIndices,
    _CardDecisionProfile profile,
    BotGamePhase phase,
  ) {
    if (unknownIndices.length == 1) return unknownIndices.first;

    if (profile.tier == _CardTier.platinum) {
      return phase == BotGamePhase.endgame
          ? unknownIndices.first
          : unknownIndices.last;
    }

    if (profile.tier == _CardTier.gold) {
      if (phase == BotGamePhase.endgame) return unknownIndices.first;
      return unknownIndices.last;
    }

    // En fin de manche, les tiers élevés jouent plus "stables"
    // pour réduire les swings dus à l'aléatoire.
    if (phase == BotGamePhase.endgame && _isAdvancedCardTier(profile.tier)) {
      return unknownIndices.first;
    }

    return unknownIndices[_random.nextInt(unknownIndices.length)];
  }

  static bool _tryAdvancedTempoSelfMatchPlay(
    GameState gs,
    Player bot,
    PlayingCard drawn,
    BotGamePhase phase,
    _CardDecisionProfile profile,
    _CardTableConclusions tableConclusions, {
    bool onlyWhenForceTempo = false,
  }) {
    if (!_isAdvancedCardTier(profile.tier)) return false;
    if (drawn.value == '7' ||
        drawn.value == '10' ||
        drawn.value == 'V' ||
        drawn.value == 'JOKER') {
      return false;
    }

    final bestMatchIdx = _bestKnownMatchIndex(bot, drawn);
    if (bestMatchIdx == -1) return false;

    final worstKnownValue = _worstKnownValue(bot);
    final replaceGain =
        worstKnownValue > drawn.points ? worstKnownValue - drawn.points : 0;
    final tempoGain = drawn.points + (tableConclusions.myCards <= 2 ? 2 : 1);

    final forceTempo = tableConclusions.isTenseEndgame ||
        phase == BotGamePhase.endgame ||
        tableConclusions.minOpponentCards <= 2 ||
        tableConclusions.isHumanDangerous ||
        tableConclusions.myCards <= 3;

    if (onlyWhenForceTempo && !forceTempo) return false;

    if (!forceTempo && replaceGain >= tempoGain + 2) {
      return false;
    }
    if (!forceTempo &&
        drawn.points <= 2 &&
        replaceGain >= 4 &&
        tableConclusions.avgOpponentCards >= 3.5) {
      return false;
    }

    GameLogic.discardDrawnCard(gs);
    final matchIdx = _bestKnownMatchIndex(bot, drawn);
    final matched =
        matchIdx != -1 ? GameLogic.matchCard(gs, bot, matchIdx) : false;
    if (matched) {
      bot.consecutiveBadDraws = 0;
    } else {
      bot.consecutiveBadDraws++;
    }
    return true;
  }

  static int _bestKnownMatchIndex(Player bot, PlayingCard target) {
    int idx = -1;
    int highestPoints = -1;
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length) continue;
      final known = bot.mentalMap[i];
      if (known == null || !known.matches(target)) continue;
      if (known.points > highestPoints) {
        highestPoints = known.points;
        idx = i;
      }
    }
    return idx;
  }

  static int _worstKnownValue(Player bot) {
    int value = -1;
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length) continue;
      final known = bot.mentalMap[i];
      if (known == null) continue;
      if (known.points > value) value = known.points;
    }
    return value;
  }

  static bool _shouldPrioritizeInfoWhenUnknowns(
      _CardTableConclusions tableConclusions) {
    // Si le bot est clairement en retard en nombre de cartes,
    // il priorise l'info pour rattraper l'optimisation.
    final cardGap =
        tableConclusions.myCards - tableConclusions.minOpponentCards;
    return cardGap >= 2;
  }

  static void _handleBronzeReplacementByContext(
    GameState gs,
    Player bot,
    PlayingCard drawn,
    int drawnVal,
    BotDifficulty difficulty,
    List<int> unknownIndices,
  ) {
    // Bronze par contexte:
    // 1) remplacer une carte connue strictement supérieure à la pioche;
    // 2) sinon explorer une inconnue;
    // 3) sinon défausser.
    int replaceIdx = -1;
    int highestKnownAboveDraw = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      final known = bot.mentalMap[i];
      if (known == null) continue;
      if (known.points > drawnVal && known.points > highestKnownAboveDraw) {
        highestKnownAboveDraw = known.points;
        replaceIdx = i;
      }
    }

    if (replaceIdx == -1 && unknownIndices.isNotEmpty) {
      replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
    }

    if (replaceIdx != -1) {
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else {
      GameLogic.discardDrawnCard(gs);
      bot.consecutiveBadDraws++;
    }
  }

  static void _handleSilverReplacementByContext(
    GameState gs,
    Player bot,
    PlayingCard drawn,
    int drawnVal,
    BotDifficulty difficulty,
    List<int> unknownIndices,
  ) {
    // Argent (contextuel simple):
    // - 7: remplacer une connue >7, sinon défausser pour déclencher le pouvoir.
    // - sinon: remplacer la 1ère inconnue, sinon améliorer la pire connue.
    if (drawn.value == '7') {
      final myTurns = gs.actionCount ~/ gs.players.length;
      // Argent apprend la règle du 7 tard : défausse stratégique à partir du tour 5
      if (myTurns >= 5 && unknownIndices.isNotEmpty) {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
        return;
      }

      int replaceIdx = -1;
      int worstAboveSeven = -1;
      for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
        final known = bot.mentalMap[i];
        if (known == null) continue;
        if (known.points > 7 && known.points > worstAboveSeven) {
          worstAboveSeven = known.points;
          replaceIdx = i;
        }
      }

      if (replaceIdx != -1) {
        _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
      return;
    }

    if (unknownIndices.isNotEmpty) {
      final replaceIdx = unknownIndices.first;
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
      return;
    }

    int worstKnownIdx = -1;
    int worstKnownValue = -1;
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final known = bot.mentalMap[i];
      if (known == null) continue;
      if (known.points > worstKnownValue) {
        worstKnownValue = known.points;
        worstKnownIdx = i;
      }
    }

    if (worstKnownIdx != -1 && drawnVal < worstKnownValue) {
      _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else {
      // Anti-humain soft Argent : actif tous les 4 tours à partir du tour 5
      final myTurns = gs.actionCount ~/ gs.players.length;
      final silverAntiHumanActive = myTurns >= 5 && myTurns % 4 == 0;
      if (silverAntiHumanActive &&
          worstKnownIdx != -1 &&
          _shouldAvoidHelpingHumanByKeeping(
            HumanThreatTracker(),
            gs,
            drawnVal,
            worstKnownValue,
            _decisionProfileForDifficulty(difficulty),
          )) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
    }
  }

  static void _handleGoldReplacementByContext(
    GameState gs,
    Player bot,
    PlayingCard drawn,
    int drawnVal,
    BotDifficulty difficulty,
    List<int> unknownIndices,
    BotGamePhase phase, {
    HumanThreatTracker? threatTracker,
    _CardTableConclusions? tableConclusions,
  }) {
    final tracker = threatTracker ?? HumanThreatTracker();
    final table = tableConclusions ?? _buildTableConclusions(gs, bot, tracker);
    final antiHumanActive = table.myTurnsPlayed >= 3 || table.isHumanDangerous;
    final isTenseEndgame = table.isTenseEndgame;

    // RÈGLE DU 7 : défausse pour pouvoir si inconnues, sinon remplace pire >7
    if (drawn.value == '7') {
      if (unknownIndices.isNotEmpty) {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
        return;
      }
      int worstKnownValue = -1;
      int worstKnownIdx = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        final known = bot.mentalMap[i];
        if (known != null && known.points > worstKnownValue) {
          worstKnownValue = known.points;
          worstKnownIdx = i;
        }
      }
      if (worstKnownIdx != -1 && worstKnownValue > 7) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
      } else {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
      }
      return;
    }

    if (unknownIndices.isNotEmpty) {
      final prioritizeInfo = _shouldPrioritizeInfoWhenUnknowns(table);
      if (!prioritizeInfo &&
          _tryAdvancedTempoSelfMatchPlay(
            gs,
            bot,
            drawn,
            phase,
            _decisionProfileForDifficulty(difficulty),
            table,
            onlyWhenForceTempo: true,
          )) {
        return;
      }

      final replaceIdx = _chooseUnknownReplacementIndex(
        gs,
        bot,
        unknownIndices,
        _decisionProfileForDifficulty(difficulty),
        phase,
      );
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      GameLogic.replaceCard(gs, replaceIdx);
      bot.consecutiveBadDraws = 0;
      return;
    }

    if (_tryAdvancedTempoSelfMatchPlay(
      gs,
      bot,
      drawn,
      phase,
      _decisionProfileForDifficulty(difficulty),
      table,
    )) {
      return;
    }

    // STRATÉGIE DOUBLONS (désactivée en tense endgame)
    if (!isTenseEndgame) {
      final doublonInfo =
          BotMemoryManager.getBestDoublonForExchange(bot, drawnVal);
      if (doublonInfo != null) {
        final (exchangeIdx, _, doublonValue) = doublonInfo;
        if (2 * doublonValue > drawnVal) {
          bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
          if (!confused) {
            bot.updateMentalMap(exchangeIdx, drawn);
          }
          GameLogic.replaceCard(gs, exchangeIdx);
          return;
        }
      }
    }

    // OPTIMISATION : remplacer la pire connue si amélioration
    int worstKnownValue = -1;
    int worstKnownIdx = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      final known = bot.mentalMap[i];
      if (known != null && known.points > worstKnownValue) {
        worstKnownValue = known.points;
        worstKnownIdx = i;
      }
    }

    if (worstKnownIdx != -1 && drawnVal < worstKnownValue) {
      // Anti-humain : vérifier avant de défausser
      if (antiHumanActive &&
          _shouldAvoidHelpingHumanByKeeping(
            tracker,
            gs,
            drawnVal,
            worstKnownValue,
            _decisionProfileForDifficulty(difficulty),
          )) {
        _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
        bot.consecutiveBadDraws = 0;
        return;
      }
      _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else if (worstKnownIdx != -1 &&
        antiHumanActive &&
        _shouldAvoidHelpingHumanByKeeping(
          tracker,
          gs,
          drawnVal,
          worstKnownValue,
          _decisionProfileForDifficulty(difficulty),
        )) {
      _replaceCard(gs, bot, worstKnownIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else {
      GameLogic.discardDrawnCard(gs);
      bot.consecutiveBadDraws++;
    }
  }

  static void _maybeTriggerBronzeBlackout(
    GameState gs,
    Player bot,
    _CardDecisionProfile profile,
  ) {
    if (profile.tier != _CardTier.bronze) {
      if (bot.bronzeBlackoutActive &&
          gs.actionCount > bot.bronzeBlackoutUntilActionCount) {
        bot.bronzeBlackoutActive = false;
      }
      return;
    }

    // Le blackout Bronze ne se déclenche plus "magiquement".
    // Il est uniquement provoqué par des événements de distraction
    // (attaque subie, perte de focus sur un pouvoir, etc.).
    if (bot.bronzeBlackoutActive &&
        gs.actionCount > bot.bronzeBlackoutUntilActionCount) {
      bot.bronzeBlackoutActive = false;
    }
  }

  static bool _isBronzeBlackoutActive(Player bot, GameState gs) {
    if (!bot.bronzeBlackoutActive) return false;
    if (gs.actionCount <= bot.bronzeBlackoutUntilActionCount) return true;
    bot.bronzeBlackoutActive = false;
    return false;
  }

  static _CardTableConclusions _buildTableConclusions(
    GameState gs,
    Player bot,
    HumanThreatTracker threatTracker,
  ) {
    final humanThreatLevel = threatTracker.calculateThreatLevel(gs);
    final isHumanDangerous = humanThreatLevel == HumanThreatLevel.high ||
        humanThreatLevel == HumanThreatLevel.critical;

    final myCards = bot.hand.length;
    final otherPlayersCards =
        gs.players.where((p) => p.id != bot.id).map((p) => p.hand.length);
    final avgOthersCards = otherPlayersCards.isEmpty
        ? 4.0
        : otherPlayersCards.reduce((a, b) => a + b) / otherPlayersCards.length;
    final minOthersCards = otherPlayersCards.isEmpty
        ? 4
        : otherPlayersCards.reduce((a, b) => a < b ? a : b);

    final playersCount = gs.players.isEmpty ? 1 : gs.players.length;
    final myTurnsPlayed = gs.actionCount ~/ playersCount;
    final isLateGame = myTurnsPlayed >= 7;

    final isTenseEndgame = (myCards <= 2 && avgOthersCards <= 3) ||
        minOthersCards <= 2 ||
        isLateGame ||
        isHumanDangerous;

    return _CardTableConclusions(
      isHumanDangerous: isHumanDangerous,
      isTenseEndgame: isTenseEndgame,
      myTurnsPlayed: myTurnsPlayed,
      minOpponentCards: minOthersCards,
      avgOpponentCards: avgOthersCards,
      myCards: myCards,
    );
  }

  static _ReactionConclusions _buildReactionConclusions({
    required GameState gameState,
    required Player bot,
    required BotDifficulty difficulty,
    required BotGamePhase phase,
    required _CardDecisionProfile profile,
    required bool hasKnownMatch,
    BotPersonality? personality,
  }) {
    final bronzeBlackoutActive = profile.tier == _CardTier.bronze &&
        _isBronzeBlackoutActive(bot, gameState);
    final shouldAttemptBlackoutRandomMatch =
        bronzeBlackoutActive && bot.hand.isNotEmpty;
    final blackoutRecklessChance = hasKnownMatch ? 0.42 : 0.28;

    final immediateRaceThreat =
        gameState.players.any((p) => p.id != bot.id && p.hand.length <= 2) ||
            gameState.dutchCallerId != null;
    final forceKnownReaction = hasKnownMatch &&
        (profile.forceKnownReaction ||
            immediateRaceThreat ||
            phase == BotGamePhase.endgame ||
            bot.hand.length <= 3);

    double knownMatchLapseChance = 0.0;
    if (!forceKnownReaction &&
        profile.knownMatchLapseChance > 0 &&
        hasKnownMatch) {
      final crowdedTablePenalty =
          ((gameState.players.length - 4) * 0.015).clamp(0.0, 0.20);
      knownMatchLapseChance =
          (profile.knownMatchLapseChance + crowdedTablePenalty)
              .clamp(0.0, 0.90);
    }

    final matchChance = forceKnownReaction
        ? 1.0
        : _getMatchChance(
            bot,
            difficulty,
            phase,
            gameState,
            personality: personality,
          );

    return _ReactionConclusions(
      forceKnownReaction: forceKnownReaction,
      shouldAttemptBlackoutRandomMatch: shouldAttemptBlackoutRandomMatch,
      blackoutRecklessChance: blackoutRecklessChance,
      knownMatchLapseChance: knownMatchLapseChance,
      matchChance: matchChance,
    );
  }

  static int _requiredImprovement(
    _CardDecisionProfile profile,
    BotGamePhase phase,
    bool isTenseEndgame,
    BotPersonality? personality,
  ) {
    int required = profile.minImprovement;

    if (isTenseEndgame) {
      required += profile.tenseImprovementBonus;
    }

    if (phase == BotGamePhase.endgame && _isAdvancedCardTier(profile.tier)) {
      required -= 1;
    }

    if (personality != null) {
      final styleBias =
          ((personality.caution - personality.aggressiveness) * 2).round();
      final riskBias = ((personality.riskTolerance - 0.5) * 2).round();
      final adaptabilityBias = personality.adaptability >= 0.70 ? -1 : 0;

      required += styleBias;
      required -= riskBias;
      required += adaptabilityBias;
    }

    return required.clamp(0, 4);
  }

  static bool _shouldReplaceKnownCard(
    int improvement,
    int requiredImprovement,
    BotGamePhase phase,
    bool isTenseEndgame,
    _CardDecisionProfile profile,
  ) {
    if (improvement > 0 && improvement >= requiredImprovement) {
      return true;
    }

    if (improvement == 0 &&
        profile.allowEqualSwapInEndgame &&
        isTenseEndgame &&
        phase == BotGamePhase.endgame) {
      return true;
    }

    return false;
  }

  static bool _shouldAvoidHelpingHumanByKeeping(
    HumanThreatTracker threatTracker,
    GameState gs,
    int drawnVal,
    int worstKnownValue,
    _CardDecisionProfile profile,
  ) {
    if (profile.maxAcceptedWorseningToDenyHuman < 0) return false;
    if (!threatTracker.shouldAvoidHelpingHuman(gs, drawnVal)) return false;

    final worsening = drawnVal - worstKnownValue;
    return worsening <= profile.maxAcceptedWorseningToDenyHuman;
  }

  static void _replaceCard(GameState gs, Player bot, int replaceIdx,
      PlayingCard drawn, BotDifficulty difficulty) {
    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
    if (!confused) {
      bot.updateMentalMap(replaceIdx, drawn);
    }
    GameLogic.replaceCard(gs, replaceIdx);
  }

  static bool _hasKnownMatch(Player bot, PlayingCard target) {
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        if (bot.mentalMap[i]!.matches(target)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Tente un match de réaction
  static Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;
    if (gameState.discardPile.isEmpty) return false;

    PlayingCard topDiscard = gameState.discardPile.last;
    final decisionProfile = _decisionProfileForDifficulty(difficulty);
    final hasKnownMatch = _hasKnownMatch(bot, topDiscard);
    final reactionConclusions = _buildReactionConclusions(
      gameState: gameState,
      bot: bot,
      difficulty: difficulty,
      phase: phase,
      personality: personality,
      profile: decisionProfile,
      hasKnownMatch: hasKnownMatch,
    );

    if (decisionProfile.tier == _CardTier.silver) {
      return _trySilverReactionMatch(gameState, bot, difficulty, hasKnownMatch);
    }

    // Bronze en blackout: il tente parfois un match totalement au hasard.
    if (reactionConclusions.shouldAttemptBlackoutRandomMatch &&
        bot.hand.isNotEmpty) {
      if (_random.nextDouble() < reactionConclusions.blackoutRecklessChance) {
        final randomIndex = _random.nextInt(bot.hand.length);
        await Future.delayed(const Duration(milliseconds: 120));
        return GameLogic.matchCard(gameState, bot, randomIndex);
      }
    }

    // Bronze (et un peu Argent) peut "rater le timing" d'une réaction,
    // même s'il connaît une carte matchante.
    if (reactionConclusions.knownMatchLapseChance > 0 &&
        _random.nextDouble() < reactionConclusions.knownMatchLapseChance) {
      return false;
    }

    if (!reactionConclusions.forceKnownReaction &&
        _random.nextDouble() > reactionConclusions.matchChance) {
      return false;
    }

    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;

        if (knownCard.matches(topDiscard)) {
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            int reactionDelay =
                (380 * (1 - difficulty.reactionSpeed)).round() + 120;
            if (personality != null) {
              reactionDelay =
                  (reactionDelay * (personality.decisionSpeedMs / 2000.0))
                      .round()
                      .clamp(120, 900);
            }
            await Future.delayed(Duration(milliseconds: reactionDelay));

            // GameLogic.matchCard() gère déjà la suppression dans mentalMap
            return GameLogic.matchCard(gameState, bot, i);
          }
        }
      }
    }

    // Pas de match à l'aveugle : le bot ne tente un match que
    // sur les cartes qu'il connaît via sa mentalMap.
    // Si sa mémoire est altérée (oubli/confusion), il peut se tromper
    // et recevoir une pénalité — c'est le risque naturel du jeu.
    return false;
  }

  static Future<bool> _trySilverReactionMatch(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    bool hasKnownMatch,
  ) async {
    if (!hasKnownMatch) return false;

    final topDiscard = gameState.discardPile.last;
    final matchingIndices = <int>[];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length &&
          bot.mentalMap[i] != null &&
          bot.mentalMap[i]!.matches(topDiscard)) {
        matchingIndices.add(i);
      }
    }
    if (matchingIndices.isEmpty) return false;

    final preferredIndex = matchingIndices.first;
    final confused = _random.nextDouble() < difficulty.confusionOnSwap;
    int firstAttemptIndex = preferredIndex;
    int? retryIndex;

    if (confused) {
      final alternatives =
          List<int>.generate(bot.hand.length, (i) => i).where((i) {
        return i != preferredIndex;
      }).toList(growable: false);
      if (alternatives.isNotEmpty) {
        firstAttemptIndex = alternatives[_random.nextInt(alternatives.length)];
        retryIndex = preferredIndex;
      }
    }

    int reactionDelay = (380 * (1 - difficulty.reactionSpeed)).round() + 120;
    await Future.delayed(Duration(milliseconds: reactionDelay));

    final firstSuccess = GameLogic.matchCard(gameState, bot, firstAttemptIndex);
    if (firstSuccess) return true;
    if (retryIndex == null) return false;

    if (retryIndex >= bot.hand.length) return false;
    await Future.delayed(const Duration(milliseconds: 120));
    return GameLogic.matchCard(gameState, bot, retryIndex);
  }

  static double _getMatchChance(
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    GameState gameState, {
    BotPersonality? personality,
  }) {
    double matchChance = difficulty.reactionMatchChance;

    // ═══════════════════════════════════════════════════════════════════════
    // 🎯 BONUS ANTI-HUMAIN : Plus agressif quand l'humain menace
    // ═══════════════════════════════════════════════════════════════════════
    final threatTracker = HumanThreatTracker();
    final humanThreatLevel = threatTracker.calculateThreatLevel(gameState);

    // Bonus de match basé sur la menace humaine
    switch (humanThreatLevel) {
      case HumanThreatLevel.critical:
        matchChance += 0.35; // Très agressif - l'humain va gagner !
        break;
      case HumanThreatLevel.high:
        matchChance += 0.20; // Agressif - l'humain est dangereux
        break;
      case HumanThreatLevel.medium:
        matchChance += 0.10; // Légèrement plus attentif
        break;
      case HumanThreatLevel.low:
        // Pas de bonus
        break;
    }

    // AMÉLIORATION : Bonus plus élevé pour beaucoup de cartes
    if (bot.hand.length >= 5) {
      matchChance += 0.25; // Augmenté de 0.15 à 0.25
    } else if (bot.hand.length >= 4) {
      matchChance += 0.15; // Augmenté de 0.10 à 0.15
    } else if (bot.hand.length >= 3) {
      matchChance += 0.10; // Nouveau bonus pour 3 cartes
    }

    if (bot.botBehavior == BotBehavior.fast) {
      matchChance = 1.0;
    } else if (bot.botBehavior == BotBehavior.balanced &&
        phase == BotGamePhase.endgame) {
      matchChance = (matchChance + 1.0) / 2;
    } else if (bot.botBehavior == BotBehavior.aggressive) {
      matchChance += 0.15; // Nouveau bonus pour aggressive
    }

    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      if (cumulativeScore >= 70) {
        matchChance += 0.25;
      } else if (cumulativeScore >= 50) {
        matchChance += 0.15;
      }
    }

    // AMÉLIORATION : En endgame, tout le monde est plus réactif
    if (phase == BotGamePhase.endgame) {
      matchChance += 0.15;
    }

    if (personality != null) {
      matchChance +=
          (personality.riskTolerance - 0.5) * 0.25; // Augmenté de 0.2 à 0.25
    }

    return matchChance.clamp(0.0, 1.0);
  }

  static _CardDecisionProfile _decisionProfileForDifficulty(
      BotDifficulty difficulty) {
    final tier = _tierFromDifficulty(difficulty);
    switch (tier) {
      case _CardTier.bronze:
        return const _CardDecisionProfile(
          tier: _CardTier.bronze,
          minImprovement: 2,
          tenseImprovementBonus: 1,
          maxAcceptedWorseningToDenyHuman: -1,
          allowEqualSwapInEndgame: false,
          greedyImmediate: true,
          greedyMinImmediateImprovement: 3,
          knownMatchLapseChance: 0.74,
          unknownReplaceSkipChance: 0.45,
          forceKnownReaction: false,
        );
      case _CardTier.silver:
        return const _CardDecisionProfile(
          tier: _CardTier.silver,
          minImprovement: 1,
          tenseImprovementBonus: 0,
          maxAcceptedWorseningToDenyHuman: 1,
          allowEqualSwapInEndgame: false,
          greedyImmediate: false,
          greedyMinImmediateImprovement: 1,
          knownMatchLapseChance: 0.14,
          unknownReplaceSkipChance: 0.0,
          forceKnownReaction: false,
        );
      case _CardTier.gold:
        return const _CardDecisionProfile(
          tier: _CardTier.gold,
          minImprovement: 0,
          tenseImprovementBonus: 0,
          maxAcceptedWorseningToDenyHuman: 1,
          allowEqualSwapInEndgame: true,
          greedyImmediate: false,
          greedyMinImmediateImprovement: 1,
          knownMatchLapseChance: 0.03,
          unknownReplaceSkipChance: 0.0,
          forceKnownReaction: true,
        );
      case _CardTier.platinum:
        return const _CardDecisionProfile(
          tier: _CardTier.platinum,
          minImprovement: 0,
          tenseImprovementBonus: 0,
          maxAcceptedWorseningToDenyHuman: 1,
          allowEqualSwapInEndgame: true,
          greedyImmediate: false,
          greedyMinImmediateImprovement: 1,
          knownMatchLapseChance: 0.0,
          unknownReplaceSkipChance: 0.0,
          forceKnownReaction: true,
        );
    }
  }

  static bool _isAdvancedCardTier(_CardTier tier) {
    return tier == _CardTier.gold || tier == _CardTier.platinum;
  }

  static _CardTier _tierFromDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Bronze':
        return _CardTier.bronze;
      case 'Argent':
        return _CardTier.silver;
      case 'Or':
      case 'Hard':
      case 'Insane':
        return _CardTier.gold;
      case 'Platine':
      case 'Nightmare':
      case 'Impossible':
        return _CardTier.platinum;
      default:
        if (difficulty.matchAccuracy >= 0.99 &&
            difficulty.reactionSpeed >= 0.98) {
          return _CardTier.platinum;
        }
        if (difficulty.matchAccuracy >= 0.95 &&
            difficulty.reactionSpeed >= 0.9) {
          return _CardTier.gold;
        }
        if (difficulty.matchAccuracy >= 0.9) {
          return _CardTier.silver;
        }
        return _CardTier.bronze;
    }
  }
}

enum _CardTier { bronze, silver, gold, platinum }

class _CardDecisionProfile {
  final _CardTier tier;
  final int minImprovement;
  final int tenseImprovementBonus;
  final int maxAcceptedWorseningToDenyHuman;
  final bool allowEqualSwapInEndgame;
  final bool greedyImmediate;
  final int greedyMinImmediateImprovement;
  final double knownMatchLapseChance;
  final double unknownReplaceSkipChance;
  final bool forceKnownReaction;

  const _CardDecisionProfile({
    required this.tier,
    required this.minImprovement,
    required this.tenseImprovementBonus,
    required this.maxAcceptedWorseningToDenyHuman,
    required this.allowEqualSwapInEndgame,
    required this.greedyImmediate,
    required this.greedyMinImmediateImprovement,
    required this.knownMatchLapseChance,
    required this.unknownReplaceSkipChance,
    required this.forceKnownReaction,
  });
}

class _CardTableConclusions {
  final bool isHumanDangerous;
  final bool isTenseEndgame;
  final int myTurnsPlayed;
  final int minOpponentCards;
  final double avgOpponentCards;
  final int myCards;

  const _CardTableConclusions({
    required this.isHumanDangerous,
    required this.isTenseEndgame,
    required this.myTurnsPlayed,
    required this.minOpponentCards,
    required this.avgOpponentCards,
    required this.myCards,
  });
}

class _ReactionConclusions {
  final bool forceKnownReaction;
  final bool shouldAttemptBlackoutRandomMatch;
  final double blackoutRecklessChance;
  final double knownMatchLapseChance;
  final double matchChance;

  const _ReactionConclusions({
    required this.forceKnownReaction,
    required this.shouldAttemptBlackoutRandomMatch,
    required this.blackoutRecklessChance,
    required this.knownMatchLapseChance,
    required this.matchChance,
  });
}
