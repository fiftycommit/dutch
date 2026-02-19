import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import 'bot_config.dart';
import 'bot_difficulty.dart';
import 'bot_dutch_strategy.dart';
import 'bot_personality.dart';

/// Audit anti-triche des bots (mode debug/assert).
///
/// Objectif:
/// - vérifier que l'état mémoire reste plausible;
/// - vérifier que la décision Dutch ne dépend pas des cartes adverses cachées.
///
/// Note:
/// - Tous les contrôles sont encapsulés dans `assert` et n'ont donc aucun coût
///   en release/profile.
class BotFairPlayAudit {
  static const List<String> _maskSuits = [
    'hearts',
    'diamonds',
    'clubs',
    'spades'
  ];
  static const List<String> _maskValues = [
    'A',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'V',
    'D',
    'R',
    'JOKER',
  ];

  /// Vérifie des invariants de mémoire/espionnage plausibles.
  static void auditKnowledgeState(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    required String stage,
  }) {
    assert(() {
      if (bot.isHuman) return true;

      final issues = <String>[];
      if (bot.knownCards.length < bot.hand.length) {
        issues.add(
            'knownCards trop court (${bot.knownCards.length}/${bot.hand.length})');
      }
      if (bot.mentalMap.length < bot.hand.length) {
        issues.add(
            'mentalMap trop court (${bot.mentalMap.length}/${bot.hand.length})');
      }

      final strictPerfectMemory = difficulty.forgetChancePerTurn == 0.0 &&
          difficulty.confusionOnSwap == 0.0;
      if (strictPerfectMemory) {
        for (int i = 0; i < bot.hand.length; i++) {
          final known = i < bot.knownCards.length && bot.knownCards[i];
          final mental = i < bot.mentalMap.length ? bot.mentalMap[i] : null;
          if (known && mental == null) {
            issues.add('index $i marqué connu sans mentalMap');
            continue;
          }
          if (known && mental != null && mental.id != bot.hand[i].id) {
            issues.add(
                'index $i connu incohérent (mental=${mental.value}/${mental.suit} vs réel=${bot.hand[i].value}/${bot.hand[i].suit})');
          }
        }
      }

      for (final entry in bot.spyMemory.entries) {
        final opponentId = entry.key;
        final opponent =
            gs.players.where((p) => p.id == opponentId).firstOrNull;
        if (opponent == null) {
          issues.add('spyMemory orpheline: $opponentId');
          continue;
        }
        for (final idx in entry.value.keys) {
          if (idx < 0 || idx >= opponent.hand.length) {
            issues.add(
                'spyMemory index invalide: cible=${opponent.name} idx=$idx hand=${opponent.hand.length}');
          }
        }
      }

      if (issues.isNotEmpty) {
        throw StateError(
          'BOT FAIR-PLAY AUDIT [$stage] ${bot.name}: ${issues.join(' | ')}',
        );
      }
      return true;
    }());
  }

  /// Vérifie que la décision Dutch ne dépend pas des cartes adverses cachées.
  ///
  /// Technique:
  /// - clone l'état;
  /// - masque les cartes adverses inconnues du bot avec des cartes sentinelles;
  /// - recalcule la décision Dutch;
  /// - compare au résultat réel.
  static void auditDutchDecisionBlindness(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    bool actualDecision, {
    BotPersonality? personality,
  }) {
    assert(() {
      if (bot.isHuman) return true;

      final cloned = _cloneGameState(gs);
      final clonedBot = cloned.players.firstWhere((p) => p.id == bot.id);
      _maskHiddenOpponentCards(cloned, clonedBot);

      final maskedDecision = BotDutchStrategy.shouldCallDutch(
        cloned,
        clonedBot,
        difficulty,
        phase,
        personality: personality,
      );

      if (maskedDecision != actualDecision) {
        throw StateError(
          'BOT FAIR-PLAY AUDIT [dutch_hidden_info] ${bot.name}: décision dépendante d\'infos cachées '
          '(réel=$actualDecision, masqué=$maskedDecision)',
        );
      }
      return true;
    }());
  }

  static GameState _cloneGameState(GameState gs) {
    final players = gs.players.map(_clonePlayer).toList(growable: false);
    return GameState(
      players: players,
      deck: List<PlayingCard>.from(gs.deck),
      discardPile: List<PlayingCard>.from(gs.discardPile),
      currentPlayerIndex: gs.currentPlayerIndex,
      gameMode: gs.gameMode,
      phase: gs.phase,
      difficulty: gs.difficulty,
      tournamentRound: gs.tournamentRound,
      eliminatedPlayerIds: List<String>.from(gs.eliminatedPlayerIds),
      drawnCard: gs.drawnCard,
      isWaitingForSpecialPower: gs.isWaitingForSpecialPower,
      specialCardToActivate: gs.specialCardToActivate,
      dutchCallerId: gs.dutchCallerId,
      reactionStartTime: gs.reactionStartTime,
      actionHistory: List<String>.from(gs.actionHistory),
      reactionTimeRemaining: gs.reactionTimeRemaining,
      lastSpiedCard: gs.lastSpiedCard,
      pendingSwap: gs.pendingSwap == null
          ? null
          : Map<String, dynamic>.from(gs.pendingSwap!),
      tournamentCumulativeScores:
          Map<String, int>.from(gs.tournamentCumulativeScores),
      turnStartTime: gs.turnStartTime,
      turnTimeoutMs: gs.turnTimeoutMs,
      readyPlayerIds: List<String>.from(gs.readyPlayerIds),
      turnCount: gs.turnCount,
      actionCount: gs.actionCount,
    );
  }

  static Player _clonePlayer(Player p) {
    final copy = p.copyWith();
    copy.spyMemory = {
      for (final e in p.spyMemory.entries)
        e.key: Map<int, PlayingCard>.from(e.value),
    };
    return copy;
  }

  static void _maskHiddenOpponentCards(GameState gs, Player observer) {
    for (final opponent in gs.players) {
      if (opponent.id == observer.id || opponent.hand.isEmpty) continue;

      final spied = observer.getSpiedCards(opponent.id);
      final visibleIndices = <int>{};
      if (spied != null && spied.isNotEmpty) {
        for (final idx in spied.keys) {
          if (idx >= 0 && idx < opponent.hand.length) {
            visibleIndices.add(idx);
          }
        }
      }

      for (int i = 0; i < opponent.hand.length; i++) {
        if (visibleIndices.contains(i)) continue;
        opponent.hand[i] = _maskedCardFor(opponent.id, i);
      }
    }
  }

  static PlayingCard _maskedCardFor(String playerId, int index) {
    final seed = (playerId.hashCode ^ (index * 1103515245)).abs();
    final suit = _maskSuits[seed % _maskSuits.length];
    final value = _maskValues[(seed ~/ _maskSuits.length) % _maskValues.length];
    return PlayingCard.create(suit, value);
  }
}
