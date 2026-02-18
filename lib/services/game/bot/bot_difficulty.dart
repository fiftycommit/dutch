class BotDifficulty {
  final String name;
  final double forgetChancePerTurn;
  final double confusionOnSwap;
  final double reactionSpeed;
  final double matchAccuracy;
  final double reactionMatchChance;

  const BotDifficulty({
    required this.name,
    required this.forgetChancePerTurn,
    required this.confusionOnSwap,
    required this.reactionSpeed,
    required this.matchAccuracy,
    required this.reactionMatchChance,
  });

  static const BotDifficulty bronze = BotDifficulty(
    name: "Bronze",
    forgetChancePerTurn: 0.32,
    confusionOnSwap: 0.45,
    reactionSpeed: 0.35,
    matchAccuracy: 0.42,
    reactionMatchChance: 0.22,
  );

  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.24,
    confusionOnSwap: 0.32,
    reactionSpeed: 0.50,
    matchAccuracy: 0.60,
    reactionMatchChance: 0.34,
  );

  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.10,
    confusionOnSwap: 0.14,
    reactionSpeed: 0.78,
    matchAccuracy: 0.88,
    reactionMatchChance: 0.70,
  );

  static const BotDifficulty platinum = BotDifficulty(
    name: "Platine",
    forgetChancePerTurn: 0.0,
    confusionOnSwap: 0.0,
    reactionSpeed: 1.0,
    matchAccuracy: 1.0,
    reactionMatchChance: 1.0,
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
