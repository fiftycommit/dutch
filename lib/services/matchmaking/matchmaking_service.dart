import 'dart:math';

import '../../models/player_learning_data.dart';

/// Configuration des seuils et paramètres de matchmaking
class MatchmakingConfig {
  // Plages MMR pour les rangs cosmétiques (affichage uniquement)
  static const int bronzeMax = 299;
  static const int silverMax = 599;
  static const int goldMax = 899;
  // Au-dessus de goldMax = Platine/Diamant

  // Facteur de progression vers le palier suivant (0.0 = début du rang, 1.0 = palier)
  // Plus on approche de 1.0, plus les bots sont forts
  static const double palierBoostMax = 0.35; // Boost max à l'approche du palier

  // Paramètres de difficulté des bots
  static const double minBotSkillMultiplier = 0.7; // Bot le plus faible = 70% du joueur
  static const double maxBotSkillMultiplier = 1.3; // Bot le plus fort = 130% du joueur

  // Écart de skill entre bots dans une même partie
  static const double botVarianceBase = 0.15; // Variance de base entre bots
}

/// Représente le niveau calculé d'un bot pour le matchmaking
class BotMatchmakingProfile {
  final double skillMultiplier; // Multiplicateur de skill par rapport au joueur
  final double effectiveMMR; // MMR "effectif" du bot
  final Map<String, double> adjustedParameters; // Paramètres AI ajustés

  const BotMatchmakingProfile({
    required this.skillMultiplier,
    required this.effectiveMMR,
    required this.adjustedParameters,
  });
}

/// Service de matchmaking adaptatif
///
/// Principe : Les rangs (Bronze/Argent/Or/Platine) sont cosmétiques.
/// La vraie difficulté est calculée à partir du MMR du joueur.
/// Plus on se rapproche d'un palier, plus les bots deviennent difficiles.
class MatchmakingService {
  static final Random _random = Random();

  /// Calcule la progression vers le prochain palier (0.0 à 1.0)
  /// 0.0 = vient de monter de rang, 1.0 = sur le point de passer au rang suivant
  static double getPalierProgress(int mmr) {
    int rangeStart;
    int rangeEnd;

    if (mmr <= MatchmakingConfig.bronzeMax) {
      rangeStart = 0;
      rangeEnd = MatchmakingConfig.bronzeMax;
    } else if (mmr <= MatchmakingConfig.silverMax) {
      rangeStart = MatchmakingConfig.bronzeMax + 1;
      rangeEnd = MatchmakingConfig.silverMax;
    } else if (mmr <= MatchmakingConfig.goldMax) {
      rangeStart = MatchmakingConfig.silverMax + 1;
      rangeEnd = MatchmakingConfig.goldMax;
    } else {
      // Platine/Diamant : progression continue
      rangeStart = MatchmakingConfig.goldMax + 1;
      rangeEnd = rangeStart + 300; // Range de 300 MMR
      // Pour les très hauts MMR, on cap à 1.0
      if (mmr > rangeEnd) return 1.0;
    }

    final progress = (mmr - rangeStart) / (rangeEnd - rangeStart);
    return progress.clamp(0.0, 1.0);
  }

  /// Calcule le boost de difficulté à l'approche du palier
  /// Utilise une courbe exponentielle pour un défi progressif
  static double getPalierBoost(int mmr) {
    final progress = getPalierProgress(mmr);
    // Courbe exponentielle : plus fort vers la fin du palier
    // f(x) = x^2 * maxBoost
    return pow(progress, 2).toDouble() * MatchmakingConfig.palierBoostMax;
  }

  /// Génère les profils de matchmaking pour les bots d'une partie
  ///
  /// [playerProfile] : Profil du joueur humain
  /// [botCount] : Nombre de bots à créer
  /// [forceChallenge] : Si true, tous les bots seront légèrement plus forts
  ///
  /// Distribution adaptative des bots :
  /// - Joueur débutant (MMR < 400) : faible/égal/fort
  /// - Joueur intermédiaire : égal/égal/fort
  /// - Joueur avancé (MMR > 700 ou proche palier) : égal/fort/boss
  /// - Joueur expert (MMR > 1000) : fort/fort/boss
  static List<BotMatchmakingProfile> generateBotProfiles({
    required PlayerProfile playerProfile,
    required int botCount,
    bool forceChallenge = false,
  }) {
    final playerMMR = playerProfile.mmr;
    final playerParams = playerProfile.learnedParameters;
    final palierBoost = getPalierBoost(playerMMR);
    final palierProgress = getPalierProgress(playerMMR);

    // Déterminer le niveau de difficulté minimum selon le skill du joueur
    // Plus le joueur est fort, plus le "plancher" de difficulté monte
    final double minMultiplierForPlayer = _calculateMinMultiplier(
      playerMMR,
      palierProgress,
    );

    final profiles = <BotMatchmakingProfile>[];

    for (int i = 0; i < botCount; i++) {
      // Distribution de base des bots
      double baseMultiplier = _calculateBaseMultiplier(
        botIndex: i,
        botCount: botCount,
        playerMMR: playerMMR,
        minMultiplier: minMultiplierForPlayer,
      );

      // Appliquer le boost de palier (plus on approche du palier, plus c'est dur)
      final adjustedMultiplier = baseMultiplier + palierBoost;

      // Challenge forcé (ex: fin de tournoi)
      final finalMultiplier = forceChallenge
          ? adjustedMultiplier + 0.1
          : adjustedMultiplier;

      // Clamp dans les limites configurées
      final clampedMultiplier = finalMultiplier.clamp(
        MatchmakingConfig.minBotSkillMultiplier,
        MatchmakingConfig.maxBotSkillMultiplier,
      );

      // Calculer le MMR effectif du bot
      final effectiveMMR = (playerMMR * clampedMultiplier).round();

      // Ajuster les paramètres AI selon le multiplicateur
      final adjustedParams = _adjustParametersForSkill(
        playerParams,
        clampedMultiplier,
        playerMMR,
      );

      profiles.add(BotMatchmakingProfile(
        skillMultiplier: clampedMultiplier,
        effectiveMMR: effectiveMMR.toDouble(),
        adjustedParameters: adjustedParams,
      ));
    }

    return profiles;
  }

  /// Calcule le multiplicateur minimum selon le niveau du joueur
  /// Plus le joueur est fort, plus le plancher monte
  static double _calculateMinMultiplier(int playerMMR, double palierProgress) {
    // Seuils de MMR pour ajuster la difficulté minimale
    if (playerMMR >= 1200) {
      // Diamant : tous les bots sont forts minimum
      return 1.05;
    } else if (playerMMR >= 900) {
      // Platine : pas de bot faible
      return 1.0 + palierProgress * 0.05;
    } else if (playerMMR >= 700) {
      // Or avancé : bots au moins égaux
      return 0.95 + palierProgress * 0.05;
    } else if (playerMMR >= 500) {
      // Argent avancé : bots presque égaux
      return 0.90 + palierProgress * 0.05;
    } else if (playerMMR >= 300) {
      // Argent : légère progression
      return 0.85 + palierProgress * 0.05;
    } else {
      // Bronze : distribution normale (peut avoir des bots faibles)
      return 0.80 + palierProgress * 0.05;
    }
  }

  /// Calcule le multiplicateur de base pour un bot selon sa position
  static double _calculateBaseMultiplier({
    required int botIndex,
    required int botCount,
    required int playerMMR,
    required double minMultiplier,
  }) {
    if (botCount == 1) {
      // Un seul bot : au niveau du joueur ou légèrement au-dessus
      return max(1.0, minMultiplier) + _random.nextDouble() * 0.1;
    }

    // Calculer la position relative du bot (0.0 = premier, 1.0 = dernier)
    final position = botIndex / (botCount - 1);

    // Distribution : du plus faible au plus fort
    // Premier bot : minMultiplier
    // Dernier bot : "boss" (1.10 - 1.25)
    final bossMultiplier = 1.10 + _random.nextDouble() * 0.15;

    // Interpolation linéaire entre min et boss
    final baseMultiplier = minMultiplier + (bossMultiplier - minMultiplier) * position;

    // Ajouter un peu de variance
    final variance = (_random.nextDouble() - 0.5) * 0.08;

    return baseMultiplier + variance;
  }

  /// Ajuste les paramètres AI selon le niveau de skill cible
  static Map<String, double> _adjustParametersForSkill(
    Map<String, dynamic> baseParams,
    double skillMultiplier,
    int playerMMR,
  ) {
    double getParam(String key, double fallback) {
      final v = baseParams[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    // Le skill multiplier influence la qualité des décisions
    // > 1.0 = meilleur que le joueur, < 1.0 = moins bon
    final skillFactor = skillMultiplier;
    final isStronger = skillFactor > 1.0;
    final delta = (skillFactor - 1.0).abs();

    // Mémoire : les bots plus forts ont une meilleure mémoire
    double baseMemoryAccuracy = getParam('memoryAccuracy', 0.7);
    double memoryAccuracy = isStronger
        ? (baseMemoryAccuracy + delta * 0.3).clamp(0.0, 0.98)
        : (baseMemoryAccuracy - delta * 0.2).clamp(0.5, 1.0);

    // Seuil Dutch : les bots plus forts sont plus précis
    double baseDutchThreshold = getParam('dutchThreshold', 15.0);
    double dutchThreshold = isStronger
        ? (baseDutchThreshold - delta * 8).clamp(3.0, 25.0)
        : (baseDutchThreshold + delta * 5).clamp(5.0, 30.0);

    // Qualité Dutch : les bots plus forts réussissent mieux leurs Dutch
    double baseDutchQuality = getParam('dutchQuality', 0.5);
    double dutchQuality = isStronger
        ? (baseDutchQuality + delta * 0.4).clamp(0.0, 0.95)
        : (baseDutchQuality - delta * 0.3).clamp(0.2, 1.0);

    // Agressivité : ajustée selon le style du joueur
    double baseAggressiveness = getParam('aggressiveness', 0.5);
    // Ajouter de la variance pour des styles de jeu différents
    double aggressiveness = (baseAggressiveness + (_random.nextDouble() - 0.5) * 0.3)
        .clamp(0.2, 0.9);

    // Prudence : inversement proportionnelle à l'agressivité avec du bruit
    double caution = (1.0 - aggressiveness + (_random.nextDouble() - 0.5) * 0.2)
        .clamp(0.2, 0.9);

    // Tolérance au risque : les bots plus forts prennent des risques calculés
    double baseRiskTolerance = getParam('riskTolerance', 0.5);
    double riskTolerance = isStronger
        ? (baseRiskTolerance + delta * 0.2).clamp(0.3, 0.8)
        : (baseRiskTolerance - delta * 0.15).clamp(0.2, 0.7);

    // Vitesse de décision : les bots plus forts sont plus rapides
    double baseDecisionSpeed = getParam('decisionSpeed', 2000.0);
    double decisionSpeed = isStronger
        ? (baseDecisionSpeed * (1.0 - delta * 0.3)).clamp(800.0, 3000.0)
        : (baseDecisionSpeed * (1.0 + delta * 0.2)).clamp(1000.0, 5000.0);

    // Utilisation des pouvoirs
    double basePowerUsageRate = getParam('powerUsageRate', 0.5);
    double powerUsageRate = (basePowerUsageRate + (skillFactor - 1.0) * 0.3)
        .clamp(0.3, 0.9);

    // Stratégie de ciblage basée sur le niveau
    // Les bots plus forts ciblent intelligemment (leader ou weak)
    // Les bots plus faibles sont plus aléatoires
    String targetingStrategy;
    if (skillFactor > 1.1) {
      targetingStrategy = _random.nextBool() ? 'leader' : 'weak';
    } else if (skillFactor < 0.9) {
      targetingStrategy = 'random';
    } else {
      final rand = _random.nextDouble();
      if (rand < 0.4) {
        targetingStrategy = 'leader';
      } else if (rand < 0.7) {
        targetingStrategy = 'weak';
      } else {
        targetingStrategy = 'random';
      }
    }

    return {
      'memoryAccuracy': memoryAccuracy,
      'memoryRetention': (memoryAccuracy * 0.95).clamp(0.5, 0.98),
      'dutchThreshold': dutchThreshold,
      'dutchQuality': dutchQuality,
      'aggressiveness': aggressiveness,
      'caution': caution,
      'riskTolerance': riskTolerance,
      'decisionSpeed': decisionSpeed,
      'powerUsageRate': powerUsageRate,
      'powerDefensiveRate': getParam('powerDefensiveRate', 0.5),
      'powerOffensiveRate': getParam('powerOffensiveRate', 0.5),
      'adaptability': (0.5 + (skillFactor - 1.0) * 0.3).clamp(0.3, 0.9),
      'targetingStrategy': targetingStrategy == 'leader' ? 0.0 : (targetingStrategy == 'weak' ? 1.0 : 2.0),
      'aggressiveness_winning': (aggressiveness * 0.8).clamp(0.2, 0.8),
      'aggressiveness_losing': (aggressiveness * 1.2).clamp(0.3, 0.95),
      'caution_winning': (caution * 1.2).clamp(0.3, 0.95),
      'caution_losing': (caution * 0.8).clamp(0.2, 0.8),
      'scoreGapWeight': isStronger ? 0.8 : 0.5,
      'rankPenalty': 0.0, // Sera mis à jour par BotTrainingService
      'ghostInfluence': 0.0, // Sera mis à jour si nécessaire
      'ghostDutchThreshold': dutchThreshold,
    };
  }

  /// Retourne le nom du rang cosmétique pour un MMR donné
  static String getRankName(int mmr) {
    if (mmr <= MatchmakingConfig.bronzeMax) return 'Bronze';
    if (mmr <= MatchmakingConfig.silverMax) return 'Argent';
    if (mmr <= MatchmakingConfig.goldMax) return 'Or';
    if (mmr <= 1200) return 'Platine';
    return 'Diamant';
  }

  /// Retourne le MMR minimum pour atteindre le prochain rang
  static int getNextRankMMR(int currentMMR) {
    if (currentMMR <= MatchmakingConfig.bronzeMax) {
      return MatchmakingConfig.bronzeMax + 1;
    }
    if (currentMMR <= MatchmakingConfig.silverMax) {
      return MatchmakingConfig.silverMax + 1;
    }
    if (currentMMR <= MatchmakingConfig.goldMax) {
      return MatchmakingConfig.goldMax + 1;
    }
    if (currentMMR <= 1200) {
      return 1201; // Vers Diamant
    }
    return currentMMR + 100; // Progression continue en Diamant
  }

  /// Calcule le pourcentage de progression vers le prochain rang (pour UI)
  static double getRankProgressPercent(int mmr) {
    return getPalierProgress(mmr) * 100;
  }
}
