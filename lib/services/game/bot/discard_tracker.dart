import 'dart:math';
import '../../../models/playing_card.dart';
import '../../../models/player.dart';
import '../../../models/game_state.dart';

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
  
  /// Nombre de défausses observées pour un joueur
  int getDiscardCount(String playerId) => _playerDiscardHistory[playerId]?.length ?? 0;
  
  /// Cartes totales dans le jeu par points
  /// 0 pts: 6 (4 As + 2 Jokers) si rouge, sinon 4 As
  /// 1-10: 4 chacun
  /// 11 (Valet): 4
  /// 12 (Dame): 4
  /// 13 (Roi noir): 2
  /// 0 (Roi rouge): 2
  static const Map<int, int> totalCardsByPoints = {
    0: 6,   // 4 As (1pt mais on les compte à 0 ici) + 2 Jokers... 
            // En fait: As=1pt, Roi rouge=0, Joker=0
    1: 4,   // 4 As
    2: 4,
    3: 4,
    4: 4,
    5: 4,
    6: 4,
    7: 4,
    8: 4,
    9: 4,
    10: 4,
    11: 4,  // Valets
    12: 4,  // Dames
    13: 2,  // Rois noirs uniquement (rouges = 0)
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
  void trackDiscard(PlayingCard card, {String? discardedBy, bool wasExchange = false}) {
    final points = card.points;
    final value = card.value;
    
    _seenByPoints[points] = (_seenByPoints[points] ?? 0) + 1;
    _seenByValue[value] = (_seenByValue[value] ?? 0) + 1;
    
    if (discardedBy != null) {
      _playerDiscardHistory.putIfAbsent(discardedBy, () => []);
      _playerDiscardHistory[discardedBy]!.add(points);
      _lastActionWasExchange[discardedBy] = wasExchange;
    }
  }
  
  /// Retourne true si la dernière action du joueur était un échange
  bool lastActionWasExchange(String playerId) => _lastActionWasExchange[playerId] ?? false;
  
  /// Enregistre plusieurs cartes (ex: après un match)
  void trackMultipleDiscards(List<PlayingCard> cards, {String? discardedBy}) {
    for (final card in cards) {
      trackDiscard(card, discardedBy: discardedBy);
    }
  }
  
  /// Reset pour une nouvelle manche
  void reset() {
    _seenByPoints.clear();
    _seenByValue.clear();
    _playerDiscardHistory.clear();
    _lastActionWasExchange.clear();
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
    
    // Moyenne des points défaussés
    final avgDiscarded = history.reduce((a, b) => a + b) / history.length;
    
    // Si il défausse des cartes hautes (>8), il garde probablement des basses
    final likelyLowHand = avgDiscarded >= 8;
    
    // Estimation du score basée sur les défausses
    // Plus il défausse haut, plus son score estimé est bas
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
    
    // Confiance basée sur le nombre d'observations
    final confidence = min(1.0, history.length / 5.0);
    
    return OpponentHandEstimate(
      playerId: playerId,
      estimatedScore: cardCount * estimatedAvgCard,
      confidence: confidence,
      likelyLowHand: likelyLowHand,
      avgDiscardedPoints: avgDiscarded,
    );
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
      buffer.writeln('  ${entry.key} pts: ${entry.value} vues, $remaining restantes');
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
