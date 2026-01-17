class BotDifficulty {
  final String name;
  final double forgetChancePerTurn;    
  final double confusionOnSwap;        
  final int dutchThreshold;            
  final double reactionSpeed;          
  final double matchAccuracy;          

  const BotDifficulty({
    required this.name,
    required this.forgetChancePerTurn,
    required this.confusionOnSwap,
    required this.dutchThreshold,
    required this.reactionSpeed,
    required this.matchAccuracy,
  });

  static const BotDifficulty bronze = BotDifficulty(
    name: "Bronze",
    forgetChancePerTurn: 0.20,     
    confusionOnSwap: 0.40,         
    dutchThreshold: 8,             
    reactionSpeed: 0.5,            
    matchAccuracy: 0.7,            
  );

  static const BotDifficulty silver = BotDifficulty(
    name: "Argent",
    forgetChancePerTurn: 0.09,     
    confusionOnSwap: 0.14,         
    dutchThreshold: 5,             
    reactionSpeed: 0.75,           
    matchAccuracy: 0.85,           
  );

  static const BotDifficulty gold = BotDifficulty(
    name: "Or",
    forgetChancePerTurn: 0.04,     
    confusionOnSwap: 0.02,          
    dutchThreshold: 4,             
    reactionSpeed: 1.0,            
    matchAccuracy: 0.95,           
  );

  static BotDifficulty fromMMR(int mmr) {
    if (mmr < 150) {
      return bronze;
    } else if (mmr < 450) {
      return silver;
    } else {
      return gold;
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
      default:
        return silver;
    }
  }

  @override
  String toString() => name;
}