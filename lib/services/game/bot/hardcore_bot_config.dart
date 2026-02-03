import 'dart:math';
import 'bot_difficulty.dart';

/// Niveaux de difficulté hardcore
enum HardcoreLevel {
  /// Difficile mais accessible - bots +150 MMR au-dessus du joueur
  hard,
  /// Très difficile - bots +250 MMR au-dessus du joueur
  insane,
  /// Cauchemar - bots ~70-85% winrate vs bon joueur
  nightmare,
  /// Mode boss - quasi imbattable (debug/défi)
  impossible,
}

/// Configuration des paramètres hardcore
/// Principe: "Hardcore floor + adaptation offset"
/// Les bots ne descendent JAMAIS en dessous du floor, même si le joueur est faible
class HardcoreBotConfig {
  // ═══════════════════════════════════════════════════════════════════════════
  // HARDCORE FLOORS - Planchers minimums absolus par niveau
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Paramètres floor pour Hard
  static const BotDifficulty hardFloor = BotDifficulty(
    name: "Hard",
    forgetChancePerTurn: 0.06,     // Max 6% oubli
    confusionOnSwap: 0.05,         // Max 5% confusion
    dutchThreshold: 4,             // Dutch à 4 points max
    reactionSpeed: 0.85,           // Réaction rapide
    matchAccuracy: 0.92,           // 92% précision
    reactionMatchChance: 0.85,     // Réagit 85% du temps
    keepCardThreshold: 3,          // Garde cartes ≤3
  );

  /// Paramètres floor pour Insane
  static const BotDifficulty insaneFloor = BotDifficulty(
    name: "Insane",
    forgetChancePerTurn: 0.03,     // Max 3% oubli
    confusionOnSwap: 0.02,         // Max 2% confusion
    dutchThreshold: 3,             // Dutch à 3 points max
    reactionSpeed: 0.95,           // Réaction très rapide
    matchAccuracy: 0.97,           // 97% précision
    reactionMatchChance: 0.95,     // Réagit 95% du temps
    keepCardThreshold: 2,          // Garde cartes ≤2
  );

  /// Paramètres floor pour Nightmare (ajusté pour 70-85% winrate)
  static const BotDifficulty nightmareFloor = BotDifficulty(
    name: "Nightmare",
    forgetChancePerTurn: 0.015,    // 1.5% oubli (pas parfait mais excellent)
    confusionOnSwap: 0.01,         // 1% confusion (légères erreurs)
    dutchThreshold: 2,             // Dutch à 2 points max
    reactionSpeed: 0.97,           // Très rapide mais pas instantané
    matchAccuracy: 0.98,           // 98% précision
    reactionMatchChance: 0.97,     // Réagit 97% du temps
    keepCardThreshold: 2,          // N'accepte que 0-2
  );

  /// Paramètres floor pour Impossible (mode boss/debug)
  static const BotDifficulty impossibleFloor = BotDifficulty(
    name: "Impossible",
    forgetChancePerTurn: 0.0,      // Mémoire parfaite
    confusionOnSwap: 0.0,          // Ne se trompe jamais
    dutchThreshold: 1,             // Dutch à 1 point seulement
    reactionSpeed: 1.0,            // Instantané
    matchAccuracy: 1.0,            // 100% précision
    reactionMatchChance: 1.0,      // Réagit TOUJOURS
    keepCardThreshold: 1,          // N'accepte que 0-1
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // MMR OFFSETS - Décalage au-dessus du joueur
  // ═══════════════════════════════════════════════════════════════════════════
  
  static const int hardMMROffset = 150;
  static const int insaneMMROffset = 250;
  static const int nightmareMMROffset = 350;  // Réduit de 400 → 350
  static const int impossibleMMROffset = 500; // Nouveau niveau boss

  /// MMR minimum pour chaque niveau (plancher absolu)
  static const int hardMinMMR = 1200;
  static const int insaneMinMMR = 1500;
  static const int nightmareMinMMR = 1650; // Réduit de 1700 → 1650
  static const int impossibleMinMMR = 1900;

  // ═══════════════════════════════════════════════════════════════════════════
  // MISTAKE RATES - Taux d'erreurs max par niveau
  // ═══════════════════════════════════════════════════════════════════════════
  
  static const double hardMaxMistakeRate = 0.06;      // 6% max
  static const double insaneMaxMistakeRate = 0.04;    // 4% max
  static const double nightmareMaxMistakeRate = 0.025; // 2.5% max (ajusté)
  static const double impossibleMaxMistakeRate = 0.005; // 0.5% max

  // ═══════════════════════════════════════════════════════════════════════════
  // REACTION TIMES - Temps de réaction par niveau (humanisé)
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Hard: temps humain rapide
  static const int hardMinReactionMs = 500;
  static const int hardMaxReactionMs = 1000;
  
  // Insane: très rapide mais encore humain
  static const int insaneMinReactionMs = 350;
  static const int insaneMaxReactionMs = 700;
  
  // Nightmare: rapide mais avec variation (pas robotique)
  static const int nightmareMinReactionMs = 250;
  static const int nightmareMaxReactionMs = 550;
  
  // Impossible: réflexes surhumains
  static const int impossibleMinReactionMs = 100;
  static const int impossibleMaxReactionMs = 300;

  // ═══════════════════════════════════════════════════════════════════════════
  // HESITATION NOISE - Simulation d'hésitation humaine
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Chance d'ajouter un délai d'hésitation (par difficulté)
  static const double hardHesitationChance = 0.25;
  static const double insaneHesitationChance = 0.15;
  static const double nightmareHesitationChance = 0.10;
  static const double impossibleHesitationChance = 0.0;
  
  /// Durée de l'hésitation en ms
  static const int minHesitationMs = 200;
  static const int maxHesitationMs = 600;

  // ═══════════════════════════════════════════════════════════════════════════
  // MÉTHODES PRINCIPALES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcule la difficulté effective pour un bot hardcore
  /// Prend le MAX entre le floor et les paramètres calculés depuis le skill
  static BotDifficulty getHardcoreDifficulty({
    required HardcoreLevel level,
    required int playerSkillEstimate,
  }) {
    final floor = _getFloor(level);
    final offset = _getMMROffset(level);
    final minMMR = _getMinMMR(level);
    
    // BotTargetSkill = max(minMMR, playerSkillEstimate + offset)
    final botTargetSkill = max(minMMR, playerSkillEstimate + offset);
    
    // Paramètres basés sur le skill cible
    final skillParams = _paramsFromSkill(botTargetSkill);
    
    // Retourne le MAX entre floor et skill params
    return _maxDifficulty(floor, skillParams, level.name);
  }

  /// Obtient le floor pour un niveau
  static BotDifficulty _getFloor(HardcoreLevel level) {
    switch (level) {
      case HardcoreLevel.hard:
        return hardFloor;
      case HardcoreLevel.insane:
        return insaneFloor;
      case HardcoreLevel.nightmare:
        return nightmareFloor;
      case HardcoreLevel.impossible:
        return impossibleFloor;
    }
  }

  /// Obtient l'offset MMR pour un niveau
  static int _getMMROffset(HardcoreLevel level) {
    switch (level) {
      case HardcoreLevel.hard:
        return hardMMROffset;
      case HardcoreLevel.insane:
        return insaneMMROffset;
      case HardcoreLevel.nightmare:
        return nightmareMMROffset;
      case HardcoreLevel.impossible:
        return impossibleMMROffset;
    }
  }

  /// Obtient le MMR minimum pour un niveau
  static int _getMinMMR(HardcoreLevel level) {
    switch (level) {
      case HardcoreLevel.hard:
        return hardMinMMR;
      case HardcoreLevel.insane:
        return insaneMinMMR;
      case HardcoreLevel.nightmare:
        return nightmareMinMMR;
      case HardcoreLevel.impossible:
        return impossibleMinMMR;
    }
  }

  /// Calcule les paramètres depuis le skill
  static BotDifficulty _paramsFromSkill(int skill) {
    // Normalisation: skill 800-2000 → 0-1
    final normalized = ((skill - 800) / 1200).clamp(0.0, 1.0);
    
    return BotDifficulty(
      name: 'SkillBased',
      forgetChancePerTurn: (0.10 * (1 - normalized)).clamp(0.0, 0.10),
      confusionOnSwap: (0.10 * (1 - normalized)).clamp(0.0, 0.10),
      dutchThreshold: (6 - (normalized * 5)).round().clamp(1, 6),
      reactionSpeed: (0.7 + normalized * 0.3).clamp(0.7, 1.0),
      matchAccuracy: (0.8 + normalized * 0.2).clamp(0.8, 1.0),
      reactionMatchChance: (0.7 + normalized * 0.3).clamp(0.7, 1.0),
      keepCardThreshold: (5 - (normalized * 4)).round().clamp(1, 5),
    );
  }

  /// Prend le max (plus dur) entre deux difficultés
  static BotDifficulty _maxDifficulty(
    BotDifficulty floor,
    BotDifficulty skill,
    String name,
  ) {
    return BotDifficulty(
      name: name,
      // Plus bas = plus dur pour les chances d'erreur
      forgetChancePerTurn: min(floor.forgetChancePerTurn, skill.forgetChancePerTurn),
      confusionOnSwap: min(floor.confusionOnSwap, skill.confusionOnSwap),
      // Plus bas = plus agressif pour Dutch
      dutchThreshold: min(floor.dutchThreshold, skill.dutchThreshold),
      // Plus haut = plus rapide/précis
      reactionSpeed: max(floor.reactionSpeed, skill.reactionSpeed),
      matchAccuracy: max(floor.matchAccuracy, skill.matchAccuracy),
      reactionMatchChance: max(floor.reactionMatchChance, skill.reactionMatchChance),
      // Plus bas = plus sélectif
      keepCardThreshold: min(floor.keepCardThreshold, skill.keepCardThreshold),
    );
  }

  /// Obtient le temps de réaction pour un niveau (avec humanisation)
  static int getReactionTime(HardcoreLevel level, Random random) {
    int baseTime;
    switch (level) {
      case HardcoreLevel.hard:
        baseTime = hardMinReactionMs + random.nextInt(hardMaxReactionMs - hardMinReactionMs);
        break;
      case HardcoreLevel.insane:
        baseTime = insaneMinReactionMs + random.nextInt(insaneMaxReactionMs - insaneMinReactionMs);
        break;
      case HardcoreLevel.nightmare:
        baseTime = nightmareMinReactionMs + random.nextInt(nightmareMaxReactionMs - nightmareMinReactionMs);
        break;
      case HardcoreLevel.impossible:
        baseTime = impossibleMinReactionMs + random.nextInt(impossibleMaxReactionMs - impossibleMinReactionMs);
        break;
    }
    
    // Ajouter hésitation aléatoire pour humaniser
    final hesitationChance = _getHesitationChance(level);
    if (random.nextDouble() < hesitationChance) {
      baseTime += minHesitationMs + random.nextInt(maxHesitationMs - minHesitationMs);
    }
    
    return baseTime;
  }

  /// Obtient la chance d'hésitation pour un niveau
  static double _getHesitationChance(HardcoreLevel level) {
    switch (level) {
      case HardcoreLevel.hard:
        return hardHesitationChance;
      case HardcoreLevel.insane:
        return insaneHesitationChance;
      case HardcoreLevel.nightmare:
        return nightmareHesitationChance;
      case HardcoreLevel.impossible:
        return impossibleHesitationChance;
    }
  }

  /// Obtient le taux d'erreur max pour un niveau
  static double getMaxMistakeRate(HardcoreLevel level) {
    switch (level) {
      case HardcoreLevel.hard:
        return hardMaxMistakeRate;
      case HardcoreLevel.insane:
        return insaneMaxMistakeRate;
      case HardcoreLevel.nightmare:
        return nightmareMaxMistakeRate;
      case HardcoreLevel.impossible:
        return impossibleMaxMistakeRate;
    }
  }

  /// Vérifie si le bot devrait faire une erreur (limité par le niveau)
  static bool shouldMakeMistake(HardcoreLevel level, Random random) {
    return random.nextDouble() < getMaxMistakeRate(level);
  }

  /// Vérifie si le niveau est considéré comme un mode "boss"
  static bool isBossMode(HardcoreLevel level) {
    return level == HardcoreLevel.impossible;
  }
}

/// Estimation du skill du joueur en temps réel pendant une partie
/// Avec lissage EMA pour éviter les oscillations yo-yo
class PlayerSkillEstimator {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Alpha pour le lissage EMA (0.15 = lissage progressif)
  static const double _emaAlpha = 0.15;
  
  /// Nombre d'actions minimum avant mise à jour
  static const int _updateEveryNActions = 3;
  
  /// Delta MMR maximum par tranche (anti-oscillation)
  static const int _maxDeltaPerUpdate = 40;
  
  /// Floor absolu pour le skill estimé
  static const int _minSkill = 600;
  static const int _maxSkill = 2000;

  // ═══════════════════════════════════════════════════════════════════════════
  // MÉTRIQUES ACCUMULÉES
  // ═══════════════════════════════════════════════════════════════════════════
  
  int _actionsCount = 0;
  int _actionsSinceLastUpdate = 0;
  int _goodDecisions = 0;
  int _badDecisions = 0;
  double _avgDecisionTimeMs = 0;
  int _powersUsedWell = 0;
  int _powersWasted = 0;
  int _dutchSuccesses = 0;
  int _dutchFailures = 0;
  
  // Historique des "obvious mistakes"
  int _obviousMistakesRecent = 0; // Dans les 5 dernières actions
  
  // Performance vs bots
  int _roundsWonVsBot = 0;
  int _roundsLostVsBot = 0;
  
  // Variance tracking (pour adaptation dynamique)
  List<int> _recentDeltas = [];
  
  // Skill estimé (mise à jour en continu avec EMA)
  int _estimatedSkill = 1000;
  int _rawSkillEstimate = 1000; // Avant lissage
  
  int get estimatedSkill => _estimatedSkill;
  
  /// Retourne le skill avec l'offset adapté au "stomp" status
  int getAdaptedSkillForHardcore(HardcoreLevel level) {
    final baseOffset = HardcoreBotConfig._getMMROffset(level);
    final minMMR = HardcoreBotConfig._getMinMMR(level);
    
    // Calcul de variance basé sur les performances récentes
    int varianceBonus = _calculateVarianceBonus();
    
    // Offset final = base + bonus variance
    int effectiveOffset = baseOffset + varianceBonus;
    
    // Skill cible = max(minMMR, playerSkill + offset)
    return max(minMMR, _estimatedSkill + effectiveOffset);
  }
  
  /// Calcule le bonus de variance (si joueur stomp, offset monte)
  int _calculateVarianceBonus() {
    if (_actionsCount < 10) return 0;
    
    // Si le joueur bat régulièrement les bots
    if (_roundsWonVsBot > _roundsLostVsBot * 2) {
      return 50; // +50 MMR si le joueur domine
    }
    
    // Si le joueur se fait dominer
    if (_roundsLostVsBot > _roundsWonVsBot * 2) {
      return -30; // -30 MMR (mais floor reste en place)
    }
    
    return 0;
  }

  /// Réinitialise l'estimateur pour une nouvelle partie
  void reset({int? initialMMR}) {
    _actionsCount = 0;
    _actionsSinceLastUpdate = 0;
    _goodDecisions = 0;
    _badDecisions = 0;
    _avgDecisionTimeMs = 0;
    _powersUsedWell = 0;
    _powersWasted = 0;
    _dutchSuccesses = 0;
    _dutchFailures = 0;
    _obviousMistakesRecent = 0;
    _roundsWonVsBot = 0;
    _roundsLostVsBot = 0;
    _recentDeltas = [];
    _estimatedSkill = initialMMR ?? 1000;
    _rawSkillEstimate = initialMMR ?? 1000;
  }

  /// Enregistre une décision du joueur
  void recordDecision({
    required bool wasGood,
    required int decisionTimeMs,
    bool wasObviousMistake = false,
  }) {
    _actionsCount++;
    _actionsSinceLastUpdate++;
    
    if (wasGood) {
      _goodDecisions++;
    } else {
      _badDecisions++;
    }
    
    if (wasObviousMistake) {
      _obviousMistakesRecent++;
    }
    
    // Decay des erreurs récentes
    if (_actionsCount % 5 == 0) {
      _obviousMistakesRecent = (_obviousMistakesRecent * 0.7).round();
    }
    
    // Moyenne mobile du temps de décision
    _avgDecisionTimeMs = (_avgDecisionTimeMs * (_actionsCount - 1) + decisionTimeMs) / _actionsCount;
    
    // Update toutes les N actions (pas à chaque action = anti-oscillation)
    if (_actionsSinceLastUpdate >= _updateEveryNActions) {
      _updateEstimate();
      _actionsSinceLastUpdate = 0;
    }
  }

  /// Enregistre l'utilisation d'un pouvoir
  void recordPowerUsage({required bool wasEffective}) {
    if (wasEffective) {
      _powersUsedWell++;
    } else {
      _powersWasted++;
    }
    _actionsSinceLastUpdate++;
    if (_actionsSinceLastUpdate >= _updateEveryNActions) {
      _updateEstimate();
      _actionsSinceLastUpdate = 0;
    }
  }

  /// Enregistre un appel Dutch
  void recordDutchCall({required bool wasSuccessful}) {
    if (wasSuccessful) {
      _dutchSuccesses++;
    } else {
      _dutchFailures++;
    }
    // Dutch est important, force une update
    _updateEstimate();
    _actionsSinceLastUpdate = 0;
  }

  /// Enregistre un round terminé (pour variance tracking)
  void recordRoundResult({required bool playerWon}) {
    if (playerWon) {
      _roundsWonVsBot++;
    } else {
      _roundsLostVsBot++;
    }
  }

  /// Met à jour l'estimation du skill avec lissage EMA
  void _updateEstimate() {
    if (_actionsCount < 3) return; // Besoin de données minimum
    
    // Calcul des ratios
    double decisionRatio = _goodDecisions / max(1, _goodDecisions + _badDecisions);
    double powerRatio = _powersUsedWell / max(1, _powersUsedWell + _powersWasted);
    double dutchRatio = _dutchSuccesses / max(1, _dutchSuccesses + _dutchFailures);
    
    // Facteur vitesse (plus rapide = potentiellement meilleur)
    // Mais pas trop rapide (< 500ms peut être des clics aléatoires)
    double speedFactor = 1.0;
    if (_avgDecisionTimeMs < 500) {
      speedFactor = 0.9; // Trop rapide, peut-être aléatoire
    } else if (_avgDecisionTimeMs < 1500) {
      speedFactor = 1.1; // Décisions rapides et réfléchies
    } else if (_avgDecisionTimeMs > 4000) {
      speedFactor = 0.95; // Très lent
    }
    
    // Pénalité pour erreurs évidentes
    double mistakePenalty = _obviousMistakesRecent * 0.05;
    
    // Score composite (0-1)
    double composite = (
      decisionRatio * 0.4 +
      powerRatio * 0.25 +
      dutchRatio * 0.35
    ) * speedFactor - mistakePenalty;
    composite = composite.clamp(0.0, 1.0);
    
    // Conversion en MMR estimé (700-1800 range)
    int newRawEstimate = (700 + composite * 1100).round();
    
    // Calcul du delta (avant clamp)
    int delta = newRawEstimate - _rawSkillEstimate;
    _recentDeltas.add(delta);
    if (_recentDeltas.length > 10) {
      _recentDeltas.removeAt(0);
    }
    
    // Clamp le delta pour éviter les variations brusques
    delta = delta.clamp(-_maxDeltaPerUpdate, _maxDeltaPerUpdate);
    _rawSkillEstimate = (_rawSkillEstimate + delta).clamp(_minSkill, _maxSkill);
    
    // Lissage EMA: newSkill = alpha * raw + (1-alpha) * old
    _estimatedSkill = ((_emaAlpha * _rawSkillEstimate) + ((1 - _emaAlpha) * _estimatedSkill)).round();
    _estimatedSkill = _estimatedSkill.clamp(_minSkill, _maxSkill);
  }

  /// Évalue si une décision de garde/défausse était bonne
  static bool evaluateCardDecision({
    required int drawnCardValue,
    required int? replacedCardValue,
    required bool discarded,
    required int knownHandSum,
    required int unknownCount,
  }) {
    // Estimation du score inconnu (moyenne attendue ~6)
    final estimatedUnknown = unknownCount * 6;
    final totalEstimated = knownHandSum + estimatedUnknown;
    
    if (discarded) {
      // Défausser une bonne carte (≤3) est mauvais
      if (drawnCardValue <= 3) return false;
      // Défausser une carte moyenne quand le score est bon est OK
      if (totalEstimated <= 10 && drawnCardValue >= 5) return true;
      // Défausser une mauvaise carte est toujours OK
      return drawnCardValue >= 6;
    } else {
      // Remplacer: bon si on améliore
      if (replacedCardValue == null) return true; // Découverte
      return drawnCardValue < replacedCardValue;
    }
  }

  /// Détecte une "obvious mistake" (erreur flagrante)
  static bool isObviousMistake({
    required int drawnCardValue,
    required int? replacedCardValue,
    required bool discarded,
    required int knownHandSum,
  }) {
    if (discarded) {
      // Défausser un 0-1-2 est une erreur évidente
      return drawnCardValue <= 2;
    } else {
      // Remplacer une bonne carte par une pire est une erreur évidente
      if (replacedCardValue != null && drawnCardValue > replacedCardValue + 3) {
        return true;
      }
    }
    return false;
  }
  
  /// Retourne true si le joueur fait beaucoup d'erreurs récemment
  bool get hasRecentMistakes => _obviousMistakesRecent >= 2;
  
  /// Retourne le ratio de décisions bonnes
  double get decisionQuality {
    if (_goodDecisions + _badDecisions == 0) return 0.5;
    return _goodDecisions / (_goodDecisions + _badDecisions);
  }
}
