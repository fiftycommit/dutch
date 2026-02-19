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
    final humanThreatLevel = threatTracker.calculateThreatLevel(gs);

    // En menace HIGH+, les bots deviennent plus conservateurs et stratégiques
    final isHumanDangerous = humanThreatLevel == HumanThreatLevel.high ||
        humanThreatLevel == HumanThreatLevel.critical;

    // ═══════════════════════════════════════════════════════════════════════
    // ANALYSE DU CONTEXTE DE TABLE
    // Quand tout le monde a peu de cartes OU qu'on a beaucoup joué → CONSERVATEUR
    // ═══════════════════════════════════════════════════════════════════════
    final myCards = bot.hand.length;
    final otherPlayersCards =
        gs.players.where((p) => p.id != bot.id).map((p) => p.hand.length);
    final avgOthersCards = otherPlayersCards.isEmpty
        ? 4.0
        : otherPlayersCards.reduce((a, b) => a + b) / otherPlayersCards.length;
    final minOthersCards = otherPlayersCards.isEmpty
        ? 4
        : otherPlayersCards.reduce((a, b) => a < b ? a : b);

    // Nombre de fois que CE bot a joué
    final myTurnsPlayed = gs.actionCount ~/ gs.players.length;
    final isLateGame = myTurnsPlayed >= 7;

    // Mode "endgame tendu" :
    // - Peu de cartes pour tout le monde OU
    // - Quelqu'un a ≤2 cartes OU
    // - On a joué plus de 7 tours
    // - 🎯 OU l'humain est dangereux (menace HIGH+)
    final isTenseEndgame = (myCards <= 2 && avgOthersCards <= 3) ||
        minOthersCards <= 2 ||
        isLateGame ||
        isHumanDangerous;

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

    // EXPLORATION : Remplacer une carte inconnue systématiquement
    // Règle demandée : si je ne connais pas une carte, je la remplace peu importe la valeur
    if (unknownIndices.isNotEmpty) {
      final replaceIdx = _chooseUnknownReplacementIndex(
        gs,
        bot,
        unknownIndices,
        decisionProfile,
        phase,
      );
      final replaceHintScore =
          _unknownHintScore(bot, replaceIdx, gs.actionCount);

      if (decisionProfile.tier == _CardTier.platinum) {
        // Si Platine pioche un 7 alors qu'il a encore des inconnues,
        // il privilégie la défausse du 7 pour déclencher le pouvoir
        // "regarder une carte", au lieu d'un échange aveugle.
        if (drawn.value == '7') {
          GameLogic.discardDrawnCard(gs);
          bot.consecutiveBadDraws++;
          return;
        }

        final expectedUnknownValue =
            BotMemoryManager.getExpectedDeckCardValue(gs);
        final knownScore = bot.getKnownScore();
        final lowScoreEndgameProtection =
            (phase == BotGamePhase.endgame || isTenseEndgame) &&
                knownScore <= 2 &&
                drawnVal > 2;
        if (lowScoreEndgameProtection) {
          GameLogic.discardDrawnCard(gs);
          bot.consecutiveBadDraws++;
          return;
        }

        // Carte reçue possiblement bonne (swap depuis joueur fort):
        // on évite de l'écraser avec une pioche moyenne/haute.
        final preserveLikelyGoodUnknown =
            replaceHintScore >= 0.55 && drawnVal > 4;
        final preserveVeryGoodUnknown =
            replaceHintScore >= 0.70 && drawnVal > 3;
        if (preserveLikelyGoodUnknown || preserveVeryGoodUnknown) {
          GameLogic.discardDrawnCard(gs);
          bot.consecutiveBadDraws++;
          return;
        }

        // Politique stricte: Platine n'échange une inconnue que si la pioche
        // est réellement meilleure que l'espérance de cette inconnue.
        // En début de partie (peu de tours joués), plus tolérant pour découvrir vite
        final myTurnsPlayed = gs.actionCount ~/ gs.players.length;
        final baseBlindSwapTolerance = myTurnsPlayed <= 3
            ? 0.2
            : isTenseEndgame
                ? -0.8
                : -0.4;
        final contextualTolerance =
            baseBlindSwapTolerance - (replaceHintScore * 1.1);
        final maxAcceptableBlindSwap =
            expectedUnknownValue + contextualTolerance;
        if (drawnVal > 2 && drawnVal > maxAcceptableBlindSwap) {
          // Platine: applique une logique d'espérance sur les inconnues
          // pour éviter les échanges aveugles fortement défavorables.
          GameLogic.discardDrawnCard(gs);
          bot.consecutiveBadDraws++;
          return;
        }
      }

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
      // Platine cible d'abord l'inconnue jugée la plus suspecte
      // (hint faible/négatif) au lieu d'un choix arbitraire.
      int bestIdx = unknownIndices.first;
      double worstHintScore = _unknownHintScore(bot, bestIdx, gs.actionCount);

      for (final idx in unknownIndices.skip(1)) {
        final score = _unknownHintScore(bot, idx, gs.actionCount);
        if (score < worstHintScore) {
          worstHintScore = score;
          bestIdx = idx;
        }
      }

      // S'il n'y a aucun signal, fallback stable en fin de main.
      final noContext = unknownIndices
          .every((idx) => bot.getUnknownCardHintQuality(idx) == null);
      return noContext ? unknownIndices.last : bestIdx;
    }

    // En fin de manche, les tiers élevés jouent plus "stables"
    // pour réduire les swings dus à l'aléatoire.
    if (phase == BotGamePhase.endgame && _isAdvancedCardTier(profile.tier)) {
      return unknownIndices.first;
    }

    return unknownIndices[_random.nextInt(unknownIndices.length)];
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
    BotGamePhase phase,
  ) {
    final myTurnsPlayed = gs.actionCount ~/ gs.players.length;
    final threatTracker = HumanThreatTracker();
    final humanThreat = threatTracker.calculateThreatLevel(gs);
    final isHumanDangerous = humanThreat == HumanThreatLevel.high ||
        humanThreat == HumanThreatLevel.critical;
    final antiHumanActive = myTurnsPlayed >= 3 || isHumanDangerous;

    // Contexte de table
    final otherPlayersCards =
        gs.players.where((p) => p.id != bot.id).map((p) => p.hand.length);
    final minOthersCards = otherPlayersCards.isEmpty
        ? 4
        : otherPlayersCards.reduce((a, b) => a < b ? a : b);
    final avgOthersCards = otherPlayersCards.isEmpty
        ? 4.0
        : otherPlayersCards.reduce((a, b) => a + b) / otherPlayersCards.length;
    final isTenseEndgame = (bot.hand.length <= 2 && avgOthersCards <= 3) ||
        minOthersCards <= 2 ||
        myTurnsPlayed >= 7 ||
        isHumanDangerous;

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

    // EXPLORATION : swap systématique des inconnues (séquentiel via .first)
    // Gold hésite parfois à explorer avec une carte haute (≥8)
    if (unknownIndices.isNotEmpty) {
      if (drawnVal >= 8 && _random.nextDouble() < 0.15) {
        GameLogic.discardDrawnCard(gs);
        bot.consecutiveBadDraws++;
        return;
      }
      final replaceIdx = unknownIndices.first;
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      GameLogic.replaceCard(gs, replaceIdx);
      bot.consecutiveBadDraws = 0;
      return;
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
            threatTracker,
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
          threatTracker,
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

  static double _unknownHintScore(Player bot, int cardIndex, int actionCount) {
    final quality = bot.getUnknownCardHintQuality(cardIndex);
    final confidence = bot.getUnknownCardHintConfidence(cardIndex);
    if (quality == null || confidence == null) return 0.0;

    final updatedAt = bot.getUnknownCardHintAction(cardIndex);
    final age = updatedAt == null ? 0 : (actionCount - updatedAt).clamp(0, 20);
    final decayFactor = pow(0.92, age).toDouble();
    final boundedDecay =
        decayFactor < 0.25 ? 0.25 : (decayFactor > 1.0 ? 1.0 : decayFactor);
    final decayedConfidence = confidence * boundedDecay;
    return quality * decayedConfidence;
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

    if (decisionProfile.tier == _CardTier.silver) {
      return _trySilverReactionMatch(gameState, bot, difficulty, hasKnownMatch);
    }

    final bronzeBlackoutActive = decisionProfile.tier == _CardTier.bronze &&
        _isBronzeBlackoutActive(bot, gameState);

    // Bronze en blackout: il tente parfois un match totalement au hasard.
    if (bronzeBlackoutActive && bot.hand.isNotEmpty) {
      final recklessChance = hasKnownMatch ? 0.42 : 0.28;
      if (_random.nextDouble() < recklessChance) {
        final randomIndex = _random.nextInt(bot.hand.length);
        await Future.delayed(const Duration(milliseconds: 120));
        return GameLogic.matchCard(gameState, bot, randomIndex);
      }
    }

    // Bronze (et un peu Argent) peut "rater le timing" d'une réaction,
    // même s'il connaît une carte matchante.
    if (decisionProfile.knownMatchLapseChance > 0 && hasKnownMatch) {
      final crowdedTablePenalty =
          ((gameState.players.length - 4) * 0.015).clamp(0.0, 0.20);
      final lapseChance =
          (decisionProfile.knownMatchLapseChance + crowdedTablePenalty)
              .clamp(0.0, 0.90);
      if (_random.nextDouble() < lapseChance) {
        return false;
      }
    }

    final forceKnownReaction =
        decisionProfile.forceKnownReaction && hasKnownMatch;
    if (!forceKnownReaction) {
      double matchChance = _getMatchChance(
        bot,
        difficulty,
        phase,
        gameState,
        personality: personality,
      );
      if (_random.nextDouble() > matchChance) return false;
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
          knownMatchLapseChance: 0.12,
          unknownReplaceSkipChance: 0.05,
          forceKnownReaction: false,
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
