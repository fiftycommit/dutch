import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../learning/ai_telemetry_service.dart';
import 'bot_difficulty.dart';
import 'bot_memory_manager.dart';

/// Mode de ciblage pour les pouvoirs
enum TargetMode {
  /// Bloquer le joueur en tête (empêcher de gagner)
  blockLeader,
  /// Punir un joueur rapide (bâtons dans les roues)
  punishFast,
  /// Voler de la valeur (améliorer son score via échange)
  stealValue,
  /// Obtenir de l'information sur un adversaire
  gatherInfo,
  /// 🔥 HARDCORE : Empêcher l'humain d'être sur le podium
  /// Même si ce n'est pas optimal pour le bot
  denyHumanPodium,
}

/// Rapport de menace pour un joueur
class OpponentThreat {
  final Player player;
  final int cardsLeft;
  final int estimatedScore;
  final double threatScore;
  final bool isLeader;
  final bool hasFewCards;
  final bool isHuman;

  OpponentThreat({
    required this.player,
    required this.cardsLeft,
    required this.estimatedScore,
    required this.threatScore,
    required this.isLeader,
    required this.hasFewCards,
    required this.isHuman,
  });
}

/// Rapport complet de la table
class ThreatReport {
  final List<OpponentThreat> opponents;
  final bool hasOpponentWithOneCard;
  final bool opponentsLikelyHighScore;
  final int minOpponentCards;
  final int avgOpponentCards;
  final double avgOpponentScore;
  final Player? leader;
  final double tablePressure;
  
  /// Score estimé du bot (exact si toutes cartes connues)
  final double botExpectedScore;
  /// Score estimé du meilleur adversaire
  final double bestOpponentScore;
  /// Confiance du bot dans sa position de leader (0..1)
  /// 0.85+ = très probablement devant, 0.5 = incertain, 0.2 = derrière
  final double leadConfidence;
  
  // 🔥 HARDCORE : Infos sur l'humain
  /// Rang actuel de l'humain (1 = premier, 4 = dernier)
  final int humanRank;
  /// Le joueur humain (null si pas d'humain)
  final Player? humanPlayer;
  /// L'humain est-il sur le podium (1er ou 2ème) ?
  final bool humanOnPodium;

  ThreatReport({
    required this.opponents,
    required this.hasOpponentWithOneCard,
    required this.opponentsLikelyHighScore,
    required this.minOpponentCards,
    required this.avgOpponentCards,
    required this.avgOpponentScore,
    required this.leader,
    required this.tablePressure,
    required this.botExpectedScore,
    required this.bestOpponentScore,
    required this.leadConfidence,
    required this.humanRank,
    required this.humanPlayer,
    required this.humanOnPodium,
  });

  /// Trie les adversaires par menace décroissante
  List<OpponentThreat> get sortedByThreat =>
      List.from(opponents)..sort((a, b) => b.threatScore.compareTo(a.threatScore));

  /// Retourne le joueur le plus menaçant
  OpponentThreat? get mostThreatening =>
      opponents.isEmpty ? null : sortedByThreat.first;
}

/// Analyse des menaces et stratégies de ciblage
/// Principe GRASP: Information Expert - Analyse l'état du jeu pour identifier les menaces
class BotThreatAnalyzer {
  static final Random _random = Random();
  
  /// 🔥 HARDCORE : Noms des difficultés "impitoyables"
  static const hardcoreDifficultyNames = {'Hard', 'Insane', 'Nightmare', 'Impossible'};
  
  /// Vérifie si la difficulté est un mode Hardcore (impitoyable)
  static bool isHardcoreMode(BotDifficulty? difficulty) {
    if (difficulty == null) return false;
    return hardcoreDifficultyNames.contains(difficulty.name);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSE CENTRALE DE LA TABLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyse complète de tous les adversaires
  /// C'est LA fonction centrale que tous les pouvoirs/décisions doivent utiliser
  static ThreatReport analyzeOpponents(
    GameState gs, 
    Player bot, {
    bool isHardcoreMode = false,
  }) {
    final opponents = <OpponentThreat>[];
    int totalCards = 0;
    double totalScore = 0;
    int minCards = 99;
    Player? leaderPlayer;
    int lowestScore = 999;

    for (var p in gs.players) {
      if (p.id == bot.id) continue;

      final cards = p.hand.length;
      final score = p.getKnownScore();
      
      totalCards += cards;
      totalScore += score;
      
      if (cards < minCards) {
        minCards = cards;
      }
      
      if (score < lowestScore) {
        lowestScore = score;
        leaderPlayer = p;
      }

      // Calcul du threatScore unifié (avec bonus Hardcore si activé)
      double threat = _calculateUnifiedThreatScore(
        p, 
        gs, 
        isHardcoreMode: isHardcoreMode,
      );

      opponents.add(OpponentThreat(
        player: p,
        cardsLeft: cards,
        estimatedScore: score,
        threatScore: threat,
        isLeader: false, // Sera mis à jour après
        hasFewCards: cards <= 2,
        isHuman: p.isHuman,
      ));
    }

    // Marquer le leader
    if (leaderPlayer != null) {
      final idx = opponents.indexWhere((o) => o.player.id == leaderPlayer!.id);
      if (idx != -1) {
        final old = opponents[idx];
        opponents[idx] = OpponentThreat(
          player: old.player,
          cardsLeft: old.cardsLeft,
          estimatedScore: old.estimatedScore,
          threatScore: old.threatScore,
          isLeader: true,
          hasFewCards: old.hasFewCards,
          isHuman: old.isHuman,
        );
      }
    }

    final count = opponents.length;
    final avgCards = count > 0 ? totalCards ~/ count : 4;
    final avgScore = count > 0 ? totalScore / count : 20.0;

    // Calculer la pression de table
    // Plus la pression est haute, plus le bot doit agir vite
    double tablePressure = 0.0;
    if (minCards == 1) {
      tablePressure += 3.0;
    } else if (minCards == 2) {
      tablePressure += 1.5;
    }
    if (avgScore < 10) {
      tablePressure += 1.0;
    }
    if (gs.gameMode == GameMode.tournament) {
      tablePressure += getTournamentPressure(gs, bot);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CALCUL leadConfidence (télémétrie SBMM)
    // ═══════════════════════════════════════════════════════════════════════
    
    // Score attendu du bot (exact si toutes cartes connues, sinon estimation)
    final botExpectedScore = _calculateBotExpectedScore(bot);
    
    // Meilleur score adverse (le plus bas = le plus menaçant)
    final bestOpponentScore = lowestScore.toDouble();
    
    // leadConfidence via sigmoid : margin positif = bot devant
    final leadConfidence = AiTelemetryService.calculateLeadConfidence(
      myExpectedScore: botExpectedScore,
      bestOpponentExpectedScore: bestOpponentScore,
    );

    // ═══════════════════════════════════════════════════════════════════════
    // 🔥 HARDCORE : Calcul du rang humain
    // ═══════════════════════════════════════════════════════════════════════
    Player? humanPlayer;
    int humanRank = 99; // Par défaut : non présent
    
    // Trouver l'humain parmi les adversaires
    for (final opp in opponents) {
      if (opp.isHuman) {
        humanPlayer = opp.player;
        break;
      }
    }
    
    // Calculer le rang de l'humain si présent
    if (humanPlayer != null) {
      // Tous les joueurs triés par score estimé (le plus bas = meilleur rang)
      final allScores = <(Player, double)>[];
      allScores.add((bot, botExpectedScore));
      for (final opp in opponents) {
        allScores.add((opp.player, opp.estimatedScore.toDouble()));
      }
      allScores.sort((a, b) => a.$2.compareTo(b.$2));
      
      // Trouver la position de l'humain
      for (int i = 0; i < allScores.length; i++) {
        if (allScores[i].$1.id == humanPlayer.id) {
          humanRank = i + 1; // 1-indexed
          break;
        }
      }
    }
    
    final humanOnPodium = humanRank <= 2;

    return ThreatReport(
      opponents: opponents,
      hasOpponentWithOneCard: minCards == 1,
      opponentsLikelyHighScore: avgScore > 15,
      minOpponentCards: minCards,
      avgOpponentCards: avgCards,
      avgOpponentScore: avgScore,
      leader: leaderPlayer,
      tablePressure: tablePressure,
      botExpectedScore: botExpectedScore,
      bestOpponentScore: bestOpponentScore,
      leadConfidence: leadConfidence,
      humanRank: humanRank,
      humanPlayer: humanPlayer,
      humanOnPodium: humanOnPodium,
    );
  }

  /// Calcule le score attendu du bot avec pénalité d'incertitude
  static double _calculateBotExpectedScore(Player bot) {
    double score = 0;
    int unknownCount = 0;
    
    for (int i = 0; i < bot.hand.length; i++) {
      final card = bot.hand[i];
      final known = i < bot.knownCards.length && bot.knownCards[i];
      
      if (known) {
        score += card.points;
      } else {
        // Pénalité d'incertitude : on suppose une carte moyenne (5-6)
        score += 5.5;
        unknownCount++;
      }
    }
    
    // Ajouter une marge d'incertitude
    // Plus de cartes inconnues = moins de confiance dans l'estimation
    score += unknownCount * 1.5; // Légère pénalité pour l'incertitude
    
    return score;
  }

  /// Calcul unifié du score de menace (utilisé partout)
  /// En mode Hardcore, l'humain reçoit un bonus massif
  static double _calculateUnifiedThreatScore(
    Player player, 
    GameState gs, {
    bool isHardcoreMode = false,
  }) {
    double score = 0.0;

    // 1) Nombre de cartes (le plus important)
    final cards = player.hand.length;
    if (cards == 1) {
      score += 50.0; // DANGER CRITIQUE
    } else if (cards == 2) {
      score += 30.0;
    } else if (cards == 3) {
      score += 15.0;
    } else if (cards == 4) {
      score += 5.0;
    }

    // 2) Score estimé
    final estimated = player.getKnownScore();
    if (estimated <= 3) {
      score += 25.0;
    } else if (estimated <= 6) {
      score += 15.0;
    } else if (estimated <= 10) {
      score += 8.0;
    }

    // 3) Bonus humain - TOUJOURS prioritaire !
    // AMÉLIORATION : Les bots doivent TOUJOURS cibler l'humain en priorité
    // C'est le joueur qu'ils doivent battre, pas les autres bots
    if (player.isHuman) {
      if (isHardcoreMode) {
        // 🔥 HARDCORE : L'humain est LA cible prioritaire
        // "Je ne peux pas gagner, mais toi non plus"
        score += 60.0; // Bonus massif
      } else {
        // Mode normal : bonus significatif quand même
        // Les bots se coordonnent contre l'humain
        score += 35.0; // Augmenté de 15 à 35
      }

      // Bonus supplémentaire si l'humain a peu de cartes
      if (cards <= 2) {
        score += 25.0; // Urgence : l'humain va Dutch
      }
    }

    // 4) Cartes connues (info = danger)
    final knownCount = BotMemoryManager.countKnownCards(player);
    if (knownCount >= 3) {
      score += 10.0; // Il sait ce qu'il fait
    }

    // 5) Tournoi : score cumulé
    if (gs.gameMode == GameMode.tournament) {
      final cumul = gs.getCumulativeScore(player);
      if (cumul <= 20) {
        score += 15.0; // En tête du tournoi
      } else if (cumul <= 40) {
        score += 8.0;
      } else if (cumul >= 80) {
        score -= 10.0; // Quasi éliminé
      }
    }

    return score;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SÉLECTION DE CIBLE UNIFIÉE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Choisit la meilleure cible selon le mode
  /// C'est LA fonction que tous les pouvoirs doivent appeler
  static Player? pickBestTarget(
    GameState gs,
    Player bot,
    TargetMode mode, {
    BotDifficulty? difficulty,
    bool isHardcoreMode = false,
  }) {
    final report = analyzeOpponents(gs, bot, isHardcoreMode: isHardcoreMode);
    if (report.opponents.isEmpty) return null;

    switch (mode) {
      case TargetMode.blockLeader:
        return _pickBlockLeaderTarget(report, difficulty);
      
      case TargetMode.punishFast:
        return _pickPunishFastTarget(report);
      
      case TargetMode.stealValue:
        return _pickStealValueTarget(report, bot, gs);
      
      case TargetMode.gatherInfo:
        return _pickGatherInfoTarget(report);
      
      case TargetMode.denyHumanPodium:
        // 🔥 HARDCORE : Cibler l'humain s'il est sur le podium
        return _pickDenyHumanPodiumTarget(report);
    }
  }

  /// Cible pour bloquer le leader
  static Player? _pickBlockLeaderTarget(ThreatReport report, BotDifficulty? difficulty) {
    // Priorité absolue : quelqu'un avec 1 carte
    if (report.hasOpponentWithOneCard) {
      final oneCardPlayers = report.opponents.where((o) => o.cardsLeft == 1).toList();
      if (oneCardPlayers.isNotEmpty) {
        // Prendre celui avec le meilleur score (le plus dangereux)
        oneCardPlayers.sort((a, b) => a.estimatedScore.compareTo(b.estimatedScore));
        return oneCardPlayers.first.player;
      }
    }

    // Sinon : le plus menaçant
    final sorted = report.sortedByThreat;
    
    // Intelligence selon difficulté
    final smartChance = difficulty != null
        ? (difficulty.name == "Platine" ? 0.95 :
           difficulty.name == "Or" ? 0.85 :
           difficulty.name == "Argent" ? 0.70 : 0.50)
        : 0.80;

    if (_random.nextDouble() < smartChance) {
      return sorted.first.player;
    }

    // Sinon random parmi les 2 premiers
    final topTwo = sorted.take(2).toList();
    return topTwo[_random.nextInt(topTwo.length)].player;
  }

  /// Cible pour punir un joueur rapide
  static Player? _pickPunishFastTarget(ThreatReport report) {
    // Prioriser les humains (souvent plus rapides) ou ceux avec peu de cartes
    final candidates = report.opponents.where((o) => o.isHuman || o.hasFewCards).toList();
    
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.threatScore.compareTo(a.threatScore));
      return candidates.first.player;
    }

    return report.mostThreatening?.player;
  }

  /// Cible pour voler de la valeur (Valet)
  static Player? _pickStealValueTarget(ThreatReport report, Player bot, GameState gs) {
    // Stratégie Valet : prendre la meilleure carte de celui qui a peu de cartes
    // et/ou donner sa pire carte au leader
    
    // Si quelqu'un a 1 carte, c'est LA cible (on veut sa bonne carte)
    if (report.hasOpponentWithOneCard) {
      final oneCard = report.opponents.where((o) => o.cardsLeft == 1).toList();
      if (oneCard.isNotEmpty) {
        // Celui avec le meilleur score = la carte est probablement bonne
        oneCard.sort((a, b) => a.estimatedScore.compareTo(b.estimatedScore));
        return oneCard.first.player;
      }
    }

    // Sinon : celui avec le score le plus bas (ses cartes sont bonnes)
    final sorted = List.of(report.opponents)
      ..sort((a, b) => a.estimatedScore.compareTo(b.estimatedScore));
    
    return sorted.first.player;
  }

  /// Cible pour obtenir de l'information
  static Player? _pickGatherInfoTarget(ThreatReport report) {
    // Le leader = on veut savoir ce qu'il a
    return report.leader ?? report.mostThreatening?.player;
  }

  /// 🔥 HARDCORE : Cible pour empêcher l'humain d'être sur le podium
  /// "Je ne peux pas gagner, mais toi non plus"
  static Player? _pickDenyHumanPodiumTarget(ThreatReport report) {
    // Si l'humain est sur le podium, c'est LUI la cible prioritaire
    if (report.humanOnPodium && report.humanPlayer != null) {
      return report.humanPlayer;
    }
    
    // Sinon on utilise la stratégie normale (bloquer le leader)
    if (report.hasOpponentWithOneCard) {
      final oneCardPlayers = report.opponents.where((o) => o.cardsLeft == 1).toList();
      if (oneCardPlayers.isNotEmpty) {
        oneCardPlayers.sort((a, b) => a.estimatedScore.compareTo(b.estimatedScore));
        return oneCardPlayers.first.player;
      }
    }
    
    return report.mostThreatening?.player;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS DE DÉCISION DUTCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcule si les adversaires ont probablement un score élevé
  /// (permet au bot de Dutch plus tôt si tout le monde galère)
  static bool opponentsLikelyStruggling(GameState gs, Player bot) {
    final report = analyzeOpponents(gs, bot);
    
    // Si la moyenne est > 12 et personne n'a moins de 3 cartes, ils galèrent
    return report.avgOpponentScore > 12 && report.minOpponentCards >= 3;
  }

  /// Calcule la confiance du bot dans son avance
  /// Retourne un score de 0 (pas d'avance) à 1 (avance écrasante)
  static double calculateLeadConfidence(GameState gs, Player bot) {
    final myScore = bot.getKnownScore();
    final report = analyzeOpponents(gs, bot);
    
    if (report.opponents.isEmpty) return 0.0;

    // Calcul de l'avance par rapport à la moyenne
    final scoreAdvantage = report.avgOpponentScore - myScore;
    
    // Normaliser sur une échelle 0-1
    // Une avance de 10 points = confiance maximale
    final confidence = (scoreAdvantage / 10.0).clamp(0.0, 1.0);
    
    return confidence;
  }

  /// Détermine si le bot est en position de gagner
  static bool isInWinningPosition(GameState gs, Player bot) {
    final myScore = bot.getKnownScore();
    final myCards = bot.hand.length;
    final report = analyzeOpponents(gs, bot);

    // Doit avoir moins de cartes que tout le monde
    if (myCards > report.minOpponentCards) return false;
    
    // Et un meilleur score que la moyenne
    if (myScore >= report.avgOpponentScore) return false;

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEGACY (compatibilité)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Détecte le joueur le plus menaçant (proche de gagner)
  static Player? getMostThreateningPlayer(GameState gs, Player bot) {
    final report = analyzeOpponents(gs, bot);
    return report.mostThreatening?.player;
  }

  /// Vérifie si le bot devrait contre-attaquer
  static bool shouldCounterAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    final report = analyzeOpponents(gs, bot);
    if (!report.hasOpponentWithOneCard && report.minOpponentCards > 2) {
      return false;
    }
    
    double counterChance = difficulty.name == "Platine" ? 0.90 :
                          difficulty.name == "Or" ? 0.80 :
                          difficulty.name == "Argent" ? 0.60 : 0.30;
    
    // Bonus si l'humain est en danger
    if (report.opponents.any((o) => o.isHuman && o.hasFewCards)) {
      counterChance += 0.10;
    }
    
    return _random.nextDouble() < counterChance;
  }

  /// Détermine si les bots devraient coordonner une attaque contre l'humain
  static bool shouldCoordinateAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    if (difficulty.name != "Or" && difficulty.name != "Platine" &&
        difficulty.name != "Hard" && difficulty.name != "Insane" &&
        difficulty.name != "Nightmare" && difficulty.name != "Impossible") {
      return false;
    }
    
    final report = analyzeOpponents(gs, bot);
    final humanThreat = report.opponents.where((o) => o.isHuman).firstOrNull;
    
    if (humanThreat == null) return false;
    
    // Si l'humain est dangereux
    if (humanThreat.hasFewCards || humanThreat.estimatedScore <= 8) {
      double coordChance = difficulty.name == "Platine" || difficulty.name == "Impossible" ? 0.85 :
                          difficulty.name == "Nightmare" ? 0.80 :
                          difficulty.name == "Insane" ? 0.75 : 0.70;
      return _random.nextDouble() < coordChance;
    }
    
    return false;
  }

  /// Cible prioritaire pour contre-attaque avec Valet
  static Player? getCounterAttackTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    if (!shouldCounterAttack(gs, bot, difficulty)) {
      return null;
    }
    
    return pickBestTarget(gs, bot, TargetMode.blockLeader, difficulty: difficulty);
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

  /// Analyse les défausses récentes pour estimer les mains adverses (legacy)
  static Map<String, double> analyzeDiscardPatterns(GameState gs, Player bot, BotDifficulty difficulty) {
    final report = analyzeOpponents(gs, bot);
    final Map<String, double> dangerScores = {};
    
    for (var opp in report.opponents) {
      dangerScores[opp.player.id] = opp.threatScore;
    }
    
    return dangerScores;
  }
}
