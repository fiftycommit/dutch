import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_config.dart';
import 'bot_memory_manager.dart';
import 'bot_personality.dart';

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
    final isTenseEndgame = (myCards <= 2 && avgOthersCards <= 3) || 
                           minOthersCards <= 2 || 
                           isLateGame;
    
    // En endgame tendu, seuil d'échange beaucoup plus strict
    // "Quand j'ai peu de cartes, j'échange que avec une bonne carte si les autres ont peu de cartes"
    final conservativeThreshold = isTenseEndgame ? 3 : 5; // Seuil pour garder une carte inconnue

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

    // EXPLORATION : Remplacer une carte inconnue pour la découvrir
    List<int> unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    
    double exploreChance = difficulty.name == "Platine" ? 1.0 :
                          difficulty.name == "Or" ? 1.0 :
                          difficulty.name == "Argent" ? 0.80 : 0.50;

    if (personality != null) {
      final style = (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0);
      exploreChance += style * 0.15;
      exploreChance -= (personality.memoryAccuracy - 0.7) * 0.2;
      exploreChance = exploreChance.clamp(0.2, 1.0);
    }
    
    // BUGFIX: En endgame tendu, réduire drastiquement l'exploration aveugle
    if (isTenseEndgame) {
      exploreChance *= 0.3; // 70% moins d'exploration
    }
    
    if (unknownIndices.isNotEmpty && _random.nextDouble() < exploreChance) {
      replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
      return;
    }
    
    // OPTIMIZATION : Chercher à améliorer le score
    int keepThreshold = _getKeepThreshold(
      bot.botBehavior,
      difficulty,
      phase,
      personality: personality,
    );

    // Chercher la pire carte connue
    int worstKnownValue = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        int cardValue = bot.mentalMap[i]!.points;
        if (cardValue > worstKnownValue && cardValue > drawnVal) {
          worstKnownValue = cardValue;
          replaceIdx = i;
        }
      }
    }

    bool isBadDraw = false;
    
    // AMÉLIORATION : Logique de remplacement plus intelligente
    // Le bot garde la carte si :
    // 1. Elle est <= seuil (très bonne carte)
    // 2. OU elle améliore significativement le score (diff >= 2)
    // 3. OU on a des cartes inconnues et la pioche est meilleure que la moyenne
    //    MAIS en endgame tendu, être plus strict (conservativeThreshold)

    final hasUnknownCards = unknownIndices.isNotEmpty;
    // BUGFIX: En endgame tendu, utiliser le seuil conservateur
    final drawnIsBetterThanAverage = drawnVal <= conservativeThreshold;

    if (replaceIdx != -1 && drawnVal <= keepThreshold) {
      // Cas 1 : Très bonne carte, on la garde
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else if (replaceIdx != -1 && worstKnownValue > drawnVal) {
      // Cas 2 : OPTIMISATION STRICTE - échanger si amélioration de 1+ point
      // Comme un joueur humain : R(13) → D(12) = échange !
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else if (hasUnknownCards && drawnIsBetterThanAverage && replaceIdx == -1) {
      // Cas 3 : Carte décente et on a des inconnues - explorer
      // BUGFIX: En endgame tendu, on n'explore que si la carte est vraiment bonne (<=3)
      int exploreIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(exploreIdx, drawn);
      }
      GameLogic.replaceCard(gs, exploreIdx);
      bot.consecutiveBadDraws = 0;
    } else {
      GameLogic.discardDrawnCard(gs);
      isBadDraw = true;
    }
    
    if (isBadDraw) {
      bot.consecutiveBadDraws++;
    }
  }

  static int _getKeepThreshold(
    BotBehavior? behavior,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    int keepThreshold = difficulty.keepCardThreshold;
    
    // HARDCORE FIX: Respecter le seuil de la difficulté, ne pas l'écraser
    // Pour Platine/Or/Insane/Nightmare/Impossible, le comportement NE modifie PAS le seuil
    final isHardcore = difficulty.name == "Platine" || 
                       difficulty.name == "Or" ||
                       difficulty.name == "Hard" ||
                       difficulty.name == "Insane" ||
                       difficulty.name == "Nightmare" ||
                       difficulty.name == "Impossible" ||
                       difficulty.name == "Impossible";
    
    if (!isHardcore) {
      // Seuls les bots non-hardcore peuvent avoir leur seuil modifié par le comportement
      switch (behavior) {
        case BotBehavior.fast:
          // Fast: légèrement plus permissif SAUF pour les difficultés hautes
          keepThreshold += 2;
          break;
        case BotBehavior.aggressive:
          keepThreshold += 1;
          break;
        case BotBehavior.balanced:
          if (phase == BotGamePhase.endgame) {
            keepThreshold = (keepThreshold + difficulty.keepCardThreshold) ~/ 2;
          }
          break;
        default:
          break;
      }
    }

    // En endgame, tous les bots deviennent plus sélectifs
    if (phase == BotGamePhase.endgame) {
      keepThreshold -= 1;
    }

    // HARDCORE FIX: Ne PAS appliquer le clamp min 2 pour les hautes difficultés
    if (personality != null && !isHardcore) {
      final style = (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0);
      keepThreshold += (style * 2).round(); // Réduit l'impact de 3 à 2
      keepThreshold = keepThreshold.clamp(1, 10); // Min 1 au lieu de 2
    } else if (personality != null && isHardcore) {
      // Pour hardcore: style a un impact minimal
      final style = (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0);
      keepThreshold += (style * 0.5).round();
      // Clamp avec le minimum de la difficulté comme floor
      keepThreshold = keepThreshold.clamp(difficulty.keepCardThreshold, 8);
    }

    return keepThreshold;
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
            
            bool success = GameLogic.matchCard(gameState, bot, i);
            
            if (success && i < bot.mentalMap.length) {
              bot.mentalMap.removeAt(i);
            }
            return success;
          }
        }
      }
    }

    // Match à l'aveugle pour Or/Platine et niveaux hardcore
    final isHardcore = difficulty.name == "Or" || 
                       difficulty.name == "Platine" ||
                       difficulty.name == "Hard" ||
                       difficulty.name == "Insane" ||
                       difficulty.name == "Nightmare";
    
    if (isHardcore) {
      return await _tryBlindMatch(
        gameState,
        bot,
        difficulty,
        topDiscard,
        personality: personality,
      );
    }

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

  static Future<bool> _tryBlindMatch(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    PlayingCard topDiscard, {
    BotPersonality? personality,
  }) async {
    // === NOUVELLE RÈGLE : PAS DE MATCH À L'AVEUGLE ===
    // Un match à l'aveugle a seulement 4/52 = 7.7% de chances de réussir
    // C'est un move "clownesque" qu'aucun humain réaliste ne ferait
    // 
    // On ne tente un match que si :
    // 1. La carte cible est connue (déjà géré dans tryReactionMatch)
    // 2. OU la probabilité dépasse un seuil réaliste (35-45%)
    //
    // Pour dépasser ce seuil, il faut avoir réduit l'espace des possibles
    // via beaucoup d'informations (pouvoirs, mémoire, etc.)
    
    List<int> unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    if (unknownIndices.isEmpty) return false;

    // Calculer la probabilité réelle de match
    // Dans un jeu standard: 4 cartes du même rang sur 52
    // Mais on peut affiner si on a des infos sur les cartes déjà vues
    
    // Compter combien de cartes du même rang on a déjà vues
    final targetRank = topDiscard.value;
    int cardsOfRankSeen = 0;
    
    // Cartes dans la défausse
    for (var card in gameState.discardPile) {
      if (card.value == targetRank) {
        cardsOfRankSeen++;
      }
    }
    
    // Cartes que le bot connaît dans sa main
    for (var card in bot.mentalMap) {
      if (card != null && card.value == targetRank) {
        cardsOfRankSeen++;
      }
    }
    
    // Calcul de probabilité
    // Si on a vu X cartes du rang, il en reste (4-X) quelque part
    // Probabilité = (4-X) / (52 - cartes vues)
    final cardsRemaining = 4 - cardsOfRankSeen;
    if (cardsRemaining <= 0) return false; // Toutes les cartes de ce rang sont visibles
    
    // Estimation grossière des cartes restantes dans le jeu
    final totalSeenCards = gameState.discardPile.length + 
                           bot.mentalMap.where((c) => c != null).length;
    final cardsInPlay = 52 - totalSeenCards;
    
    if (cardsInPlay <= 0) return false;
    
    final matchProbability = cardsRemaining / cardsInPlay;
    
    // Seuil minimum pour tenter un match à l'aveugle
    // Un humain rationnel n'essaie que si la proba est raisonnable
    double minProbabilityThreshold;
    switch (difficulty.name) {
      case "Impossible":
        minProbabilityThreshold = 0.30; // Boss peut prendre plus de risques calculés
        break;
      case "Nightmare":
        minProbabilityThreshold = 0.35;
        break;
      case "Insane":
        minProbabilityThreshold = 0.38;
        break;
      case "Hard":
        minProbabilityThreshold = 0.40;
        break;
      case "Platine":
        minProbabilityThreshold = 0.35;
        break;
      default:
        minProbabilityThreshold = 0.45; // Or et moins : plus prudent
    }
    
    // Ajustement personnalité
    if (personality != null) {
      // Les personnalités risk-taker peuvent baisser légèrement le seuil
      minProbabilityThreshold -= (personality.riskTolerance - 0.5) * 0.10;
      minProbabilityThreshold = minProbabilityThreshold.clamp(0.25, 0.55);
    }
    
    // Si la probabilité est trop faible, ne pas tenter
    if (matchProbability < minProbabilityThreshold) {
      return false;
    }

    // OK, la probabilité est acceptable, on peut tenter
    int blindIndex = unknownIndices[_random.nextInt(unknownIndices.length)];
    PlayingCard blindCard = bot.hand[blindIndex];
    
    if (blindCard.matches(topDiscard)) {
      int reactionDelay = (320 * (1 - difficulty.reactionSpeed)).round() + 120;
      if (personality != null) {
        reactionDelay =
            (reactionDelay * (personality.decisionSpeedMs / 2000.0))
                .round()
                .clamp(120, 850);
      }
      await Future.delayed(Duration(milliseconds: reactionDelay));
      
      bool success = GameLogic.matchCard(gameState, bot, blindIndex);
      if (success && blindIndex < bot.mentalMap.length) {
        bot.mentalMap.removeAt(blindIndex);
      }
      return success;
    }
    
    return false;
  }
}
