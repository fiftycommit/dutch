import 'dart:math';
import 'bot_difficulty.dart';
import '../engine_random.dart';

/// Service de matchmaking pour générer des bots adaptés au niveau du joueur
///
/// Philosophie :
/// - Tous les bots suivent la MÊME logique (même cerveau)
/// - La différence vient de : mémoire, précision, réactivité
/// - Le skill n'est pas discret (Bronze/Argent/Difficile) mais CONTINU basé sur le MMR
class BotMatchmaking {
  static Random get _random => EngineRandom.instance;

  /// Génère une liste de difficultés de bot adaptées au MMR du joueur
  ///
  /// [playerMMR] : Le MMR actuel du joueur
  /// [botCount] : Nombre de bots à générer (1-3)
  /// [variance] : Variance autour du MMR du joueur (défaut: 100)
  ///
  /// Retourne une liste de BotDifficulty avec des skills variés autour du joueur
  static List<BotDifficulty> generateMatchedBots({
    required int playerMMR,
    required int botCount,
    int variance = 100,
  }) {
    final bots = <BotDifficulty>[];

    for (int i = 0; i < botCount; i++) {
      // Générer un MMR de bot autour du joueur avec variance
      // Plus le joueur est haut, plus les bots peuvent être légèrement au-dessus
      final mmrOffset = _random.nextInt(variance * 2) - variance;
      final botMMR = (playerMMR + mmrOffset).clamp(0, 1500);

      // Convertir le MMR en paramètres de bot (interpolation continue)
      bots.add(_mmrToDifficulty(botMMR, i));
    }

    return bots;
  }

  /// Convertit un MMR en BotDifficulty avec interpolation continue
  ///
  /// Au lieu de sauts discrets (Bronze/Argent/etc), on interpole les paramètres
  /// pour une courbe de difficulté fluide
  static BotDifficulty _mmrToDifficulty(int mmr, int botIndex) {
    // Normaliser le MMR sur une échelle 0-1 (0=débutant, 1=expert)
    // MMR 0 = 0.0, MMR 1200 = 1.0
    final double skill = (mmr / 1200.0).clamp(0.0, 1.0);

    // Interpolation des paramètres
    // Plus le skill est haut, plus le bot est précis/rapide/mémorise

    // Chance d'oubli : 15% à skill=0, 0% à skill=1
    final forgetChance = 0.15 * (1 - skill);

    // Confusion sur swap : 25% à skill=0, 0% à skill=1
    final confusion = 0.25 * (1 - skill);

    // Vitesse de réaction : 0.5 à skill=0, 1.0 à skill=1
    final reactionSpeed = 0.5 + (0.5 * skill);

    // Précision match : 0.6 à skill=0, 1.0 à skill=1
    final matchAccuracy = 0.6 + (0.4 * skill);

    // Chance de réaction match : 0.3 à skill=0, 1.0 à skill=1
    final reactionMatchChance = 0.3 + (0.7 * skill);

    // Nom basé sur le rang (pour l'affichage uniquement)
    final rankName = _getRankName(mmr, botIndex);

    return BotDifficulty(
      name: rankName,
      forgetChancePerTurn: forgetChance,
      confusionOnSwap: confusion,
      reactionSpeed: reactionSpeed,
      matchAccuracy: matchAccuracy,
      reactionMatchChance: reactionMatchChance,
    );
  }

  /// Obtient le nom du rang pour l'affichage
  static String _getRankName(int mmr, int botIndex) {
    // Noms uniques par bot pour l'affichage
    final suffixes = ['', ' II', ' III'];
    final suffix = botIndex < suffixes.length ? suffixes[botIndex] : '';

    if (mmr >= 600) return 'Difficile$suffix';
    if (mmr >= 300) return 'Argent$suffix';
    return 'Bronze$suffix';
  }

  /// Mode manuel : retourne une difficulté fixe basée sur le badge choisi
  ///
  /// Utilisé quand le joueur choisit explicitement un niveau dans le mode sandbox
  static BotDifficulty getFixedDifficulty(String badge) {
    switch (badge.toLowerCase()) {
      case 'bronze':
        return _mmrToDifficulty(150, 0); // MMR moyen Bronze
      case 'argent':
        return _mmrToDifficulty(450, 0); // MMR moyen Argent
      case 'or':
      case 'platine':
      case 'difficile':
        return _mmrToDifficulty(950, 0); // MMR moyen palier fort fusionné
      default:
        return _mmrToDifficulty(450, 0); // Défaut = Argent
    }
  }

  /// Calcule le "skill effectif" d'un bot pour l'affichage
  ///
  /// Retourne un pourcentage 0-100 basé sur les paramètres
  static int calculateEffectiveSkill(BotDifficulty difficulty) {
    // Moyenne pondérée des paramètres normalisés
    final memorySkill = 1 - difficulty.forgetChancePerTurn / 0.15;
    final precisionSkill = 1 - difficulty.confusionOnSwap / 0.25;
    final reactionSkill = difficulty.reactionSpeed;
    final matchSkill = difficulty.matchAccuracy;

    final avgSkill = (memorySkill + precisionSkill + reactionSkill + matchSkill) / 4;
    return (avgSkill * 100).round().clamp(0, 100);
  }

  /// Génère une description du niveau de bot pour l'UI
  static String getDifficultyDescription(BotDifficulty difficulty) {
    final skill = calculateEffectiveSkill(difficulty);

    if (skill >= 90) return 'Expert';
    if (skill >= 70) return 'Avancé';
    if (skill >= 50) return 'Intermédiaire';
    if (skill >= 30) return 'Débutant';
    return 'Novice';
  }
}
