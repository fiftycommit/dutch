import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';

/// Analyse des menaces et stratégies de ciblage
/// Principe GRASP: Information Expert - Analyse l'état du jeu pour identifier les menaces
class BotThreatAnalyzer {
  static final Random _random = Random();

  /// Détecte le joueur le plus menaçant (proche de gagner)
  static Player? getMostThreateningPlayer(GameState gs, Player bot) {
    Player? mostThreatening;
    int lowestCards = 99;
    int lowestScore = 999;
    
    for (var p in gs.players) {
      if (p.id == bot.id) continue;
      
      if (p.hand.length < lowestCards || 
          (p.hand.length == lowestCards && p.getEstimatedScore() < lowestScore)) {
        lowestCards = p.hand.length;
        lowestScore = p.getEstimatedScore();
        mostThreatening = p;
      }
    }
    
    // Retourner seulement si vraiment menaçant (3 cartes ou moins)
    if (mostThreatening != null && lowestCards <= 3) {
      return mostThreatening;
    }
    return null;
  }

  /// Vérifie si le bot devrait contre-attaquer
  static bool shouldCounterAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    Player? threat = getMostThreateningPlayer(gs, bot);
    if (threat == null) return false;
    
    double counterChance = difficulty.name == "Platine" ? 0.90 :
                          difficulty.name == "Or" ? 0.80 :
                          difficulty.name == "Argent" ? 0.60 : 0.30;
    
    if (threat.isHuman) {
      counterChance += 0.10;
    }
    
    return _random.nextDouble() < counterChance;
  }

  /// Analyse les défausses récentes pour estimer les mains adverses
  static Map<String, double> analyzeDiscardPatterns(GameState gs, Player bot, BotDifficulty difficulty) {
    Map<String, double> dangerScores = {};
    
    if (difficulty.name != "Or" && difficulty.name != "Platine") {
      return dangerScores;
    }
    
    for (var p in gs.players) {
      if (p.id == bot.id) continue;
      
      double danger = 0.0;
      
      danger += (5 - p.hand.length) * 15.0;
      
      int estimatedScore = p.getEstimatedScore();
      if (estimatedScore <= 5) {
        danger += 40.0;
      } else if (estimatedScore <= 10) {
        danger += 25.0;
      } else if (estimatedScore <= 15) {
        danger += 10.0;
      }
      
      if (p.isHuman) {
        danger += 20.0;
      }
      
      dangerScores[p.id] = danger;
    }
    
    return dangerScores;
  }

  /// Détermine si les bots devraient coordonner une attaque contre l'humain
  static bool shouldCoordinateAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    if (difficulty.name != "Or" && difficulty.name != "Platine") {
      return false;
    }
    
    Player? human;
    try {
      human = gs.players.firstWhere((p) => p.isHuman);
    } catch (e) {
      return false;
    }
    
    if (human.hand.length <= 3) {
      double coordChance = difficulty.name == "Platine" ? 0.85 : 0.70;
      return _random.nextDouble() < coordChance;
    }
    
    if (human.getEstimatedScore() <= 8) {
      double coordChance = difficulty.name == "Platine" ? 0.70 : 0.55;
      return _random.nextDouble() < coordChance;
    }
    
    return false;
  }

  /// Cible prioritaire pour contre-attaque avec Valet
  static Player? getCounterAttackTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    if (!shouldCounterAttack(gs, bot, difficulty)) {
      return null;
    }
    
    Player? threat = getMostThreateningPlayer(gs, bot);
    
    if (shouldCoordinateAttack(gs, bot, difficulty)) {
      try {
        Player human = gs.players.firstWhere((p) => p.isHuman);
        if (threat == null || !threat.isHuman) {
          if (_random.nextDouble() < 0.60) {
            return human;
          }
        }
      } catch (e) {
        // Pas d'humain
      }
    }
    
    return threat;
  }

  /// Calcule la pression du tournoi
  static double getTournamentPressure(GameState gs, Player bot) {
    if (gs.gameMode != GameMode.tournament) return 0.0;
    
    int cumulativeScore = gs.getCumulativeScore(bot);
    if (cumulativeScore >= 80) return 3.0;
    if (cumulativeScore >= 60) return 2.0;
    if (cumulativeScore >= 40) return 1.0;
    if (cumulativeScore <= 20) return -1.0;
    return 0.0;
  }
}
