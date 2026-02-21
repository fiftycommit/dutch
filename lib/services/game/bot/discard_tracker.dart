import 'dart:math';
import '../../../models/playing_card.dart';
import '../../../models/player.dart';
import '../../../models/game_state.dart';

enum DiscardActionType {
  drawnDiscard,
  exchangeDiscard,
  matchDiscard,
}

/// Système de comptage de cartes pour les bots intelligents
///
/// Un joueur expert observe :
/// - Les cartes défaussées (visibles par tous)
/// - Ce que les adversaires défaussent (indice sur leur main)
/// - Les probabilités restantes
///
/// Avec 52 cartes + 2 jokers = 54 cartes au total
/// 4 exemplaires de chaque valeur (sauf Joker = 2)
class DiscardTracker {
  /// Cartes vues dans la défausse (par valeur de points)
  /// Ex: {0: 3} = 3 cartes à 0 points vues (As, Roi rouge, Joker)
  final Map<int, int> _seenByPoints = {};

  /// Cartes vues par valeur exacte (pour probabilités fines)
  /// Ex: {'A': 2, 'R': 3, '7': 1}
  final Map<String, int> _seenByValue = {};

  /// Historique des défausses par joueur (playerId -> liste de points défaussés)
  /// Permet d'estimer la qualité de leur main
  final Map<String, List<int>> _playerDiscardHistory = {};

  /// Actions observées par joueur.
  /// - exchangeDiscard: a gardé la pioche en échangeant une carte de main
  /// - drawnDiscard: a défaussé directement la carte piochée
  /// - matchDiscard: a posé une carte via match en réaction
  final Map<String, int> _playerExchangeDiscardCount = {};
  final Map<String, int> _playerDrawnDiscardCount = {};
  final Map<String, int> _playerMatchDiscardCount = {};
  final Map<String, List<int>> _playerExchangeDiscardPoints = {};
  final Map<String, List<int>> _playerDrawnDiscardPoints = {};
  final Map<String, List<int>> _playerMatchTurns = {};
  final Map<String, List<_HandSnapshot>> _playerHandSnapshots = {};

  /// Signaux publics duel:
  /// - indices remplacés observés (sans valeur de la carte gardée),
  /// - plafond estimé par index après remplacement (oldDiscard + marge),
  /// - indices vus au départ (mémorisation publique),
  /// - volume d'utilisation des pouvoirs.
  final Map<String, List<int>> _playerReplacedIndexHistory = {};
  final Map<String, Map<int, int>> _playerReplacedIndexCounts = {};
  final Map<String, Map<int, double>> _playerIndexUpperBounds = {};
  final Map<String, Map<int, int>> _playerVisibleSwapByIndexCount = {};
  final Map<String, int> _playerVisibleSwapCount = {};
  final Map<String, Set<int>> _playerPublicStartKnownIndices = {};
  final Map<String, int> _playerPowerUseCount = {};
  final Map<String, List<int>> _playerPowerUseTurns = {};
  final Map<String, int> _playerRoundStartScore = {};

  /// Nombre de défausses observées pour un joueur
  int getDiscardCount(String playerId) =>
      _playerDiscardHistory[playerId]?.length ?? 0;

  /// Cartes totales dans le jeu par points
  /// 0 pts: 6 (4 As + 2 Jokers) si rouge, sinon 4 As
  /// 1-10: 4 chacun
  /// 11 (Valet): 4
  /// 12 (Dame): 4
  /// 13 (Roi noir): 2
  /// 0 (Roi rouge): 2
  static const Map<int, int> totalCardsByPoints = {
    0: 6, // 4 As (1pt mais on les compte à 0 ici) + 2 Jokers...
    // En fait: As=1pt, Roi rouge=0, Joker=0
    1: 4, // 4 As
    2: 4,
    3: 4,
    4: 4,
    5: 4,
    6: 4,
    7: 4,
    8: 4,
    9: 4,
    10: 4,
    11: 4, // Valets
    12: 4, // Dames
    13: 2, // Rois noirs uniquement (rouges = 0)
  };

  /// Cartes totales par valeur faciale.
  /// Utile pour exploiter _seenByValue (et non seulement les points).
  static const Map<String, int> totalCardsByValue = {
    'A': 4,
    '2': 4,
    '3': 4,
    '4': 4,
    '5': 4,
    '6': 4,
    '7': 4,
    '8': 4,
    '9': 4,
    '10': 4,
    'V': 4,
    'D': 4,
    'R': 4,
    'JOKER': 2,
  };

  /// Nombre total de cartes basses (≤4 pts) dans le jeu
  static const int totalLowCards = 4 + 4 + 4 + 4 + 4; // As(1) + 2 + 3 + 4 = 20

  /// Nombre total de cartes hautes (≥10 pts) dans le jeu
  static const int totalHighCards = 4 + 4 + 4 + 2; // 10 + V + D + R noir = 14

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACKING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Type d'action effectuée
  /// wasExchange = true → le joueur a gardé la carte piochée (échange)
  /// wasExchange = false → le joueur a défaussé la carte piochée directement
  final Map<String, bool> _lastActionWasExchange = {};

  /// Enregistre une carte vue dans la défausse
  /// [wasExchange] : true si le joueur a échangé (gardé la pioche), false si défausse directe
  void trackDiscard(
    PlayingCard card, {
    String? discardedBy,
    bool wasExchange = false,
    DiscardActionType? actionType,
    int? turnCount,
    int? replacedIndex,
  }) {
    final points = card.points;
    final value = card.value;

    _seenByPoints[points] = (_seenByPoints[points] ?? 0) + 1;
    _seenByValue[value] = (_seenByValue[value] ?? 0) + 1;

    if (discardedBy != null) {
      _playerDiscardHistory.putIfAbsent(discardedBy, () => []);
      _playerDiscardHistory[discardedBy]!.add(points);

      final resolvedType = actionType ??
          (wasExchange
              ? DiscardActionType.exchangeDiscard
              : DiscardActionType.drawnDiscard);
      switch (resolvedType) {
        case DiscardActionType.exchangeDiscard:
          _playerExchangeDiscardCount[discardedBy] =
              (_playerExchangeDiscardCount[discardedBy] ?? 0) + 1;
          final exchanged =
              _playerExchangeDiscardPoints.putIfAbsent(discardedBy, () => []);
          exchanged.add(points);
          if (exchanged.length > 24) {
            exchanged.removeRange(0, exchanged.length - 24);
          }
          _lastActionWasExchange[discardedBy] = true;
          if (replacedIndex != null) {
            _recordReplacementIndexObservation(
              discardedBy,
              replacedIndex: replacedIndex,
              discardedPoints: points,
            );
          }
          break;
        case DiscardActionType.drawnDiscard:
          _playerDrawnDiscardCount[discardedBy] =
              (_playerDrawnDiscardCount[discardedBy] ?? 0) + 1;
          final drawn =
              _playerDrawnDiscardPoints.putIfAbsent(discardedBy, () => []);
          drawn.add(points);
          if (drawn.length > 24) {
            drawn.removeRange(0, drawn.length - 24);
          }
          _lastActionWasExchange[discardedBy] = false;
          break;
        case DiscardActionType.matchDiscard:
          _playerMatchDiscardCount[discardedBy] =
              (_playerMatchDiscardCount[discardedBy] ?? 0) + 1;
          _lastActionWasExchange[discardedBy] = false;
          if (turnCount != null) {
            final turns = _playerMatchTurns.putIfAbsent(discardedBy, () => []);
            turns.add(turnCount);
            if (turns.length > 32) {
              turns.removeRange(0, turns.length - 32);
            }
          }
          break;
      }
    }
  }

  /// Enregistre qu'un joueur a utilisé un pouvoir (look/spy/valet/joker).
  void recordPowerUse(
    String playerId, {
    int? turnCount,
  }) {
    _playerPowerUseCount[playerId] = (_playerPowerUseCount[playerId] ?? 0) + 1;
    if (turnCount != null) {
      final turns = _playerPowerUseTurns.putIfAbsent(playerId, () => <int>[]);
      turns.add(turnCount);
      if (turns.length > 32) {
        turns.removeRange(0, turns.length - 32);
      }
    }
  }

  int getPowerUseCount(String playerId) => _playerPowerUseCount[playerId] ?? 0;

  void recordRoundStartScore(String playerId, int score) {
    _playerRoundStartScore[playerId] = score;
  }

  int getRoundStartScore(String playerId, {int fallback = 0}) {
    return _playerRoundStartScore[playerId] ?? fallback;
  }

  int getRecentPowerUseCountInTurns(
    String playerId,
    int currentTurn, {
    int windowTurns = 4,
  }) {
    final turns = _playerPowerUseTurns[playerId];
    if (turns == null || turns.isEmpty) return 0;
    final floorTurn = currentTurn - windowTurns;
    int count = 0;
    for (final turn in turns) {
      if (turn >= floorTurn) count++;
    }
    return count;
  }

  /// Mémorisation publique observée (indices vus au départ).
  /// Les valeurs restent cachées.
  void observePublicMemorizedIndices(
    String playerId,
    Iterable<int> indices,
    int handSize,
  ) {
    if (handSize <= 0) return;
    final valid = indices.where((idx) => idx >= 0 && idx < handSize).toSet();
    if (valid.isEmpty) return;
    final observed =
        _playerPublicStartKnownIndices.putIfAbsent(playerId, () => <int>{});
    observed.addAll(valid);
  }

  int getObservedStartKnownCount(String playerId, int handSize) {
    if (handSize <= 0) return 0;
    final observed = _playerPublicStartKnownIndices[playerId];
    if (observed == null || observed.isEmpty) return 0;
    return observed.where((idx) => idx >= 0 && idx < handSize).length;
  }

  double getObservedStartKnownRatio(String playerId, int handSize) {
    if (handSize <= 0) return 0.0;
    final count = getObservedStartKnownCount(playerId, handSize);
    return (count / handSize).clamp(0.0, 1.0);
  }

  Map<int, int> getObservedReplacementIndexCounts(
      String playerId, int handSize) {
    if (handSize <= 0) return const <int, int>{};
    final source = _playerReplacedIndexCounts[playerId];
    if (source == null || source.isEmpty) return const <int, int>{};

    final filtered = <int, int>{};
    for (final entry in source.entries) {
      if (entry.key < 0 || entry.key >= handSize) continue;
      filtered[entry.key] = entry.value;
    }
    return filtered;
  }

  Map<int, double> getObservedIndexUpperBounds(String playerId, int handSize) {
    if (handSize <= 0) return const <int, double>{};
    final source = _playerIndexUpperBounds[playerId];
    if (source == null || source.isEmpty) return const <int, double>{};

    final filtered = <int, double>{};
    for (final entry in source.entries) {
      if (entry.key < 0 || entry.key >= handSize) continue;
      filtered[entry.key] = entry.value;
    }
    return filtered;
  }

  /// Retourne l'index adverse le plus susceptible de contenir une carte basse:
  /// - souvent remplacé,
  /// - plafond estimé bas.
  int? pickLikelyStrongIndex(String playerId, int handSize) {
    if (handSize <= 0) return null;
    final counts = getObservedReplacementIndexCounts(playerId, handSize);
    final bounds = getObservedIndexUpperBounds(playerId, handSize);
    if (counts.isEmpty && bounds.isEmpty) return null;
    final swapNoise = _playerVisibleSwapByIndexCount[playerId];

    int? bestIdx;
    double bestScore = -9999;
    for (int idx = 0; idx < handSize; idx++) {
      final count = counts[idx] ?? 0;
      final bound = bounds[idx] ?? 9.5;
      final noisePenalty = min((swapNoise?[idx] ?? 0), 4) * 1.10;
      final score = (count * 1.20) + ((13.0 - bound) * 0.80) - noisePenalty;
      if (score > bestScore) {
        bestScore = score;
        bestIdx = idx;
      }
    }

    if (bestIdx == null) return null;
    return bestScore >= 1.0 ? bestIdx : null;
  }

  /// Retourne true si la dernière action du joueur était un échange
  bool lastActionWasExchange(String playerId) =>
      _lastActionWasExchange[playerId] ?? false;

  /// Enregistre plusieurs cartes (ex: après un match)
  void trackMultipleDiscards(
    List<PlayingCard> cards, {
    String? discardedBy,
    DiscardActionType actionType = DiscardActionType.matchDiscard,
  }) {
    for (final card in cards) {
      trackDiscard(
        card,
        discardedBy: discardedBy,
        actionType: actionType,
      );
    }
  }

  /// Reset pour une nouvelle manche
  void reset() {
    _seenByPoints.clear();
    _seenByValue.clear();
    _playerDiscardHistory.clear();
    _lastActionWasExchange.clear();
    _playerExchangeDiscardCount.clear();
    _playerDrawnDiscardCount.clear();
    _playerMatchDiscardCount.clear();
    _playerExchangeDiscardPoints.clear();
    _playerDrawnDiscardPoints.clear();
    _playerMatchTurns.clear();
    _playerHandSnapshots.clear();
    _playerReplacedIndexHistory.clear();
    _playerReplacedIndexCounts.clear();
    _playerIndexUpperBounds.clear();
    _playerVisibleSwapByIndexCount.clear();
    _playerVisibleSwapCount.clear();
    _playerPublicStartKnownIndices.clear();
    _playerPowerUseCount.clear();
    _playerPowerUseTurns.clear();
    _playerRoundStartScore.clear();
  }

  /// Snapshot de la table à un tour donné (rotation de table).
  /// Permet de mesurer la vélocité de réduction des mains: n(t-k) - n(t).
  void recordTableSnapshot(GameState gs) {
    final turn = gs.turnCount;
    for (final player in gs.players) {
      observePublicMemorizedIndices(
        player.id,
        player.memorizedCardIndices,
        player.hand.length,
      );
      final snapshots =
          _playerHandSnapshots.putIfAbsent(player.id, () => <_HandSnapshot>[]);
      if (snapshots.isNotEmpty && snapshots.last.turn == turn) {
        snapshots[snapshots.length - 1] =
            _HandSnapshot(turn: turn, cards: player.hand.length);
      } else {
        snapshots.add(_HandSnapshot(turn: turn, cards: player.hand.length));
      }
      if (snapshots.length > 12) {
        snapshots.removeRange(0, snapshots.length - 12);
      }
    }
  }

  /// Retourne la vélocité de cartes d'un joueur sur [windowTurns] :
  /// n(t-windowTurns) - n(t). Positif = réduction rapide.
  int getCardVelocity(
    String playerId,
    int currentTurn, {
    int currentCards = -1,
    int windowTurns = 2,
  }) {
    final snapshots = _playerHandSnapshots[playerId];
    if (snapshots == null || snapshots.isEmpty) return 0;

    final nowCards = currentCards >= 0 ? currentCards : snapshots.last.cards;
    final targetTurn = currentTurn - windowTurns;

    _HandSnapshot? anchor;
    for (int i = snapshots.length - 1; i >= 0; i--) {
      final snap = snapshots[i];
      if (snap.turn <= targetTurn) {
        anchor = snap;
        break;
      }
    }
    anchor ??= snapshots.first;

    final velocity = anchor.cards - nowCards;
    return velocity < 0 ? 0 : velocity;
  }

  /// Nombre de matchs observés sur les [windowTurns] derniers tours.
  int getRecentMatchCountInTurns(
    String playerId,
    int currentTurn, {
    int windowTurns = 3,
  }) {
    final turns = _playerMatchTurns[playerId];
    if (turns == null || turns.isEmpty) return 0;
    final floorTurn = currentTurn - windowTurns;
    int count = 0;
    for (final t in turns) {
      if (t >= floorTurn) count++;
    }
    return count;
  }

  /// Retourne vrai si au moins [requiredMatches] matchs ont été faits
  /// en [withinTurns] tours (détection de burst latent).
  bool hasMatchBurst(
    String playerId,
    int currentTurn, {
    int requiredMatches = 2,
    int withinTurns = 3,
  }) {
    if (requiredMatches <= 1) return true;
    final turns = _playerMatchTurns[playerId];
    if (turns == null || turns.length < requiredMatches) return false;

    int left = 0;
    for (int right = 0; right < turns.length; right++) {
      while (turns[right] - turns[left] > withinTurns && left < right) {
        left++;
      }
      if ((right - left + 1) >= requiredMatches &&
          turns[right] >= (currentTurn - withinTurns - 1)) {
        return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROBABILITÉS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Nombre de cartes d'une valeur de points déjà vues
  int seenCount(int points) => _seenByPoints[points] ?? 0;

  /// Nombre de cartes d'une valeur de points restantes (non vues)
  int remainingCount(int points) {
    final total = totalCardsByPoints[points] ?? 4;
    return max(0, total - seenCount(points));
  }

  /// Probabilité qu'une carte de X points soit encore en jeu
  /// Retourne 0.0 à 1.0
  double probabilityRemaining(int points) {
    final total = totalCardsByPoints[points] ?? 4;
    final remaining = remainingCount(points);
    return remaining / total;
  }

  /// Nombre de cartes d'une valeur faciale déjà vues.
  int seenCountByValue(String value) => _seenByValue[value] ?? 0;

  /// Nombre de cartes d'une valeur faciale restantes.
  int remainingCountByValue(String value) {
    final total = totalCardsByValue[value] ?? 4;
    return max(0, total - seenCountByValue(value));
  }

  /// Proba qu'une valeur faciale soit encore disponible.
  double probabilityValueRemaining(String value) {
    final total = totalCardsByValue[value] ?? 4;
    if (total <= 0) return 0.0;
    return (remainingCountByValue(value) / total).clamp(0.0, 1.0);
  }

  /// Nombre estimé de cartes encore inconnues en jeu.
  int get remainingUnknownCardsByValue {
    int remaining = 0;
    for (final entry in totalCardsByValue.entries) {
      remaining += remainingCountByValue(entry.key);
    }
    return max(remaining, 1);
  }

  /// Proba de piocher une carte de points <= [maxPoints].
  double probabilityDrawAtOrBelow(int maxPoints) {
    int favorable = 0;
    int total = 0;
    for (final entry in totalCardsByPoints.entries) {
      final points = entry.key;
      final rem = remainingCount(points);
      if (rem <= 0) continue;
      total += rem;
      if (points <= maxPoints) favorable += rem;
    }
    if (total <= 0) return 0.0;
    return (favorable / total).clamp(0.0, 1.0);
  }

  /// Espérance de points d'une carte future.
  double expectedDrawnPoints() {
    int total = 0;
    double weighted = 0;
    for (final entry in totalCardsByPoints.entries) {
      final points = entry.key;
      final rem = remainingCount(points);
      if (rem <= 0) continue;
      total += rem;
      weighted += points * rem;
    }
    if (total <= 0) return 6.5;
    return weighted / total;
  }

  /// Proba approximative de recroiser [value] dans les cartes inconnues.
  /// [knownOwned] = nombre de cartes déjà connues de cette valeur chez soi.
  double estimateFutureMatchProbability(
    String value, {
    int knownOwned = 0,
  }) {
    final remainingByValue = remainingCountByValue(value);
    final available = max(0, remainingByValue - knownOwned);
    if (available <= 0) return 0.0;
    final pool = remainingUnknownCardsByValue;
    if (pool <= 0) return 0.0;
    return (available / pool).clamp(0.0, 1.0);
  }

  /// Nombre total de cartes basses (≤4) restantes
  int get remainingLowCards {
    int count = 0;
    for (int pts = 1; pts <= 4; pts++) {
      count += remainingCount(pts);
    }
    // Ajouter Jokers (0 pts) et Rois rouges (0 pts)
    count += remainingCount(0);
    return count;
  }

  /// Nombre total de cartes hautes (≥10) restantes
  int get remainingHighCards {
    int count = 0;
    for (int pts = 10; pts <= 13; pts++) {
      count += remainingCount(pts);
    }
    return count;
  }

  /// Ratio de cartes basses vs hautes restantes
  /// > 1.0 = plus de bonnes cartes disponibles
  /// < 1.0 = plus de mauvaises cartes disponibles
  double get lowToHighRatio {
    final high = remainingHighCards;
    if (high == 0) return 10.0; // Toutes les hautes sont sorties !
    return remainingLowCards / high;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSE DES ADVERSAIRES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyse la qualité probable de la main d'un adversaire
  /// basée sur ce qu'il a défaussé
  ///
  /// Logique : Si un joueur défausse beaucoup de cartes hautes,
  /// il garde probablement des cartes basses → bonne main !
  OpponentHandEstimate estimateOpponentHand(String playerId, int cardCount) {
    final history = _playerDiscardHistory[playerId] ?? [];

    if (history.isEmpty) {
      // Pas d'info → estimation neutre
      return OpponentHandEstimate(
        playerId: playerId,
        estimatedScore: cardCount * 6.5, // Moyenne théorique
        confidence: 0.0,
        likelyLowHand: false,
        avgDiscardedPoints: 0,
      );
    }

    // Moyenne pondérée avec biais récence (les dernières actions comptent plus).
    double weightedSum = 0;
    double totalWeight = 0;
    for (int i = 0; i < history.length; i++) {
      final recency = (i + 1) / history.length; // 0..1
      final weight = 0.55 + (recency * 0.90); // 0.55..1.45
      weightedSum += history[i] * weight;
      totalWeight += weight;
    }
    final avgDiscarded = totalWeight > 0
        ? weightedSum / totalWeight
        : history.reduce((a, b) => a + b) / history.length;

    // Si il défausse des cartes hautes (>8), il garde probablement des basses
    final likelyLowHand = avgDiscarded >= 8;

    // Estimation du score basée sur les défausses:
    // plus il défausse haut, plus son score estimé est bas.
    double estimatedAvgCard;
    if (avgDiscarded >= 10) {
      estimatedAvgCard = 3.0; // Il garde des très bonnes cartes
    } else if (avgDiscarded >= 7) {
      estimatedAvgCard = 5.0; // Il garde des cartes moyennes-bonnes
    } else if (avgDiscarded >= 4) {
      estimatedAvgCard = 7.0; // Il garde des cartes moyennes
    } else {
      estimatedAvgCard = 9.0; // Il défausse des basses → garde des hautes !
    }

    final decisions = getObservedDecisionCount(playerId);
    final exchangeRate = getExchangeRate(playerId);
    final lastExchange = lastActionWasExchange(playerId);

    // Ajustements comportementaux:
    // - garde souvent la pioche => tendance à améliorer sa main (score estimé plus bas)
    // - vient de défausser la pioche => légère dégradation de l'estimation
    estimatedAvgCard -= exchangeRate * 1.4;
    if (lastExchange) {
      estimatedAvgCard -= 0.6;
    } else {
      estimatedAvgCard += 0.3;
    }
    if (cardCount <= 2) {
      estimatedAvgCard -= 0.4;
    }
    estimatedAvgCard = estimatedAvgCard.clamp(1.0, 10.0);

    // Confiance: couverture + stabilité des signaux (et jamais 100% ici).
    double variance = 0;
    for (final value in history) {
      final delta = value - avgDiscarded;
      variance += delta * delta;
    }
    variance = history.isEmpty ? 0 : variance / history.length;
    final volatility = (sqrt(variance) / 6.0).clamp(0.0, 1.0);
    final coverage = ((history.length * 0.55) + (decisions * 0.45)) / 14.0;
    final confidence =
        (0.08 + (coverage * 0.78) - (volatility * 0.22)).clamp(0.05, 0.90);

    return OpponentHandEstimate(
      playerId: playerId,
      estimatedScore: cardCount * estimatedAvgCard,
      confidence: confidence,
      likelyLowHand: likelyLowHand,
      avgDiscardedPoints: avgDiscarded,
    );
  }

  int getExchangeDiscardCount(String playerId) =>
      _playerExchangeDiscardCount[playerId] ?? 0;

  int getDrawnDiscardCount(String playerId) =>
      _playerDrawnDiscardCount[playerId] ?? 0;

  int getMatchDiscardCount(String playerId) =>
      _playerMatchDiscardCount[playerId] ?? 0;

  int getObservedDecisionCount(String playerId) =>
      getExchangeDiscardCount(playerId) + getDrawnDiscardCount(playerId);

  double getExchangeRate(String playerId) {
    final decisions = getObservedDecisionCount(playerId);
    if (decisions == 0) return 0.5;
    return getExchangeDiscardCount(playerId) / decisions;
  }

  double getAverageDiscardedPoints(String playerId) {
    final history = _playerDiscardHistory[playerId] ?? const <int>[];
    if (history.isEmpty) return 6.5;
    final total = history.reduce((a, b) => a + b);
    return total / history.length;
  }

  /// Moyenne des cartes défaussées instantanément (drawnDiscard).
  /// Un joueur qui jette souvent des petites cartes instant suggère
  /// qu'un payload faible peut déjà le perturber.
  double getAverageDrawnDiscardPoints(String playerId, {int lookback = 0}) {
    final values = _playerDrawnDiscardPoints[playerId] ?? const <int>[];
    return _averagePoints(values, lookback: lookback);
  }

  /// Moyenne des cartes remplacées (exchangeDiscard).
  /// Utile pour voir si un joueur "nettoie" souvent des cartes hautes.
  double getAverageExchangeDiscardPoints(String playerId, {int lookback = 0}) {
    final values = _playerExchangeDiscardPoints[playerId] ?? const <int>[];
    return _averagePoints(values, lookback: lookback);
  }

  /// Taux de défausses instantanées basses (<= maxPoints).
  double getLowDrawnDiscardRate(
    String playerId, {
    int maxPoints = 4,
    int lookback = 0,
  }) {
    final values = _playerDrawnDiscardPoints[playerId] ?? const <int>[];
    if (values.isEmpty) return 0.0;
    final sample = _tail(values, lookback);
    if (sample.isEmpty) return 0.0;
    final lows = sample.where((v) => v <= maxPoints).length;
    return (lows / sample.length).clamp(0.0, 1.0);
  }

  /// Vrai si le joueur a récemment défaussé instantanément une petite carte.
  bool hasRecentLowDrawnDiscard(
    String playerId, {
    int maxPoints = 4,
    int lookback = 4,
  }) {
    final values = _playerDrawnDiscardPoints[playerId] ?? const <int>[];
    if (values.isEmpty) return false;
    final sample = _tail(values, lookback);
    return sample.any((v) => v <= maxPoints);
  }

  OpponentStyleEstimate estimateOpponentStyle(String playerId) {
    final decisions = getObservedDecisionCount(playerId);
    final exchangeRate = getExchangeRate(playerId);
    final avgDiscarded = getAverageDiscardedPoints(playerId);
    final matchCount = getMatchDiscardCount(playerId);
    final powerUses = getPowerUseCount(playerId);

    // Confiance rapide mais bornée: le Platine doit s'adapter tôt.
    final confidence =
        ((decisions / 4.0) + (powerUses / 12.0)).clamp(0.15, 1.0);
    final highDiscardSignal = ((avgDiscarded - 5.5) / 6.0).clamp(0.0, 1.0);
    final matchSignal = (matchCount / 3.0).clamp(0.0, 1.0);
    final powerSignal = (powerUses / 5.0).clamp(0.0, 1.0);

    // 0..1 : capacité probable à optimiser sa main.
    final optimization = (highDiscardSignal * 0.50 +
            exchangeRate * 0.28 +
            matchSignal * 0.12 +
            powerSignal * 0.10)
        .clamp(0.0, 1.0);

    // 0..1 : profil opportuniste/agressif (beaucoup d'échanges).
    final aggression =
        (exchangeRate * 0.66 + matchSignal * 0.22 + powerSignal * 0.12)
            .clamp(0.0, 1.0);

    // 0..1 : tendance à varier ses décisions (plus c'est haut, plus c'est dur à lire).
    final unpredictability =
        (1.0 - ((exchangeRate - 0.5).abs() * 2.0)).clamp(0.0, 1.0);

    return OpponentStyleEstimate(
      playerId: playerId,
      optimization: optimization,
      aggression: aggression,
      unpredictability: unpredictability,
      confidence: confidence,
      avgDiscardedPoints: avgDiscarded,
      observedDecisions: decisions,
    );
  }

  OpponentIndexIntel estimateOpponentIndexIntel(String playerId, int handSize) {
    if (handSize <= 0) {
      return OpponentIndexIntel(
        playerId: playerId,
        estimatedScoreCeiling: 0.0,
        estimatedCardCeiling: 0.0,
        confidence: 1.0,
        observedReplacements: 0,
        indexCoverage: 0.0,
        dominantIndexReuse: 0.0,
        startKnownRatio: 0.0,
        lowRejectRate: 0.0,
        powerUses: getPowerUseCount(playerId),
        visibleSwapRatio: 0.0,
      );
    }

    final history = _playerReplacedIndexHistory[playerId] ?? const <int>[];
    final observedReplacements = history.length;
    final counts = _playerReplacedIndexCounts[playerId] ?? const <int, int>{};
    final caps = _playerIndexUpperBounds[playerId] ?? const <int, double>{};

    int dominantIndexCount = 0;
    int uniqueValidIndices = 0;
    for (final entry in counts.entries) {
      final idx = entry.key;
      final count = entry.value;
      if (idx < 0 || idx >= handSize) continue;
      uniqueValidIndices++;
      if (count > dominantIndexCount) dominantIndexCount = count;
    }

    final indexCoverage =
        handSize <= 0 ? 0.0 : (uniqueValidIndices / handSize).clamp(0.0, 1.0);
    final dominantIndexReuse = observedReplacements <= 0
        ? 0.0
        : (dominantIndexCount / observedReplacements).clamp(0.0, 1.0);

    final capValues = <double>[];
    for (final entry in caps.entries) {
      final idx = entry.key;
      if (idx < 0 || idx >= handSize) continue;
      capValues.add(entry.value);
    }

    final baseCardCeiling = capValues.isEmpty
        ? 8.8
        : capValues.reduce((a, b) => a + b) / capValues.length;
    final startKnownRatio = getObservedStartKnownRatio(playerId, handSize);
    final lowRejectRate =
        getLowDrawnDiscardRate(playerId, maxPoints: 4, lookback: 8);
    final recentLowReject =
        hasRecentLowDrawnDiscard(playerId, maxPoints: 4, lookback: 4);
    final powerUses = getPowerUseCount(playerId);
    final observedDecisions = getObservedDecisionCount(playerId);
    final visibleSwapCount = _playerVisibleSwapCount[playerId] ?? 0;
    final visibleSwapRatio = observedReplacements <= 0
        ? 0.0
        : (visibleSwapCount / observedReplacements).clamp(0.0, 1.0);

    double cardCeiling = baseCardCeiling;
    cardCeiling -= startKnownRatio * 0.90;
    cardCeiling -= lowRejectRate * 1.40;
    cardCeiling -= indexCoverage * 0.75;
    if (recentLowReject) {
      cardCeiling -= 0.30;
    }
    if (dominantIndexReuse >= 0.60 && observedReplacements >= 3) {
      cardCeiling -= 0.25;
    }
    if (powerUses >= 3) {
      cardCeiling -= 0.35;
    } else if (powerUses >= 1) {
      cardCeiling -= 0.15;
    }
    cardCeiling += visibleSwapRatio * 2.10;
    if (visibleSwapCount >= 2) {
      cardCeiling += 0.35;
    }
    cardCeiling = cardCeiling.clamp(1.1, 10.0);

    final estimatedScoreCeiling = cardCeiling * handSize;

    double confidence = 0.10;
    confidence += (min(observedReplacements, 8) / 8.0) * 0.45;
    confidence += (min(observedDecisions, 10) / 10.0) * 0.25;
    confidence += startKnownRatio * 0.15;
    confidence += (min(powerUses, 6) / 6.0) * 0.10;
    if (capValues.isEmpty) confidence -= 0.12;
    confidence -= visibleSwapRatio * 0.22;
    confidence = confidence.clamp(0.05, 0.92);

    return OpponentIndexIntel(
      playerId: playerId,
      estimatedScoreCeiling: estimatedScoreCeiling,
      estimatedCardCeiling: cardCeiling,
      confidence: confidence,
      observedReplacements: observedReplacements,
      indexCoverage: indexCoverage,
      dominantIndexReuse: dominantIndexReuse,
      startKnownRatio: startKnownRatio,
      lowRejectRate: lowRejectRate,
      powerUses: powerUses,
      visibleSwapRatio: visibleSwapRatio,
    );
  }

  /// Enregistre un index remplacé publiquement (ex: pouvoir Valet).
  /// Contrairement à un échange avec défausse, on ne connaît pas la valeur
  /// de la carte déplacée, donc aucun plafond par points n'est appliqué.
  void observeVisibleReplacementIndex(
    String playerId, {
    required int replacedIndex,
  }) {
    _recordReplacementIndexVisibility(
      playerId,
      replacedIndex: replacedIndex,
    );

    _playerVisibleSwapCount[playerId] =
        (_playerVisibleSwapCount[playerId] ?? 0) + 1;
    final byIndex = _playerVisibleSwapByIndexCount.putIfAbsent(
        playerId, () => <int, int>{});
    byIndex[replacedIndex] = (byIndex[replacedIndex] ?? 0) + 1;

    // L'index a été modifié par un Valet: l'ancien plafond de valeur
    // observé via échanges ne s'applique plus sur cet emplacement.
    final bounds = _playerIndexUpperBounds[playerId];
    bounds?.remove(replacedIndex);
  }

  void _recordReplacementIndexObservation(
    String playerId, {
    required int replacedIndex,
    required int discardedPoints,
  }) {
    _recordReplacementIndexVisibility(
      playerId,
      replacedIndex: replacedIndex,
    );

    final bounds =
        _playerIndexUpperBounds.putIfAbsent(playerId, () => <int, double>{});
    final proposed = (discardedPoints + 1.5).clamp(1.0, 13.0).toDouble();
    final previous = bounds[replacedIndex] ?? 13.0;
    bounds[replacedIndex] = min(previous, proposed);
  }

  void _recordReplacementIndexVisibility(
    String playerId, {
    required int replacedIndex,
  }) {
    if (replacedIndex < 0) return;

    final history =
        _playerReplacedIndexHistory.putIfAbsent(playerId, () => <int>[]);
    history.add(replacedIndex);
    if (history.length > 40) {
      history.removeRange(0, history.length - 40);
    }

    final counts =
        _playerReplacedIndexCounts.putIfAbsent(playerId, () => <int, int>{});
    counts[replacedIndex] = (counts[replacedIndex] ?? 0) + 1;
  }

  List<int> _tail(List<int> values, int lookback) {
    if (values.isEmpty) return const <int>[];
    if (lookback <= 0 || values.length <= lookback) {
      return List<int>.from(values);
    }
    return List<int>.from(values.sublist(values.length - lookback));
  }

  double _averagePoints(List<int> values, {int lookback = 0}) {
    if (values.isEmpty) return 6.5;
    final sample = _tail(values, lookback);
    if (sample.isEmpty) return 6.5;
    final total = sample.reduce((a, b) => a + b);
    return total / sample.length;
  }

  /// Estime le meilleur score adverse probable (le plus bas)
  /// Pour décider si on peut Dutch en sécurité
  double estimateBestOpponentScore(GameState gs, Player bot) {
    double bestScore = 999;

    for (final player in gs.players) {
      if (player.id == bot.id) continue;

      final estimate = estimateOpponentHand(player.id, player.hand.length);

      // Pondérer par la confiance
      // Si pas de confiance, utiliser une estimation prudente (basse)
      final weightedScore = estimate.confidence > 0.3
          ? estimate.estimatedScore
          : player.hand.length * 4.0; // Estimation prudente

      if (weightedScore < bestScore) {
        bestScore = weightedScore;
      }
    }

    return bestScore;
  }

  /// Détermine si c'est un bon moment pour Dutch
  /// basé sur le comptage de cartes
  bool isGoodTimeForDutch(GameState gs, Player bot) {
    final myScore = bot.getKnownScore();
    final bestOpponentEstimate = estimateBestOpponentScore(gs, bot);

    // Marge de sécurité basée sur le ratio low/high restant
    final ratio = lowToHighRatio;
    double safetyMargin;

    if (ratio > 1.5) {
      // Beaucoup de bonnes cartes restantes → adversaires peuvent s'améliorer
      safetyMargin = 3.0;
    } else if (ratio > 1.0) {
      safetyMargin = 2.0;
    } else {
      // Plus de mauvaises cartes → moins de risque
      safetyMargin = 1.0;
    }

    return myScore + safetyMargin < bestOpponentEstimate;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEBUG
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Discard Tracker ===');
    buffer.writeln('Cartes vues par points:');
    for (final entry in _seenByPoints.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final remaining = remainingCount(entry.key);
      buffer.writeln(
          '  ${entry.key} pts: ${entry.value} vues, $remaining restantes');
    }
    buffer.writeln('Low/High ratio: ${lowToHighRatio.toStringAsFixed(2)}');
    return buffer.toString();
  }
}

/// Estimation de la main d'un adversaire
class OpponentHandEstimate {
  final String playerId;
  final double estimatedScore;
  final double confidence; // 0.0 à 1.0
  final bool likelyLowHand;
  final double avgDiscardedPoints;

  OpponentHandEstimate({
    required this.playerId,
    required this.estimatedScore,
    required this.confidence,
    required this.likelyLowHand,
    required this.avgDiscardedPoints,
  });

  @override
  String toString() =>
      'Estimate($playerId): ~${estimatedScore.toStringAsFixed(1)} pts '
      '(conf: ${(confidence * 100).toStringAsFixed(0)}%, '
      'avgDiscard: ${avgDiscardedPoints.toStringAsFixed(1)})';
}

class OpponentStyleEstimate {
  final String playerId;
  final double optimization;
  final double aggression;
  final double unpredictability;
  final double confidence;
  final double avgDiscardedPoints;
  final int observedDecisions;

  OpponentStyleEstimate({
    required this.playerId,
    required this.optimization,
    required this.aggression,
    required this.unpredictability,
    required this.confidence,
    required this.avgDiscardedPoints,
    required this.observedDecisions,
  });
}

class OpponentIndexIntel {
  final String playerId;
  final double estimatedScoreCeiling;
  final double estimatedCardCeiling;
  final double confidence;
  final int observedReplacements;
  final double indexCoverage;
  final double dominantIndexReuse;
  final double startKnownRatio;
  final double lowRejectRate;
  final int powerUses;
  final double visibleSwapRatio;

  OpponentIndexIntel({
    required this.playerId,
    required this.estimatedScoreCeiling,
    required this.estimatedCardCeiling,
    required this.confidence,
    required this.observedReplacements,
    required this.indexCoverage,
    required this.dominantIndexReuse,
    required this.startKnownRatio,
    required this.lowRejectRate,
    required this.powerUses,
    required this.visibleSwapRatio,
  });
}

class _HandSnapshot {
  final int turn;
  final int cards;

  const _HandSnapshot({
    required this.turn,
    required this.cards,
  });
}
