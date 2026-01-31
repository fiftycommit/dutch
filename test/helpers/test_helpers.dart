import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Crée un joueur humain pour les tests
Player createHumanPlayer({String id = 'human', String name = 'Joueur'}) {
  return Player(id: id, name: name, isHuman: true, position: 0);
}

/// Crée un joueur bot pour les tests
Player createBotPlayer({
  String id = 'bot',
  String name = 'Bot',
  int position = 1,
  BotBehavior behavior = BotBehavior.balanced,
  BotSkillLevel skillLevel = BotSkillLevel.silver,
}) {
  return Player(
    id: id,
    name: name,
    isHuman: false,
    position: position,
    botBehavior: behavior,
    botSkillLevel: skillLevel,
  );
}

/// Crée une liste de joueurs standard (1 humain + n bots)
List<Player> createStandardPlayers({int botCount = 2}) {
  final players = <Player>[createHumanPlayer()];
  for (int i = 0; i < botCount; i++) {
    players.add(createBotPlayer(
      id: 'bot_$i',
      name: 'Bot ${i + 1}',
      position: i + 1,
    ));
  }
  return players;
}

/// Crée une carte spécifique pour les tests
PlayingCard createCard(String suit, String value) {
  return PlayingCard.create(suit, value);
}

/// Crée un GameState initialisé pour les tests
GameState createTestGameState({
  int playerCount = 3,
  GameMode gameMode = GameMode.quick,
  Difficulty difficulty = Difficulty.medium,
  GamePhase phase = GamePhase.playing,
}) {
  final players = createStandardPlayers(botCount: playerCount - 1);
  final gameState = GameLogic.initializeGame(
    players: players,
    gameMode: gameMode,
    difficulty: difficulty,
  );
  gameState.phase = phase;
  return gameState;
}

/// Crée un GameState avec des cartes spécifiques pour les tests déterministes
GameState createDeterministicGameState({
  List<PlayingCard>? humanHand,
  List<PlayingCard>? bot1Hand,
  List<PlayingCard>? discardPile,
  List<PlayingCard>? deck,
  GamePhase phase = GamePhase.playing,
}) {
  final human = createHumanPlayer();
  final bot1 = createBotPlayer(id: 'bot_0', name: 'Bot 1', position: 1);
  
  human.hand = humanHand ?? [
    createCard('hearts', 'A'),
    createCard('diamonds', '2'),
    createCard('clubs', '3'),
    createCard('spades', '4'),
  ];
  human.knownCards = List.filled(human.hand.length, true, growable: true);
  
  bot1.hand = bot1Hand ?? [
    createCard('hearts', '5'),
    createCard('diamonds', '6'),
    createCard('clubs', '7'),
    createCard('spades', '8'),
  ];
  bot1.knownCards = List.filled(bot1.hand.length, false, growable: true);
  bot1.mentalMap = List.filled(bot1.hand.length, null, growable: true);
  
  return GameState(
    players: [human, bot1],
    deck: deck ?? _createTestDeck(),
    discardPile: discardPile ?? [createCard('hearts', '9')],
    phase: phase,
    currentPlayerIndex: 0,
  );
}

List<PlayingCard> _createTestDeck() {
  return [
    createCard('hearts', '10'),
    createCard('diamonds', 'V'),
    createCard('clubs', 'D'),
    createCard('spades', 'R'),
    createCard('hearts', '2'),
    createCard('diamonds', '3'),
  ];
}

/// Vérifie tous les invariants d'un GameState
/// Lance une exception si un invariant est violé
class GameStateInvariants {
  /// Vérifie que toutes les cartes sont uniques (pas de doublons)
  static void assertNoDuplicateCards(GameState gs) {
    final allCards = <String>{};
    
    // Cartes dans le deck
    for (var card in gs.deck) {
      if (!allCards.add(card.id)) {
        throw StateError('Carte dupliquée dans le deck: ${card.id}');
      }
    }
    
    // Cartes dans la défausse
    for (var card in gs.discardPile) {
      if (!allCards.add(card.id)) {
        throw StateError('Carte dupliquée dans la défausse: ${card.id}');
      }
    }
    
    // Cartes dans les mains des joueurs
    for (var player in gs.players) {
      for (var card in player.hand) {
        if (card.isHidden) continue; // Ignorer les cartes masquées en multi
        if (!allCards.add(card.id)) {
          throw StateError('Carte dupliquée dans la main de ${player.name}: ${card.id}');
        }
      }
    }
    
    // Carte piochée
    if (gs.drawnCard != null) {
      if (!allCards.add(gs.drawnCard!.id)) {
        throw StateError('drawnCard dupliquée: ${gs.drawnCard!.id}');
      }
    }
  }
  
  /// Vérifie que le total des cartes est constant (54 cartes standard)
  static void assertTotalCardsConstant(GameState gs, {int expectedTotal = 54}) {
    int total = gs.deck.length + gs.discardPile.length;
    for (var player in gs.players) {
      total += player.hand.length;
    }
    if (gs.drawnCard != null) total++;
    
    if (total != expectedTotal) {
      throw StateError('Total cartes incorrect: $total (attendu: $expectedTotal)');
    }
  }
  
  /// Vérifie que les index sont cohérents
  static void assertValidIndices(GameState gs) {
    if (gs.currentPlayerIndex < 0 || gs.currentPlayerIndex >= gs.players.length) {
      throw StateError('currentPlayerIndex invalide: ${gs.currentPlayerIndex}');
    }
    
    for (var player in gs.players) {
      if (player.knownCards.length != player.hand.length) {
        throw StateError(
          'knownCards.length (${player.knownCards.length}) != hand.length (${player.hand.length}) pour ${player.name}'
        );
      }
    }
  }
  
  /// Vérifie que la phase est cohérente avec l'état
  static void assertPhaseCoherence(GameState gs) {
    switch (gs.phase) {
      case GamePhase.ended:
        // En ended, plus d'actions possibles
        if (gs.drawnCard != null) {
          throw StateError('drawnCard devrait être null en phase ended');
        }
        break;
      case GamePhase.reaction:
        // En reaction, la défausse ne doit pas être vide
        if (gs.discardPile.isEmpty) {
          throw StateError('discardPile vide en phase reaction');
        }
        break;
      case GamePhase.dutchCalled:
        // Dutch appelé implique dutchCallerId non null
        if (gs.dutchCallerId == null) {
          throw StateError('dutchCallerId null en phase dutchCalled');
        }
        break;
      default:
        break;
    }
  }
  
  /// Vérifie tous les invariants
  static void assertAllInvariants(GameState gs, {int? expectedTotal}) {
    assertNoDuplicateCards(gs);
    if (expectedTotal != null) {
      assertTotalCardsConstant(gs, expectedTotal: expectedTotal);
    }
    assertValidIndices(gs);
    assertPhaseCoherence(gs);
  }
}

/// Extension pour faciliter les tests sur GameState
extension GameStateTestExtensions on GameState {
  /// Compte le total des cartes dans le jeu
  int get totalCards {
    int total = deck.length + discardPile.length;
    for (var player in players) {
      total += player.hand.length;
    }
    if (drawnCard != null) total++;
    return total;
  }
  
  /// Retourne le joueur humain
  Player get humanPlayer => players.firstWhere((p) => p.isHuman);
  
  /// Retourne le score du joueur humain
  int get humanScore => humanPlayer.calculateScore();
}
