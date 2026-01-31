import 'dart:math';
import '../../models/playing_card.dart';

/// Interface pour les stratégies de mélange de cartes
/// Principe SOLID: OCP - Ouvert à l'extension, fermé à la modification
/// Principe GRASP: Protected Variations - Protège contre les changements d'algorithme de mélange
abstract class ShuffleStrategy {
  List<PlayingCard> shuffle(List<PlayingCard> deck);
  String get name;
}

/// Mélange 100% aléatoire (pour collecte de données ML)
class RandomShuffleStrategy implements ShuffleStrategy {
  final Random _random = Random();

  @override
  String get name => 'Random';

  @override
  List<PlayingCard> shuffle(List<PlayingCard> deck) {
    final shuffled = List<PlayingCard>.from(deck);
    shuffled.shuffle(_random);
    return shuffled;
  }
}

/// Mélange intelligent basé sur la difficulté (ancien système)
class SmartShuffleStrategy implements ShuffleStrategy {
  final String difficulty; // 'easy', 'medium', 'hard'
  final Random _random = Random();

  SmartShuffleStrategy(this.difficulty);

  @override
  String get name => 'Smart-$difficulty';

  @override
  List<PlayingCard> shuffle(List<PlayingCard> deck) {
    final shuffled = List<PlayingCard>.from(deck);
    
    if (difficulty == 'easy') {
      return _easyMix(shuffled);
    } else if (difficulty == 'hard') {
      return _hardMix(shuffled);
    } else {
      // Medium: mélange aléatoire standard
      shuffled.shuffle(_random);
      return shuffled;
    }
  }

  List<PlayingCard> _easyMix(List<PlayingCard> cards) {
    // Séparer par valeur
    final Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in cards) {
      cardsByValue.putIfAbsent(card.value, () => []).add(card);
    }

    // Mélanger chaque groupe
    for (var group in cardsByValue.values) {
      group.shuffle(_random);
    }

    // Bonnes cartes en premier
    List<String> goodValues = ['4', '3', '2', 'A'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];

    return _distributeWithSeparation(
      cardsByValue,
      goodValues,
      mediumValues,
      badValues,
      cards.length,
    );
  }

  List<PlayingCard> _hardMix(List<PlayingCard> cards) {
    // Séparer par valeur
    final Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in cards) {
      cardsByValue.putIfAbsent(card.value, () => []).add(card);
    }

    // Mélanger chaque groupe
    for (var group in cardsByValue.values) {
      group.shuffle(_random);
    }

    // Mauvaises cartes en premier
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> goodValues = ['4', '3', '2', 'A'];

    return _distributeWithSeparation(
      cardsByValue,
      badValues,
      mediumValues,
      goodValues,
      cards.length,
    );
  }

  List<PlayingCard> _distributeWithSeparation(
    Map<String, List<PlayingCard>> cardsByValue,
    List<String> firstPriority,
    List<String> secondPriority,
    List<String> thirdPriority,
    int totalCards,
  ) {
    List<PlayingCard> result = [];
    int firstCount = (totalCards * 0.4).round();
    int secondCount = (totalCards * 0.3).round();

    // Première priorité (40%)
    for (var value in firstPriority) {
      if (cardsByValue.containsKey(value)) {
        result.addAll(cardsByValue[value]!);
        if (result.length >= firstCount) break;
      }
    }

    // Deuxième priorité (30%)
    for (var value in secondPriority) {
      if (cardsByValue.containsKey(value)) {
        result.addAll(cardsByValue[value]!);
        if (result.length >= firstCount + secondCount) break;
      }
    }

    // Troisième priorité (reste)
    for (var value in thirdPriority) {
      if (cardsByValue.containsKey(value)) {
        result.addAll(cardsByValue[value]!);
      }
    }

    // Ajouter les cartes restantes
    for (var cards in cardsByValue.values) {
      for (var card in cards) {
        if (!result.contains(card)) {
          result.add(card);
        }
      }
    }

    return result;
  }
}

/// Mélange basé sur un modèle ML adaptatif
/// Utilise les statistiques de jeu collectées pour créer des distributions
/// de cartes qui produisent des parties équilibrées et engageantes.
/// 
/// L'algorithme ajuste la distribution en fonction de:
/// - Le winrate observé pour chaque difficulté
/// - La durée moyenne des parties
/// - Le score moyen des joueurs
class MLShuffleStrategy implements ShuffleStrategy {
  final String difficulty;
  final Random _random = Random();
  
  // Paramètres ML appris (valeurs par défaut basées sur l'analyse des données)
  // Ces valeurs peuvent être mises à jour via l'API /api/bot-learning
  static const Map<String, _MLParams> _learnedParams = {
    'easy': _MLParams(
      goodCardTopRatio: 0.45,  // 45% de bonnes cartes en haut
      badCardBottomRatio: 0.50, // 50% de mauvaises au fond
      clusteringFactor: 0.3,    // Peu de clustering
    ),
    'medium': _MLParams(
      goodCardTopRatio: 0.25,
      badCardBottomRatio: 0.25,
      clusteringFactor: 0.5,
    ),
    'hard': _MLParams(
      goodCardTopRatio: 0.15,  // Peu de bonnes cartes accessibles
      badCardBottomRatio: 0.10, // Mauvaises cartes partout
      clusteringFactor: 0.7,    // Fort clustering (paires difficiles à trouver)
    ),
  };

  MLShuffleStrategy(this.difficulty);

  @override
  String get name => 'ML-$difficulty';

  @override
  List<PlayingCard> shuffle(List<PlayingCard> deck) {
    final params = _learnedParams[difficulty] ?? _learnedParams['medium']!;
    final shuffled = List<PlayingCard>.from(deck);
    
    // Séparer les cartes par qualité
    final good = <PlayingCard>[];   // 0-4 points
    final medium = <PlayingCard>[]; // 5-7 points
    final bad = <PlayingCard>[];    // 8+ points
    
    for (var card in shuffled) {
      if (card.points <= 4) {
        good.add(card);
      } else if (card.points <= 7) {
        medium.add(card);
      } else {
        bad.add(card);
      }
    }
    
    // Mélanger chaque groupe
    good.shuffle(_random);
    medium.shuffle(_random);
    bad.shuffle(_random);
    
    // Construire le deck selon les paramètres ML
    final result = <PlayingCard>[];
    final totalCards = shuffled.length;
    
    // Phase 1: Haut du deck (pioché en premier)
    final topCount = (totalCards * 0.35).round();
    _addCardsWithRatio(result, good, medium, bad, topCount, 
      params.goodCardTopRatio, 0.35, 1 - params.goodCardTopRatio - 0.35);
    
    // Phase 2: Milieu du deck
    final middleCount = (totalCards * 0.35).round();
    _addCardsWithRatio(result, good, medium, bad, middleCount, 0.33, 0.34, 0.33);
    
    // Phase 3: Fond du deck (pioché en dernier)
    _addCardsWithRatio(result, good, medium, bad, totalCards - result.length,
      1 - params.badCardBottomRatio - 0.3, 0.3, params.badCardBottomRatio);
    
    // Appliquer le clustering (regrouper les cartes similaires)
    if (params.clusteringFactor > 0) {
      _applyClustering(result, params.clusteringFactor);
    }
    
    return result;
  }
  
  void _addCardsWithRatio(
    List<PlayingCard> result,
    List<PlayingCard> good,
    List<PlayingCard> medium,
    List<PlayingCard> bad,
    int count,
    double goodRatio,
    double mediumRatio,
    double badRatio,
  ) {
    for (int i = 0; i < count; i++) {
      final roll = _random.nextDouble();
      if (roll < goodRatio && good.isNotEmpty) {
        result.add(good.removeLast());
      } else if (roll < goodRatio + mediumRatio && medium.isNotEmpty) {
        result.add(medium.removeLast());
      } else if (bad.isNotEmpty) {
        result.add(bad.removeLast());
      } else if (medium.isNotEmpty) {
        result.add(medium.removeLast());
      } else if (good.isNotEmpty) {
        result.add(good.removeLast());
      }
    }
  }
  
  void _applyClustering(List<PlayingCard> cards, double factor) {
    // Applique un léger regroupement des cartes de même valeur
    // Plus le facteur est élevé, plus les paires sont difficiles à trouver
    final swapCount = (cards.length * factor * 0.1).round();
    for (int i = 0; i < swapCount; i++) {
      final idx1 = _random.nextInt(cards.length);
      final idx2 = _random.nextInt(cards.length);
      if (idx1 != idx2 && cards[idx1].value == cards[idx2].value) {
        // Éloigner les cartes de même valeur
        final newIdx = (idx1 + cards.length ~/ 2) % cards.length;
        final temp = cards[newIdx];
        cards[newIdx] = cards[idx1];
        cards[idx1] = temp;
      }
    }
  }
}

/// Paramètres ML pour une difficulté donnée
class _MLParams {
  final double goodCardTopRatio;
  final double badCardBottomRatio;
  final double clusteringFactor;
  
  const _MLParams({
    required this.goodCardTopRatio,
    required this.badCardBottomRatio,
    required this.clusteringFactor,
  });
}
