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

  // Factory pour créer les cartes
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

  // ✅ Le getter pour l'affichage des images
  String get imagePath {
    // Cas du Joker
    if (value == 'JOKER') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return 'assets/images/cards/joker-rouge.svg';
      }
      return 'assets/images/cards/joker-noir.svg';
    }

    // Conversion de la Valeur (ex: 'A' -> '01', 'K' -> 'R')
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
    if (value == 'K' && (suit == 'hearts' || suit == 'diamonds')) return 0; 
    if (value == 'JOKER') return 0; 
    if (value == 'K' && (suit == 'clubs' || suit == 'spades')) return 13; 
    if (value == 'Q' || value == 'D') return 12; 
    if (value == 'J' || value == 'V') return 11; 
    if (value == 'A') return 1; 
    return int.tryParse(value) ?? 0; 
  }

  // ✅ CORRECTION : Seulement 7, 10, V et JOKER ont des pouvoirs
  static bool _isSpecialCard(String value) {
    return ['7', '10', 'V', 'JOKER'].contains(value);
  }
}