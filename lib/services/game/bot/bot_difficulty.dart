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
    forgetChancePerTurn: 0.08,      // Oublie moins souvent
    confusionOnSwap: 0.15,          // Se trompe moins
    dutchThreshold: 6,              // Dutch plus agressif
    reactionSpeed: 0.75,            // Réaction correcte
    matchAccuracy: 0.88,            // Bonne précision
    reactionMatchChance: 0.60,      // Réagit souvent
    keepCardThreshold: 5,           // Garde les bonnes cartes
  );

  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.02,     // Oublie très rarement
    confusionOnSwap: 0.03,         // Se trompe très rarement
    dutchThreshold: 3,             // Dutch agressif
    reactionSpeed: 0.95,           // Réaction très rapide
    matchAccuracy: 0.98,           // Excellente précision
    reactionMatchChance: 0.90,     // Réagit presque toujours
    keepCardThreshold: 3,          // N'accepte que les bonnes cartes
  );

  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.0,       // N'oublie jamais
    confusionOnSwap: 0.0,           // Ne se trompe jamais
    dutchThreshold: 2,              // Dutch plus agressif
    reactionSpeed: 1.0,             // Réaction instantanée
    matchAccuracy: 1.0,             // Précision parfaite
    reactionMatchChance: 1.0,       // Réagit TOUJOURS
    keepCardThreshold: 2,           // N'accepte que les très bonnes cartes
  );

  static const BotDifficulty platinum = BotDifficulty(
    name: "Platine",
    forgetChancePerTurn: 0.0,      // N'oublie JAMAIS
    confusionOnSwap: 0.0,          // Ne se trompe JAMAIS sur les échanges
    dutchThreshold: 0,             // Dutch ultra agressif à 0 point seulement
    reactionSpeed: 1.0,            // Réaction instantanée
    matchAccuracy: 1.0,            // Précision parfaite
    reactionMatchChance: 1.0,      // Réagit TOUJOURS s'il peut matcher
    keepCardThreshold: 0,          // N'accepte que les cartes 0 points (Roi)
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
