class BotDifficulty {
  final String name;
  final double forgetChancePerTurn;
  final double confusionOnSwap;
  final int dutchThreshold;
  final double reactionSpeed;
  final double matchAccuracy;
  final double reactionMatchChance;
  final int keepCardThreshold;

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

  static const BotDifficulty bronze = BotDifficulty(
    name: "Bronze",
    forgetChancePerTurn: 0.25,
    confusionOnSwap: 0.45,
    dutchThreshold: 12,
    reactionSpeed: 0.4,
    matchAccuracy: 0.65,
    reactionMatchChance: 0.20,
    keepCardThreshold: 8,
  );

  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.12,
    confusionOnSwap: 0.20,
    dutchThreshold: 8,
    reactionSpeed: 0.60,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.40,
    keepCardThreshold: 7,
  );

  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.01,
    confusionOnSwap: 0.02,
    dutchThreshold: 4,
    reactionSpeed: 0.92,
    matchAccuracy: 0.95,
    reactionMatchChance: 0.85,
    keepCardThreshold: 4,
  );

  static const BotDifficulty platinum = BotDifficulty(
    name: "Platine",
    forgetChancePerTurn: 0.0,      // N'oublie JAMAIS
    confusionOnSwap: 0.0,          // Ne se trompe JAMAIS sur les échanges
    dutchThreshold: 2,             // Dutch très agressif à 2 points
    reactionSpeed: 1.0,            // Réaction instantanée
    matchAccuracy: 1.0,            // Précision parfaite
    reactionMatchChance: 1.0,      // Réagit TOUJOURS s'il peut matcher
    keepCardThreshold: 2,          // N'accepte que les cartes 0-2 points
  );

  static BotDifficulty fromMMR(int mmr) {
    if (mmr < 300) {
      return bronze;
    } else if (mmr < 600) {
      return silver;
    } else if (mmr < 900) {
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
