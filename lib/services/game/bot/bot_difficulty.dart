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

  /// Profil fort unique fusionné depuis les anciens paliers Or/Platine.
  /// La précision mécanique reste au niveau Platine; la stratégie métier
  /// filtre ensuite les coups trop agressifs.
  static const BotDifficulty difficult = BotDifficulty(
    name: "Difficile",
    forgetChancePerTurn: 0.0,
    confusionOnSwap: 0.0,
    reactionSpeed: 1.0,
    matchAccuracy: 1.0,
    reactionMatchChance: 1.0,
  );

  static const BotDifficulty gold = difficult;
  static const BotDifficulty platinum = difficult;

  static BotDifficulty fromMMR(int mmr) {
    if (mmr < 300) {
      return bronze;
    } else if (mmr < 600) {
      return silver;
    } else {
      return difficult;
    }
  }

  static BotDifficulty fromRank(String rank) {
    switch (rank) {
      case "Bronze":
        return bronze;
      case "Argent":
        return silver;
      case "Or":
      case "Platine":
      case "Difficile":
        return difficult;
      default:
        return silver;
    }
  }

  @override
  String toString() => name;
}
