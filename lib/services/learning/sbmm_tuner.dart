import 'ai_telemetry_service.dart';

/// Tuner automatique pour le SBMM basé sur la télémétrie AI
/// 
/// Ajuste automatiquement le sweatFactor et les paramètres des bots
/// en fonction des performances observées :
/// - winrate joueur ~ 45-55%
/// - pacing correct (pas trop rush, pas trop long)
/// - pouvoirs qui font mal (impact positif)
/// - sandbagging modéré
class SbmmTuner {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTANTES DE CALIBRAGE
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Winrate cible (45-55%)
  static const double targetWinrateMin = 0.45;
  static const double targetWinrateMax = 0.55;
  
  /// Seuil d'efficacité des pouvoirs
  static const double minPowerEfficiency = 0.05;
  
  /// Nombre max de sandbags acceptables par partie
  static const int maxAcceptableSandbags = 3;
  
  /// Ajustement max du sweatFactor par partie
  static const double maxSweatAdjustment = 0.08;

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCUL DU NOUVEAU SWEAT FACTOR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Met à jour le sweatFactor en fonction des données de la partie
  /// 
  /// [prevSweat] : valeur actuelle (0.0 = facile, 1.0 = très dur)
  /// [summary] : résumé de télémétrie de la partie
  /// [recentWinrate] : winrate sur les N dernières parties (optionnel)
  /// 
  /// Retourne le nouveau sweatFactor entre 0.0 et 1.0
  static double update({
    required double prevSweat,
    required AiTelemetrySummary summary,
    double? recentWinrate,
  }) {
    double adjustment = 0.0;
    
    // ═══════════════════════════════════════════════════════════════════════
    // 1) AJUSTEMENT BASÉ SUR LE WINRATE
    // ═══════════════════════════════════════════════════════════════════════
    if (recentWinrate != null) {
      if (recentWinrate > targetWinrateMax) {
        // Joueur gagne trop → augmenter la difficulté
        adjustment += (recentWinrate - targetWinrateMax) * 0.3;
      } else if (recentWinrate < targetWinrateMin) {
        // Joueur perd trop → baisser la difficulté
        adjustment -= (targetWinrateMin - recentWinrate) * 0.3;
      }
    } else {
      // Pas de winrate historique, on se base sur cette partie uniquement
      if (summary.playerWon) {
        adjustment += 0.02; // Légère augmentation si victoire
      } else {
        adjustment -= 0.01; // Très légère baisse si défaite
      }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // 2) AJUSTEMENT BASÉ SUR LE PACING
    // ═══════════════════════════════════════════════════════════════════════
    if (summary.isTooFast) {
      // Parties trop courtes → les bots rushent trop → baisser l'agressivité
      adjustment -= 0.03;
    } else if (summary.isTooSlow) {
      // Parties trop longues → trop de sandbagging → augmenter l'agressivité
      adjustment += 0.02;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // 3) AJUSTEMENT BASÉ SUR LA QUALITÉ DES POUVOIRS
    // ═══════════════════════════════════════════════════════════════════════
    if (!summary.powersAreEffective && summary.totalPowerUses > 2) {
      // Les bots gaspillent leurs pouvoirs → pas besoin d'augmenter la difficulté
      // Plutôt corriger la stratégie de ciblage
      adjustment -= 0.01;
    } else if (summary.meanPowerImpactPerUse > 0.15) {
      // Les pouvoirs sont très efficaces → la difficulté est correcte ou élevée
      // Pas d'ajustement spécifique
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // 4) AJUSTEMENT BASÉ SUR LE SANDBAGGING
    // ═══════════════════════════════════════════════════════════════════════
    if (summary.excessiveSandbagging) {
      // Trop de sandbagging peut être frustrant
      // Si le joueur perd quand même, c'est double peine
      if (!summary.playerWon) {
        adjustment -= 0.02;
      }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // 5) APPLIQUER LES LIMITES
    // ═══════════════════════════════════════════════════════════════════════
    
    // Limiter l'ajustement max par partie
    adjustment = adjustment.clamp(-maxSweatAdjustment, maxSweatAdjustment);
    
    // Calculer et limiter le nouveau sweatFactor
    final newSweat = (prevSweat + adjustment).clamp(0.0, 1.0);
    
    return newSweat;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCUL DES PARAMÈTRES BOT À PARTIR DU SWEAT FACTOR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convertit le sweatFactor en paramètres bot concrets
  static BotSweatParameters getParameters(double sweatFactor) {
    // Clamp pour sécurité
    final sweat = sweatFactor.clamp(0.0, 1.0);
    
    return BotSweatParameters(
      // Taux d'erreur : 15% à sweat 0, 2% à sweat 1
      mistakeRate: _lerp(0.15, 0.02, sweat),
      
      // Rétention mémoire : 70% à sweat 0, 98% à sweat 1
      memoryRetention: _lerp(0.70, 0.98, sweat),
      
      // Précision d'estimation : 60% à sweat 0, 95% à sweat 1
      estimationAccuracy: _lerp(0.60, 0.95, sweat),
      
      // Taux d'utilisation offensive des pouvoirs : 30% à sweat 0, 80% à sweat 1
      powerOffensiveRate: _lerp(0.30, 0.80, sweat),
      
      // Seuil de Dutch (score max pour Dutch) : 12 à sweat 0, 6 à sweat 1
      dutchThreshold: _lerp(12.0, 6.0, sweat).round(),
      
      // Probabilité de sandbagging : 0% à sweat 0, 50% à sweat 1
      sandbagChance: _lerp(0.0, 0.50, sweat),
      
      // Agressivité de match (seuil de probabilité) : 30% à sweat 0, 15% à sweat 1
      matchThreshold: _lerp(0.30, 0.15, sweat),
    );
  }

  /// Interpolation linéaire
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  // ═══════════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Génère un diagnostic textuel basé sur la télémétrie
  static String diagnose(AiTelemetrySummary summary) {
    final issues = <String>[];
    final positive = <String>[];
    
    // Pacing
    if (summary.isTooFast) {
      issues.add('⚡ Parties trop rapides (${summary.totalActions} actions, cible: ${summary.targetActions})');
    } else if (summary.isTooSlow) {
      issues.add('🐢 Parties trop longues (${summary.totalActions} actions, cible: ${summary.targetActions})');
    } else {
      positive.add('✓ Pacing correct');
    }
    
    // Pouvoirs
    if (!summary.powersAreEffective && summary.totalPowerUses > 0) {
      issues.add('🎯 Pouvoirs peu efficaces (impact moyen: ${summary.meanPowerImpactPerUse.toStringAsFixed(2)})');
    } else if (summary.totalPowerUses > 0) {
      positive.add('✓ Pouvoirs bien utilisés (impact: ${summary.meanPowerImpactPerUse.toStringAsFixed(2)})');
    }
    
    // Sandbagging
    if (summary.excessiveSandbagging) {
      issues.add('🃏 Sandbagging excessif (${summary.totalSandbagTurns} fois)');
    } else if (summary.totalSandbagTurns > 0) {
      positive.add('✓ Sandbagging modéré (${summary.totalSandbagTurns} fois)');
    }
    
    // Résultat
    if (summary.playerWon) {
      positive.add('🏆 Joueur a gagné');
    } else {
      positive.add('🤖 Bot a gagné');
    }
    
    final buffer = StringBuffer('=== Diagnostic SBMM ===\n');
    for (final p in positive) {
      buffer.writeln(p);
    }
    if (issues.isNotEmpty) {
      buffer.writeln('--- Problèmes ---');
      for (final i in issues) {
        buffer.writeln(i);
      }
    }
    
    return buffer.toString();
  }
}

/// Paramètres de bot dérivés du sweatFactor
class BotSweatParameters {
  /// Taux d'erreur (0-1) - probabilité de faire une erreur
  final double mistakeRate;
  
  /// Rétention mémoire (0-1) - combien le bot se souvient
  final double memoryRetention;
  
  /// Précision d'estimation (0-1) - qualité des estimations de score
  final double estimationAccuracy;
  
  /// Taux offensif des pouvoirs (0-1) - préférence pour attaquer vs défendre
  final double powerOffensiveRate;
  
  /// Seuil de Dutch - score max pour appeler Dutch
  final int dutchThreshold;
  
  /// Probabilité de sandbagging (0-1)
  final double sandbagChance;
  
  /// Seuil de match - probabilité min pour tenter un match
  final double matchThreshold;

  const BotSweatParameters({
    required this.mistakeRate,
    required this.memoryRetention,
    required this.estimationAccuracy,
    required this.powerOffensiveRate,
    required this.dutchThreshold,
    required this.sandbagChance,
    required this.matchThreshold,
  });

  @override
  String toString() => '''
BotSweatParameters:
  mistakeRate: ${(mistakeRate * 100).toStringAsFixed(1)}%
  memoryRetention: ${(memoryRetention * 100).toStringAsFixed(1)}%
  estimationAccuracy: ${(estimationAccuracy * 100).toStringAsFixed(1)}%
  powerOffensiveRate: ${(powerOffensiveRate * 100).toStringAsFixed(1)}%
  dutchThreshold: $dutchThreshold
  sandbagChance: ${(sandbagChance * 100).toStringAsFixed(1)}%
  matchThreshold: ${(matchThreshold * 100).toStringAsFixed(1)}%
''';
}
