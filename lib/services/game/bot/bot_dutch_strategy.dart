import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_config.dart';
import 'bot_difficulty.dart';
import 'bot_threat_analyzer.dart';
import 'bot_personality.dart';
import 'bot_memory_manager.dart';
import 'discard_tracker.dart';
import 'human_threat_tracker.dart';

/// Stratégie de décision pour appeler Dutch
/// Logique multi‑paramètres (sans seuils de score fixes)
class BotDutchStrategy {
  /// Tracker de défausses partagé (comptage de cartes)
  static final DiscardTracker discardTracker = DiscardTracker();

  /// Décide si le bot doit appeler Dutch
  static bool shouldCallDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    if (!_canDutchStateBased(gs, bot, difficulty)) return false;
    return _shouldDutchStateBased(gs, bot, difficulty, personality);
  }

  /// Vérifie si le bot PEUT Dutch (conditions nécessaires)
  static bool _canDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
  ) {
    // RÈGLE FONDAMENTALE : le bot doit connaître TOUTES ses cartes
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    if (unknownIndices.isNotEmpty) {
      return false;
    }

    // Vérifier que la mentalMap est cohérente
    final knownCount = bot.mentalMap.where((c) => c != null).length;
    final handSize = bot.hand.length;
    if (knownCount < handSize) {
      return false; // Pas assez de certitude
    }

    return true;
  }

  /// Décide si le bot DEVRAIT Dutch (conditions suffisantes)
  /// Logique multi‑paramètres (pas de seuil de score fixe)
  static bool _shouldDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotPersonality? personality,
  ) {
    final myCards = bot.hand.length;
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot);

    final threatTracker = HumanThreatTracker();
    final humanThreatLevel = threatTracker.calculateThreatLevel(gs);

    // Ne Dutch pas si j'ai trop de cartes
    if (myCards >= 4) return false;

    // Si je viens de rater un match ou de prendre une pénalité, ne Dutch pas
    if (_recentMatchFail(gs, bot) || _recentPenalty(gs, bot)) {
      return false;
    }

    // Si un adversaire a 1 carte et moi > 1, prudence
    if (report.hasOpponentWithOneCard && myCards > 1) {
      return false;
    }

    final mostThreat = report.mostThreatening?.player ?? report.leader;
    final mostThreatId = mostThreat?.id;
    final mainExchanged = mostThreatId != null && discardTracker.lastActionWasExchange(mostThreatId);
    final mainEstimate = (mostThreatId != null && mostThreat != null)
        ? discardTracker.estimateOpponentHand(mostThreatId, mostThreat.hand.length)
        : null;
    final mainDiscardedGoodCard = mainEstimate != null &&
        mainEstimate.confidence >= 0.4 &&
        !discardTracker.lastActionWasExchange(mostThreatId!) &&
        mainEstimate.avgDiscardedPoints <= 4;

    // Si l'adversaire principal a jeté une bonne carte sans échange, ne Dutch pas
    if (mainDiscardedGoodCard) {
      return false;
    }

    final anyOpponentPenalty = report.opponents.any((o) => _recentPenalty(gs, o.player));
    final maxOpponentCards = report.opponents.isEmpty
        ? myCards
        : report.opponents.map((o) => o.cardsLeft).reduce(max);
    final avgOpponentCards = report.avgOpponentCards;

    // Anti‑humain critique : bloquer si l'humain est sur le point de gagner
    if (humanThreatLevel == HumanThreatLevel.critical && myCards <= 3) {
      gs.addToHistory('🎯 ${bot.name} Dutch préemptif (humain critique)');
      return true;
    }

    // 1 carte : Dutch immédiat
    if (myCards == 1) {
      return true;
    }

    // 2 cartes : Dutch si pression ou avantage clair
    if (myCards == 2) {
      if (maxOpponentCards >= 5) return true;
      if (avgOpponentCards >= myCards + 2) return true;
      if (mainExchanged) return true;
      if (anyOpponentPenalty) return true;
      return false;
    }

    // 3 cartes : Dutch seulement si gros écart ou pression (pénalité/échange)
    if (myCards == 3) {
      if (maxOpponentCards >= 5 && (mainExchanged || anyOpponentPenalty)) return true;
      if (avgOpponentCards >= 5 && anyOpponentPenalty) return true;
      if (mainExchanged && humanThreatLevel.index >= HumanThreatLevel.high.index) return true;
      return false;
    }

    return false;
  }

  static bool _recentMatchFail(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['rate son match']);
  }

  static bool _recentPenalty(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['pénalité', 'penalite']);
  }

  static bool _recentActionContains(GameState gs, String playerName, List<String> keywords,
      {int limit = 12}) {
    final name = playerName.toLowerCase();
    int count = 0;
    for (final entry in gs.actionHistory) {
      if (count >= limit) break;
      count++;
      final lower = entry.toLowerCase();
      if (!lower.contains(name)) continue;
      for (final keyword in keywords) {
        if (lower.contains(keyword)) return true;
      }
    }
    return false;
  }
}
