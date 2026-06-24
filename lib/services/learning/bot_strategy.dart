import 'dart:math';
import '../../models/player.dart';
import '../../models/game_state.dart';
import '../game/bot/bot_config.dart';
import '../game/bot/bot_difficulty.dart';
import '../game/bot/bot_dutch_strategy.dart';

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
    reactionSpeed: 0.6,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.5,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final phase = BotConfig.getBotPhase(bot, gameState);
    return BotDutchStrategy.shouldCallDutch(gameState, bot, difficulty, phase);
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique simple pour bot facile
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    final knownValues = <int>[];
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null) {
        knownValues.add(card.points);
      }
    }
    if (knownValues.isEmpty) return true;
    final maxKnown = knownValues.reduce(max);
    return cardValue < maxKnown;
  }
}

/// Stratégie pour bot moyen
class MediumBotStrategy implements BotStrategy {
  @override
  BotDifficulty get difficulty => const BotDifficulty(
    name: 'Medium',
    forgetChancePerTurn: 0.08,
    confusionOnSwap: 0.15,
    reactionSpeed: 0.75,
    matchAccuracy: 0.88,
    reactionMatchChance: 0.60,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final phase = BotConfig.getBotPhase(bot, gameState);
    return BotDutchStrategy.shouldCallDutch(gameState, bot, difficulty, phase);
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique équilibrée pour bot moyen
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    final knownValues = <int>[];
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null) {
        knownValues.add(card.points);
      }
    }
    if (knownValues.isEmpty) return true;
    final maxKnown = knownValues.reduce(max);
    return cardValue < maxKnown;
  }
}

/// Stratégie pour bot difficile
class HardBotStrategy implements BotStrategy {
  @override
  BotDifficulty get difficulty => const BotDifficulty(
    name: 'Hard',
    forgetChancePerTurn: 0.02,
    confusionOnSwap: 0.03,
    reactionSpeed: 0.95,
    matchAccuracy: 0.98,
    reactionMatchChance: 0.90,
  );

  @override
  bool shouldCallDutch(Player bot, GameState gameState) {
    final phase = BotConfig.getBotPhase(bot, gameState);
    return BotDutchStrategy.shouldCallDutch(gameState, bot, difficulty, phase);
  }

  @override
  BotAction makeDecision(Player bot, GameState gameState) {
    // Logique avancée pour bot difficile
    return BotAction('draw', {});
  }

  @override
  bool shouldKeepCard(Player bot, int cardValue, GameState gameState) {
    final knownValues = <int>[];
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null) {
        knownValues.add(card.points);
      }
    }
    if (knownValues.isEmpty) return true;
    final maxKnown = knownValues.reduce(max);
    return cardValue < maxKnown;
  }
}

/// Factory pour créer les stratégies de bots
/// Principe GRASP: Creator - Responsable de la création des stratégies
class BotStrategyFactory {
  static BotStrategy createStrategy(String skillLevel) {
    // Vocabulaire Difficulty ('easy'/'medium') conservé tel quel (distinct du skill).
    final s = skillLevel.toLowerCase();
    if (s == 'easy') return EasyBotStrategy();
    if (s == 'medium') return MediumBotStrategy();
    // Interprétation skill centralisée via le helper (défaut silver → Medium,
    // identique à l'ancien default). 'hard'/'gold'/'platinum' → difficile → Hard.
    switch (BotSkillLevel.fromString(skillLevel)) {
      case BotSkillLevel.bronze:
        return EasyBotStrategy();
      case BotSkillLevel.silver:
        return MediumBotStrategy();
      case BotSkillLevel.difficile:
        return HardBotStrategy();
    }
  }
}
