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
    int replaceIdx = -1;

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
    final otherPlayersCards = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => p.hand.length);
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
    
    // Note: En endgame tendu ou si l'humain est dangereux,
    // on désactive la stratégie doublons (voir ci-dessous)

    // ═══════════════════════════════════════════════════════════════════════
    // STRATÉGIE DOUBLONS (priorité haute) - Désactivée en endgame tendu
    // Si le bot a un doublon et que la carte piochée est > valeur doublon,
    // échanger un des doublons → puis matcher l'autre pendant défausse collective
    // ═══════════════════════════════════════════════════════════════════════
    final doublonInfo = isTenseEndgame ? null : BotMemoryManager.getBestDoublonForExchange(bot, drawnVal);
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
    List<int> unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    if (unknownIndices.isNotEmpty) {
      replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
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

    bool isBadDraw = false;

    if (maxKnownValue >= 0 && drawnVal > maxKnownValue) {
      // Carte piochée pire que toutes les cartes connues -> on défausse
      GameLogic.discardDrawnCard(gs);
      isBadDraw = true;
    } else if (worstKnownIdx != -1 && drawnVal < worstKnownValue) {
      // Sinon, on remplace la pire carte connue
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

  static void _replaceCard(GameState gs, Player bot, int replaceIdx, PlayingCard drawn, BotDifficulty difficulty) {
    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
    if (!confused) {
      bot.updateMentalMap(replaceIdx, drawn);
    }
    GameLogic.replaceCard(gs, replaceIdx);
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

    double matchChance = _getMatchChance(
      bot,
      difficulty,
      phase,
      gameState,
      personality: personality,
    );

    if (_random.nextDouble() > matchChance) return false;

    PlayingCard topDiscard = gameState.discardPile.last;
    
    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;
        
        if (knownCard.matches(topDiscard)) {
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            int reactionDelay = (380 * (1 - difficulty.reactionSpeed)).round() + 120;
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
    } else if (bot.botBehavior == BotBehavior.balanced && phase == BotGamePhase.endgame) {
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
      matchChance += (personality.riskTolerance - 0.5) * 0.25; // Augmenté de 0.2 à 0.25
    }

    return matchChance.clamp(0.0, 1.0);
  }
}
