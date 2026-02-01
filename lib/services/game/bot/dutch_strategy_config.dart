/// Configuration centralisée des seuils et paramètres de stratégie Dutch
///
/// Toutes les "valeurs magiques" sont ici pour faciliter l'équilibrage
/// et éviter les constantes éparpillées dans le code.
class DutchStrategyConfig {
  // ============================================
  // SEUILS DE SCORE POUR APPELER DUTCH
  // ============================================

  /// Seuils pour les bots Platine (stratégie agressive)
  static const PlatinumThresholds platinum = PlatinumThresholds();

  /// Seuils pour les bots Or (stratégie équilibrée)
  static const GoldThresholds gold = GoldThresholds();

  /// Seuils pour les bots Argent/Bronze (stratégie basique)
  static const BasicThresholds basic = BasicThresholds();

  // ============================================
  // PARAMÈTRES D'AUDACE
  // ============================================

  /// Bonus d'audace selon le nombre de cartes en main
  static const Map<int, double> cardCountAudacityBonus = {
    1: 3.0, // Une seule carte = très audacieux
    2: 2.0, // Deux cartes = audacieux
    3: 1.0, // Trois cartes = légèrement audacieux
  };

  /// Bonus d'audace pour tirages consécutifs mauvais
  static const int badDrawsThreshold = 3;
  static const double badDrawsAudacityPerDraw = 0.5;

  /// Pénalité d'audace par adversaire dangereux (≤2 cartes)
  static const double dangerousOpponentPenalty = 0.5;

  /// Multiplicateurs d'audace selon la difficulté
  static const Map<String, double> difficultyAudacityMultiplier = {
    'Bronze': 0.5,
    'Argent': 0.8,
    'Or': 1.0,
    'Platine': 1.2,
  };

  /// Limites de l'audace
  static const double minAudacity = -3.0;
  static const double maxAudacity = 5.0;

  // ============================================
  // PARAMÈTRES DE CONFIANCE DUTCH
  // ============================================

  /// Nombre d'essais récents à considérer pour la confiance
  static const int recentAttemptsCount = 5;

  /// Poids du taux de victoire dans le calcul de confiance
  static const double winRateWeight = 0.7;

  /// Poids de la précision dans le calcul de confiance
  static const double accuracyWeight = 0.3;

  /// Offset de confiance (0.5 = neutre)
  static const double confidenceOffset = 0.5;

  /// Limites de confiance
  static const double minConfidence = -1.0;
  static const double maxConfidence = 1.0;

  // ============================================
  // PARAMÈTRES DE BLUFF (Platine uniquement)
  // ============================================

  /// Probabilité de bluff en phase d'optimisation
  static const double bluffProbability = 0.20;

  /// Nombre de cartes min/max pour bluffer
  static const int bluffMinCards = 3;
  static const int bluffMaxCards = 4;

  // ============================================
  // AJUSTEMENTS DE PERSONNALITÉ
  // ============================================

  /// Multiplicateur du style boost (aggressiveness - caution)
  static const double styleBoostMultiplier = 2.0;

  /// Multiplicateur de la pénalité de rang
  static const double rankPenaltyMultiplier = 6.0;

  /// Multiplicateur de la pénalité de qualité Dutch
  static const double dutchQualityPenaltyMultiplier = 3.0;

  /// Limites de la pénalité d'écart de score
  static const double minScoreGapPenalty = -6.0;
  static const double maxScoreGapPenalty = 8.0;

  /// Base de la marge de sécurité
  static const double safetyMarginBase = 1.0;

  /// Multiplicateur de la marge de sécurité selon la qualité Dutch
  static const double safetyMarginQualityMultiplier = 2.5;

  /// Limites de la marge de sécurité
  static const double minSafetyMargin = 1.0;
  static const double maxSafetyMargin = 5.0;

  // ============================================
  // BONUS TOTAUX
  // ============================================

  /// Seuil de bonus total pour déclencher un Dutch opportuniste
  static const double opportunisticBonusThreshold = 3.0;

  /// Score max pour un Dutch opportuniste
  static const int opportunisticMaxScore = 8;
}

/// Seuils spécifiques aux bots Platine
class PlatinumThresholds {
  const PlatinumThresholds();

  /// Score max avec ≤2 cartes
  int get twoCardsMaxScore => 6;

  /// Score max avec avantage significatif en cartes (≥2 cartes de moins)
  int get significantAdvantageMaxScore => 10;

  /// Score max avec avantage en cartes ET en score
  int get dualAdvantageMaxScore => 8;

  /// Score max avec ≤3 cartes et très bas score
  int get lowScoreMaxScore => 4;

  /// Nombre de cartes pour le seuil lowScore
  int get lowScoreMaxCards => 3;

  /// Score max en phase endgame
  int get endgameMaxScore => 6;

  /// Avantage significatif = différence de cartes
  int get significantCardAdvantage => 2;
}

/// Seuils spécifiques aux bots Or
class GoldThresholds {
  const GoldThresholds();

  /// Score max avec ≤2 cartes
  int get twoCardsMaxScore => 5;

  /// Score max avec avantage significatif + avantage score
  int get significantAdvantageMaxScore => 8;

  /// Score max avec ≤3 cartes et très bas score
  int get lowScoreMaxScore => 3;

  /// Nombre de cartes pour le seuil lowScore
  int get lowScoreMaxCards => 3;

  /// Score max en phase endgame avec avantage cartes
  int get endgameMaxScore => 5;
}

/// Seuils pour les bots Bronze/Argent (basés sur behavior)
class BasicThresholds {
  const BasicThresholds();

  /// Seuils en phase endgame selon le behavior
  int endgameThreshold(String behavior, bool isBronze) {
    switch (behavior) {
      case 'fast':
        return isBronze ? 3 : 5;
      case 'aggressive':
      case 'balanced':
      default:
        return isBronze ? 2 : 4;
    }
  }

  /// Seuils en phase normale selon le behavior
  int normalThreshold(String behavior, bool isBronze) {
    switch (behavior) {
      case 'fast':
        return isBronze ? 2 : 4;
      case 'aggressive':
      case 'balanced':
      default:
        return isBronze ? 1 : 3;
    }
  }
}
