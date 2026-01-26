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
    forgetChancePerTurn: 0.18,
    confusionOnSwap: 0.30,
    dutchThreshold: 10,
    reactionSpeed: 0.55,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.35,
    keepCardThreshold: 7,
  );

  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.08,
    confusionOnSwap: 0.12,
    dutchThreshold: 6,
    reactionSpeed: 0.75,
    matchAccuracy: 0.85,
    reactionMatchChance: 0.55,
    keepCardThreshold: 6,
  );

  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.01,
    confusionOnSwap: 0.01,
    dutchThreshold: 3,
    reactionSpeed: 0.96,
    matchAccuracy: 0.97,
    reactionMatchChance: 0.9,
    keepCardThreshold: 3,
  );

  static const BotDifficulty platinum = BotDifficulty(
    name: "Platine",
    forgetChancePerTurn: 0.0,      // N'oublie JAMAIS
    confusionOnSwap: 0.0,          // Ne se trompe JAMAIS sur les échanges
    dutchThreshold: 1,             // Dutch très agressif à 1 point
    reactionSpeed: 1.0,            // Réaction instantanée
    matchAccuracy: 1.0,            // Précision parfaite
    reactionMatchChance: 1.0,      // Réagit TOUJOURS s'il peut matcher
    keepCardThreshold: 1,          // N'accepte que les cartes 0-1 points
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
