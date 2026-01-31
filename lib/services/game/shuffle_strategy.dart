import 'dart:math';
import '../models/card.dart';

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

/// Mélange basé sur un modèle ML (futur)
class MLShuffleStrategy implements ShuffleStrategy {
  final String difficulty;
  final Random _random = Random();

  MLShuffleStrategy(this.difficulty);

  @override
  String get name => 'ML-$difficulty';

  @override
  List<PlayingCard> shuffle(List<PlayingCard> deck) {
    // TODO: Implémenter le mélange basé sur le modèle ML
    // Pour l'instant, utilise le mélange aléatoire
    final shuffled = List<PlayingCard>.from(deck);
    shuffled.shuffle(_random);
    return shuffled;
  }
}
