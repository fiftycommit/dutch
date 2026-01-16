class PlayingCard {
  final String suit; // 'hearts', 'diamonds', 'clubs', 'spades', 'joker'
  final String value; // 'A', '2', ..., '10', 'J', 'Q', 'K', 'JOKER'
  final int points;
  final bool isSpecial;
  final String id;

  PlayingCard({
    required this.suit,
    required this.value,
    required this.points,
    required this.isSpecial,
    required this.id,
  });

  factory PlayingCard.create(String suit, String value) {
    int points = _calculatePoints(suit, value);
    bool isSpecial = _isSpecialCard(value);
    String id = '${value}_$suit';

    return PlayingCard(
      suit: suit,
      value: value,
      points: points,
      isSpecial: isSpecial,
      id: id,
    );
  }

  String get matchValue {
    // Pour les Rois, on différencie par couleur
    if (value == 'K') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return 'K_RED';  // Roi rouge
      } else {
        return 'K_BLACK'; // Roi noir
      }
    }
    // Pour les Jokers, ils matchent entre eux
    if (value == 'JOKER') {
      return 'JOKER';
    }
    // Pour les autres cartes, la valeur suffit
    return value;
  }

  String get imagePath {
    // Cas du Joker
    if (value == 'JOKER') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return 'assets/images/cards/joker-rouge.svg';
      }
      return 'assets/images/cards/joker-noir.svg';
    }

    String fileValue;
    switch (value) {
      case 'A': fileValue = '01'; break;
      case 'J': case 'V': fileValue = 'V'; break; // Valet
      case 'Q': case 'D': fileValue = 'D'; break; // Dame
      case 'K': case 'R': fileValue = 'R'; break; // Roi
      default: 
        // Pour 2 à 10, on ajoute un '0' devant si nécessaire (ex: '2' -> '02')
        if (int.tryParse(value) != null) {
          fileValue = value.padLeft(2, '0');
        } else {
          fileValue = value;
        }
    }

    // Conversion de la Couleur (anglais -> français)
    String fileSuit;
    switch (suit) {
      case 'hearts': fileSuit = 'coeur'; break;
      case 'diamonds': fileSuit = 'carreau'; break;
      case 'clubs': fileSuit = 'trefle'; break;
      case 'spades': fileSuit = 'pique'; break;
      default: fileSuit = suit;
    }

    return 'assets/images/cards/$fileValue-$fileSuit.svg';
  }

  static int _calculatePoints(String suit, String value) {
    // Roi rouge = 0 points
    if (value == 'K' && (suit == 'hearts' || suit == 'diamonds')) return 0; 
    
    // Joker = 0 points
    if (value == 'JOKER') return 0; 
    
    // Roi noir = 13 points
    if (value == 'K' && (suit == 'clubs' || suit == 'spades')) return 13; 
    
    // Dame = 12 points
    if (value == 'Q' || value == 'D') return 12; 
    
    // Valet = 11 points
    if (value == 'J' || value == 'V') return 11; 
    
    // As = 1 point
    if (value == 'A') return 1; 
    
    // Autres cartes (2-10) = leur valeur
    return int.tryParse(value) ?? 0; 
  }

  static bool _isSpecialCard(String value) {
    return ['7', '10', 'V', 'JOKER'].contains(value);
  }

  bool matches(PlayingCard other) {
    return this.matchValue == other.matchValue;
  }

  String get displayName {
    if (value == 'K') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return 'Roi Rouge';
      } else {
        return 'Roi Noir';
      }
    }
    
    if (value == 'JOKER') return 'Joker';
    if (value == 'A') return 'As';
    if (value == 'V' || value == 'J') return 'Valet';
    if (value == 'D' || value == 'Q') return 'Dame';
    
    return value;
  }
}