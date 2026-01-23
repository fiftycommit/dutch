class BotDifficulty {
  final String name;
  final double forgetChancePerTurn;    // Chance d'oublier une carte connue
  final double confusionOnSwap;        // Chance de se tromper après échange
  final int dutchThreshold;            // Score max pour appeler Dutch
  final double reactionSpeed;          // Vitesse de réaction (0-1)
  final double matchAccuracy;          // Précision des matchs
  final double reactionMatchChance;    // â NOUVEAU: Chance de tenter un match en réaction
  final int keepCardThreshold;         // â NOUVEAU: Seuil pour garder une carte piochée

  const BotDifficulty({
    required this.name,
    required this.forgetChancePerTurn,
    required this.confusionOnSwap,
    required this.dutchThreshold,
    required this.reactionSpeed,
    required this.matchAccuracy,
    required this.reactionMatchChance,
    required this.keepCardThreshold,
  });

  // â BRONZE : Bot débutant, fait beaucoup d'erreurs
  static const BotDifficulty bronze = BotDifficulty(
    name: "Bronze",
    forgetChancePerTurn: 0.25,      // Oublie souvent (25%)
    confusionOnSwap: 0.45,          // Très confus après échange (45%)
    dutchThreshold: 12,             // Dutch seulement si très bas score
    reactionSpeed: 0.4,             // Lent Ã  réagir
    matchAccuracy: 0.65,            // Rate souvent ses matchs (35% d'erreur)
    reactionMatchChance: 0.20,      // Tente rarement de matcher en réaction
    keepCardThreshold: 8,           // Garde les cartes jusqu'Ã  8 pts
  );

  // â ARGENT : Bot intermédiaire, joue correctement
  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.10,      // Oublie parfois (10%)
    confusionOnSwap: 0.15,          // Parfois confus (15%)
    dutchThreshold: 6,              // Dutch Ã  6 pts ou moins
    reactionSpeed: 0.70,            // Réaction correcte
    matchAccuracy: 0.85,            // Bon au match (15% d'erreur)
    reactionMatchChance: 0.50,      // 50% de chance de matcher en réaction
    keepCardThreshold: 6,           // Garde les cartes jusqu'Ã  6 pts
  );

  // â OR : Bot expert, très stratégique
  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.02,      // Oublie très rarement (2%)
    confusionOnSwap: 0.05,          // Quasi jamais confus (5%)
    dutchThreshold: 4,              // Dutch agressif Ã  4 pts
    reactionSpeed: 0.95,            // Réaction quasi instantanée
    matchAccuracy: 0.95,            // Excellent au match (5% d'erreur)
    reactionMatchChance: 0.80,      // Match très souvent en réaction (80%)
    keepCardThreshold: 5,           // Exigeant, garde seulement â¤5 pts
  );

  // â NOUVEAU : PLATINE - Bot quasi parfait (pour mode très difficile)
  static const BotDifficulty platinum = BotDifficulty(
    name: "Platine",
    forgetChancePerTurn: 0.01,      // Mémoire quasi parfaite
    confusionOnSwap: 0.02,          // Presque jamais confus
    dutchThreshold: 3,              // Dutch très agressif
    reactionSpeed: 1.0,             // Réaction instantanée
    matchAccuracy: 0.98,            // Match quasi parfait
    reactionMatchChance: 0.90,      // Match presque toujours en réaction
    keepCardThreshold: 4,           // Très exigeant
  );

  static BotDifficulty fromMMR(int mmr) {
    if (mmr < 100) {
      return bronze;
    } else if (mmr < 300) {
      return silver;
    } else if (mmr < 600) {
      return gold;
    } else {
      return platinum;
    }
  }

  static BotDifficulty fromRank(String rank) {
    switch (rank) {
      case "Bronze":
        return bronze;
      case "Argent":
        return silver;
      case "Or":
        return gold;
      case "Platine":
        return platinum;
      default:
        return silver;
    }
  }

  @override
  String toString() => name;
}