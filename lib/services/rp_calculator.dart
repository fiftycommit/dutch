/// Service centralisé pour le calcul des points de classement (RP)
/// Utilisé par results_screen.dart et stats_service.dart
class RPCalculator {
  /// Définition des tiers de rang avec leurs seuils MMR
  static const Map<String, int> rankThresholds = {
    'Bronze': 0,
    'Argent': 150,
    'Or': 450,
    'Platine': 800,
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
        return 0xFF00CED1; // Cyan/Turquoise
      case 'Or':
        return 0xFFFFD700; // Gold
      case 'Argent':
        return 0xFFC0C0C0; // Silver
      default:
        return 0xFFCD7F32; // Bronze
    }
  }

  /// Calculer le changement de RP pour une partie
  /// [playerRank] : position du joueur (1-4)
  /// [currentMMR] : MMR actuel du joueur
  /// [calledDutch] : si le joueur a appelé Dutch
  /// [hasEmptyHand] : si le joueur a vidé sa main (toutes cartes défaussées)
  /// [isEliminated] : si le joueur est éliminé (Dutch raté en 1er)
  static RPResult calculateRP({
    required int playerRank,
    required int currentMMR,
    required bool calledDutch,
    required bool hasEmptyHand,
    bool isEliminated = false,
  }) {
    String rank = getRankName(currentMMR);
    Map<String, int> points = basePoints[rank]!;
    
    int baseRP = 0;
    
    // Points de base selon la position
    switch (playerRank) {
      case 1:
        baseRP = points['win']!;
        break;
      case 2:
        baseRP = points['second']!;
        break;
      case 3:
        baseRP = points['third']!;
        break;
      case 4:
        baseRP = points['last']!;
        break;
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
