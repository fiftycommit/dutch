class PlayingCard {
  final String suit; // 'hearts', 'diamonds', 'clubs', 'spades', 'joker'
  final String value; // 'A', '2', ..., '10', 'V', 'D', 'R', 'JOKER'
  final int points;
  final bool isSpecial;
  final String id;
  final bool isHidden; // Carte masquée (cartes adversaires en multijoueur)

  PlayingCard({
    required this.suit,
    required this.value,
    required this.points,
    required this.isSpecial,
    required this.id,
    this.isHidden = false,
  });

  /// Carte masquée placeholder pour les cartes adversaires en multijoueur
  factory PlayingCard.hidden() {
    return PlayingCard(
      suit: 'hidden',
      value: 'hidden',
      points: 0,
      isSpecial: false,
      id: 'hidden_${DateTime.now().microsecondsSinceEpoch}',
      isHidden: true,
    );
  }

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
    if (value == 'R') {
      return 'R';
    }
    if (value == 'JOKER') {
      return 'JOKER';
    }
    return value;
  }

  String get imagePath {
    // Carte masquée -> dos de carte
    if (isHidden) {
      return 'assets/images/cards/back.svg';
    }

    if (value == 'JOKER') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return 'assets/images/cards/joker-rouge.svg';
      }
      return 'assets/images/cards/joker-noir.svg';
    }

    String fileValue;
    switch (value) {
      case 'A':
        fileValue = '01';
        break;
      case 'V':
        fileValue = 'V';
        break;
      case 'D':
        fileValue = 'D';
        break; 
      case 'R':
        fileValue = 'R';
        break; 
      default:
        if (int.tryParse(value) != null) {
          fileValue = value.padLeft(2, '0');
        } else {
          fileValue = value;
        }
    }

    String fileSuit;
    switch (suit) {
      case 'hearts':
        fileSuit = 'coeur';
        break;
      case 'diamonds':
        fileSuit = 'carreau';
        break;
      case 'clubs':
        fileSuit = 'trefle';
        break;
      case 'spades':
        fileSuit = 'pique';
        break;
      default:
        fileSuit = suit;
    }

    return 'assets/images/cards/$fileValue-$fileSuit.svg';
  }

  static int _calculatePoints(String suit, String value) {
    if (value == 'R' && (suit == 'hearts' || suit == 'diamonds')) return 0;

    if (value == 'JOKER') return 0;

    if (value == 'R' && (suit == 'clubs' || suit == 'spades')) return 13;

    if (value == 'D') return 12;

    if (value == 'V') return 11;

    if (value == 'A') return 1;

    return int.tryParse(value) ?? 0;
  }

  static bool _isSpecialCard(String value) {
    return ['7', '10', 'V', 'JOKER'].contains(value);
  }

  bool matches(PlayingCard other) {
    return matchValue == other.matchValue;
  }

  String get displayName {
    if (value == 'R') {
      if (suit == 'hearts' || suit == 'diamonds') {
        return ' Roi Rouge';
      } else {
        return ' Roi Noir';
      }
    }

    if (value == 'JOKER') return ' Joker';
    if (value == 'A') return ' A';
    if (value == 'V') return ' Valet';
    if (value == 'D') return 'e Dame';

    return ' $value';
  }

  // Sérialisation JSON pour multijoueur
  factory PlayingCard.fromJson(Map<String, dynamic> json) {
    // Carte masquée envoyée par le serveur pour les cartes adversaires
    if (json['hidden'] == true) {
      return PlayingCard.hidden();
    }

    return PlayingCard(
      suit: json['suit'] as String,
      value: json['value'] as String,
      points: json['points'] as int,
      isSpecial: json['isSpecial'] as bool,
      id: json['id'] as String,
      isHidden: false,
    );
  }

  Map<String, dynamic> toJson() {
    if (isHidden) {
      return {'hidden': true};
    }
    return {
      'suit': suit,
      'value': value,
      'points': points,
      'isSpecial': isSpecial,
      'id': id,
    };
  }
}
