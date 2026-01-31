import '../models/player.dart';
import '../models/game_state.dart';
import 'bot_difficulty.dart';

/// Interface pour les stratégies de comportement des bots
/// Principe SOLID: LSP - Les stratégies peuvent être substituées sans changer le comportement
/// Principe GRASP: Polymorphism - Comportements différents selon le type
abstract class BotStrategy {
  BotDifficulty get difficulty;
  
  /// Décider si le bot doit appeler Dutch
  bool shouldCallDutch(Player bot, GameState gameState);
  
  /// Décider quelle action prendre (tirer, défausser, pouvoir)
  BotAction makeDecision(Player bot, GameState gameState);
  
  /// Évaluer si une carte doit être gardée ou défaussée
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState);
}

/// Action que le bot peut prendre
class BotAction {
  final String type; // 'draw', 'discard', 'power', 'dutch'
  final Map<String, dynamic> details;
  
  BotAction(this.type, this.details);
}

/// Stratégie pour bot facile
class EasyBotStrategy implements BotStrategy {
  @override
  BotDifficulty get difficulty => const BotDifficulty(
    name: 'Easy',
    forgetChancePerTurn: 0.15,
    confusionOnSwap: 0.25,
    dutchThreshold: 8,
    reactionSpeed: 0.6,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.5,
    keepCardThreshold: 5,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final estimatedScore = bot.getEstimatedScore();
    return estimatedScore <= difficulty.dutchThreshold;
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique simple pour bot facile
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    return cardValue <= difficulty.keepCardThreshold;
  }
}

/// Stratégie pour bot moyen
class MediumBotStrategy implements BotStrategy {
  @override
  BotDifficulty get difficulty => const BotDifficulty(
    name: 'Medium',
    forgetChancePerTurn: 0.08,
    confusionOnSwap: 0.15,
    dutchThreshold: 6,
    reactionSpeed: 0.75,
    matchAccuracy: 0.88,
    reactionMatchChance: 0.60,
    keepCardThreshold: 4,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final estimatedScore = bot.getEstimatedScore();
    return estimatedScore <= difficulty.dutchThreshold;
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique équilibrée pour bot moyen
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    return cardValue <= difficulty.keepCardThreshold;
  }
}

/// Stratégie pour bot difficile
class HardBotStrategy implements BotStrategy {
  @override
  BotDifficulty get difficulty => const BotDifficulty(
    name: 'Hard',
    forgetChancePerTurn: 0.02,
    confusionOnSwap: 0.03,
    dutchThreshold: 3,
    reactionSpeed: 0.95,
    matchAccuracy: 0.98,
    reactionMatchChance: 0.90,
    keepCardThreshold: 3,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final estimatedScore = bot.getEstimatedScore();
    // Bot difficile prend plus de risques
    return estimatedScore <= difficulty.dutchThreshold;
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique avancée pour bot difficile
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    return cardValue <= difficulty.keepCardThreshold;
  }
}

/// Factory pour créer les stratégies de bots
/// Principe GRASP: Creator - Responsable de la création des stratégies
class BotStrategyFactory {
  static BotStrategy createStrategy(String skillLevel) {
    switch (skillLevel.toLowerCase()) {
      case 'bronze':
      case 'easy':
        return EasyBotStrategy();
      case 'silver':
      case 'medium':
        return MediumBotStrategy();
      case 'gold':
      case 'platinum':
      case 'hard':
        return HardBotStrategy();
      default:
        return MediumBotStrategy();
    }
  }
}
