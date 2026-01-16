import 'card.dart';
import 'game_settings.dart'; // ✅ Correction : Import nécessaire pour BotPersonality

class Player {
  final String id;
  final String name;
  final bool isHuman;
  final BotPersonality? botPersonality;
  final int position; // ✅ Restauré : Nécessaire pour l'initialisation

  // On garde la liste stricte (non-nullable) comme validé précédemment
  List<PlayingCard> hand; 
  
  List<bool> knownCards;

  Player({
    required this.id,
    required this.name,
    required this.isHuman,
    this.botPersonality,
    this.position = 0, // ✅ Restauré : Valeur par défaut
    List<PlayingCard>? hand,
    List<bool>? knownCards,
  }) : 
    hand = hand ?? [],
    knownCards = knownCards ?? [];
    
  Player.clone(Player other) 
    : id = other.id,
      name = other.name,
      isHuman = other.isHuman,
      botPersonality = other.botPersonality,
      position = other.position, // ✅ Restauré : Copie de la position
      hand = List.from(other.hand),
      knownCards = List.from(other.knownCards);

  // ✅ RESTAURÉ : Méthode vitale pour le calcul des scores (GameLogic)
  int calculateScore() {
    int score = 0;
    for (var card in hand) {
      score += card.points;
    }
    return score;
  }

  // ✅ RESTAURÉ : Getter pour l'affichage du nom (PlayerAvatar)
  String get displayName => name;

  // ✅ RESTAURÉ : Getter pour l'avatar (PlayerAvatar)
  String get displayAvatar {
    if (isHuman) return "😎"; 
    
    if (botPersonality != null) {
      switch (botPersonality!) {
        case BotPersonality.beginner: return "👶";
        case BotPersonality.novice: return "😐";
        case BotPersonality.balanced: return "🙂";
        case BotPersonality.cautious: return "🛡️";
        case BotPersonality.aggressive: return "⚔️";
        case BotPersonality.legend: return "👑";
      }
    }
    return "🤖"; 
  }
}