/// Service centralisé pour le calcul des points de classement (RP)
/// Utilisé par results_screen.dart et stats_service.dart
class RPCalculator {
  /// Définition des tiers de rang avec leurs seuils MMR
  static const Map<String, int> rankThresholds = {
    'Bronze': 0,
    'Argent': 300,
    'Or': 600,
    'Platine': 900,
  };

  /// Points de base par victoire/défaite selon le rang
  static const Map<String, Map<String, int>> basePoints = {
    'Bronze': {
      'win': 30,      // Victoire facile = peu de points
      'second': 15,
      'third': -25,
      'last': -50,    // Défaite = grosse perte
    },
    'Argent': {
      'win': 45,
      'second': 20,
      'third': -20,
      'last': -40,
    },
    'Or': {
      'win': 55,
      'second': 25,
      'third': -18,
      'last': -30,
    },
    'Platine': {
      'win': 70,      // Victoire difficile = beaucoup de points
      'second': 30,
      'third': -15,
      'last': -20,    // Défaite = petite perte (bots très forts)
    },
  };

  /// Bonus fixes (indépendants du rang)
  static const int dutchWinBonus = 20;           // +20 si Dutch + 1er
  static const int dutchPerfectBonus = 30;       // +30 supplémentaire si 0 points (total +50)
  static const int dutchFailPenalty = -30;       // -30 si Dutch sans être 1er

  /// Obtenir le nom du rang à partir du MMR
  static String getRankName(int mmr) {
    if (mmr >= rankThresholds['Platine']!) return 'Platine';
    if (mmr >= rankThresholds['Or']!) return 'Or';
    if (mmr >= rankThresholds['Argent']!) return 'Argent';
    return 'Bronze';
  }

  /// Obtenir la couleur du rang
  static int getRankColorValue(String rank) {
    switch (rank) {
      case 'Platine':
        return 0xFF00BFFF; // Bleu diamant brillant (Deep Sky Blue)
      case 'Or':
        return 0xFFFFD700; // Gold
      case 'Argent':
        return 0xFFC0C0C0; // Silver
      default:
        return 0xFFCD7F32; // Bronze
    }
  }

  /// Calculer le changement de RP pour une partie
  /// [playerRank] : position du joueur (1-N)
  /// [totalPlayers] : nombre total de joueurs dans la manche
  /// [currentMMR] : MMR actuel du joueur
  /// [calledDutch] : si le joueur a appelé Dutch
  /// [hasEmptyHand] : si le joueur a vidé sa main (toutes cartes défaussées)
  /// [isEliminated] : si le joueur est éliminé (Dutch raté en 1er)
  /// [isTournament] : si c'est une manche de tournoi (bonus/malus ajustés)
  /// [tournamentRound] : numéro de la manche (1, 2 ou 3)
  static RPResult calculateRP({
    required int playerRank,
    required int currentMMR,
    required bool calledDutch,
    required bool hasEmptyHand,
    bool isEliminated = false,
    int totalPlayers = 4,
    bool isTournament = false,
    int tournamentRound = 1,
  }) {
    String rank = getRankName(currentMMR);
    Map<String, int> points = basePoints[rank]!;
    
    int baseRP = 0;
    
    // Points de base selon la position RELATIVE au nombre de joueurs
    // En tournoi avec moins de 4 joueurs, adapter les positions
    if (playerRank == 1) {
      // Toujours le gagnant
      baseRP = points['win']!;
    } else if (playerRank == totalPlayers) {
      // Toujours le dernier = éliminé/perdant
      baseRP = points['last']!;
    } else if (totalPlayers == 4) {
      // 4 joueurs : classique
      if (playerRank == 2) {
        baseRP = points['second']!;
      } else {
        baseRP = points['third']!;
      }
    } else if (totalPlayers == 3) {
      // 3 joueurs : 2ème est entre second et third
      baseRP = ((points['second']! + points['third']!) / 2).round();
    } else {
      // 2 joueurs : soit 1er soit dernier (déjà traité)
      baseRP = points['last']!;
    }
    
    // Bonus tournoi selon la manche (plus on avance, plus c'est important)
    if (isTournament) {
      double tournamentMultiplier = 1.0;
      if (tournamentRound == 2) {
        tournamentMultiplier = 1.2; // Demi-finale
      } else if (tournamentRound == 3) {
        tournamentMultiplier = 1.5; // Finale
      }
      baseRP = (baseRP * tournamentMultiplier).round();
    }

    int bonusRP = 0;
    List<String> bonusDescriptions = [];

    // Bonus Dutch
    if (calledDutch) {
      if (playerRank == 1) {
        // Dutch gagnant : +20
        bonusRP += dutchWinBonus;
        bonusDescriptions.add('+$dutchWinBonus (Dutch)');
        
        // Dutch parfait (main vide) : +30 supplémentaire
        if (hasEmptyHand) {
          bonusRP += dutchPerfectBonus;
          bonusDescriptions.add('+$dutchPerfectBonus (Main vide)');
        }
      } else {
        // Dutch raté : -30
        bonusRP += dutchFailPenalty;
        bonusDescriptions.add('$dutchFailPenalty (Dutch raté)');
      }
    }

    int totalRP = baseRP + bonusRP;

    return RPResult(
      totalChange: totalRP,
      baseChange: baseRP,
      bonusChange: bonusRP,
      rank: rank,
      bonusDescriptions: bonusDescriptions,
    );
  }

  /// Obtenir le prochain rang et les points nécessaires
  static NextRankInfo? getNextRankInfo(int currentMMR) {
    String currentRank = getRankName(currentMMR);
    
    int nextThreshold;
    String nextRank;
    
    if (currentRank == 'Bronze') {
      nextThreshold = rankThresholds['Argent']!;
      nextRank = 'Argent';
    } else if (currentRank == 'Argent') {
      nextThreshold = rankThresholds['Or']!;
      nextRank = 'Or';
    } else if (currentRank == 'Or') {
      nextThreshold = rankThresholds['Platine']!;
      nextRank = 'Platine';
    } else {
      return null; // Déjà au rang max
    }

    return NextRankInfo(
      nextRank: nextRank,
      pointsNeeded: nextThreshold - currentMMR,
      threshold: nextThreshold,
    );
  }
}

/// Résultat du calcul de RP
class RPResult {
  final int totalChange;
  final int baseChange;
  final int bonusChange;
  final String rank;
  final List<String> bonusDescriptions;

  RPResult({
    required this.totalChange,
    required this.baseChange,
    required this.bonusChange,
    required this.rank,
    required this.bonusDescriptions,
  });

  String get formattedChange {
    if (totalChange >= 0) {
      return '+$totalChange RP';
    }
    return '$totalChange RP';
  }

  bool get isPositive => totalChange >= 0;
}

/// Info sur le prochain rang
class NextRankInfo {
  final String nextRank;
  final int pointsNeeded;
  final int threshold;

  NextRankInfo({
    required this.nextRank,
    required this.pointsNeeded,
    required this.threshold,
  });
}
