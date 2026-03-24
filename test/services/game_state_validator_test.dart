import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/game_state_validator.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('GameStateValidator', () {
    late GameStateValidator validator;
    late GameState gameState;

    setUp(() {
      validator = GameStateValidator();
      
      final players = [
        Player(id: 'human', name: 'Human', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      for (var player in players) {
        player.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];
        player.knownCards = List.filled(4, false, growable: true);
      }

      // Need 52+ cards total: 8 in hands + 1 in discard + 43 in deck = 52
      gameState = GameState(
        players: players,
        deck: GameState.createFullDeck().sublist(0, 43),
        discardPile: [PlayingCard.create('hearts', '3')],
        currentPlayerIndex: 0,
        phase: GamePhase.playing,
      );
    });

    group('validate', () {
      test('returns valid for correct game state', () {
        final result = validator.validate(gameState);
        
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test('detects invalid currentPlayerIndex (negative)', () {
        gameState.currentPlayerIndex = -1;
        
        final result = validator.validate(gameState);
        
        expect(result.isValid, isFalse);
        expect(result.errors, isNotEmpty);
      });

      test('detects invalid currentPlayerIndex (too high)', () {
        gameState.currentPlayerIndex = 100;
        
        final result = validator.validate(gameState);
        
        expect(result.isValid, isFalse);
      });

      test('detects hand/knownCards size mismatch', () {
        gameState.players[0].knownCards = [true, false]; // Only 2, hand has 4
        
        final result = validator.validate(gameState);
        
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.contains('knownCards')), isTrue);
      });

      test('detects empty hand during playing phase', () {
        gameState.players[0].hand = [];
        gameState.players[0].knownCards = [];
        
        final result = validator.validate(gameState);
        
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.contains('main vide')), isTrue);
      });

      test('allows empty hand in ended phase', () {
        gameState.phase = GamePhase.ended;
        gameState.players[0].hand = [];
        gameState.players[0].knownCards = [];
        
        final result = validator.validate(gameState);
        
        // May still have other errors but not for empty hand
        expect(result.errors.any((e) => e.contains('main vide')), isFalse);
      });

      test('detects invalid dutch caller', () {
        gameState.dutchCallerId = 'non_existent_player';
        
        final result = validator.validate(gameState);
        
        expect(result.isValid, isFalse);
        expect(result.errors.any((e) => e.contains('Dutch caller')), isTrue);
      });

      test('validates correct dutch caller', () {
        gameState.dutchCallerId = 'human';
        
        final result = validator.validate(gameState);
        
        expect(result.errors.any((e) => e.contains('Dutch caller')), isFalse);
      });
    });

    group('canPerformAction', () {
      test('draw action allowed in playing phase with no drawn card', () {
        gameState.phase = GamePhase.playing;
        gameState.drawnCard = null;
        
        expect(validator.canPerformAction(gameState, 'draw'), isTrue);
      });

      test('draw action not allowed with drawn card', () {
        gameState.phase = GamePhase.playing;
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        expect(validator.canPerformAction(gameState, 'draw'), isFalse);
      });

      test('draw action not allowed in reaction phase', () {
        gameState.phase = GamePhase.reaction;
        gameState.drawnCard = null;
        
        expect(validator.canPerformAction(gameState, 'draw'), isFalse);
      });

      test('replace action allowed with drawn card', () {
        gameState.phase = GamePhase.playing;
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        expect(validator.canPerformAction(gameState, 'replace'), isTrue);
      });

      test('replace action not allowed without drawn card', () {
        gameState.phase = GamePhase.playing;
        gameState.drawnCard = null;
        
        expect(validator.canPerformAction(gameState, 'replace'), isFalse);
      });

      test('discard action allowed with drawn card', () {
        gameState.phase = GamePhase.playing;
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        expect(validator.canPerformAction(gameState, 'discard'), isTrue);
      });

      test('match action allowed in reaction phase', () {
        gameState.phase = GamePhase.reaction;
        gameState.discardPile = [PlayingCard.create('hearts', '5')];
        
        expect(validator.canPerformAction(gameState, 'match'), isTrue);
      });

      test('match action not allowed in playing phase', () {
        gameState.phase = GamePhase.playing;
        gameState.discardPile = [PlayingCard.create('hearts', '5')];
        
        expect(validator.canPerformAction(gameState, 'match'), isFalse);
      });

      test('match action not allowed with empty discard pile', () {
        gameState.phase = GamePhase.reaction;
        gameState.discardPile = [];
        
        expect(validator.canPerformAction(gameState, 'match'), isFalse);
      });

      test('dutch action allowed when not called', () {
        gameState.dutchCallerId = null;
        
        expect(validator.canPerformAction(gameState, 'dutch'), isTrue);
      });

      test('dutch action not allowed when already called', () {
        gameState.dutchCallerId = 'human';
        
        expect(validator.canPerformAction(gameState, 'dutch'), isFalse);
      });

      test('unknown action returns false', () {
        expect(validator.canPerformAction(gameState, 'unknown_action'), isFalse);
      });
    });

    group('canUsePower', () {
      test('returns true when waiting for power and current player', () {
        gameState.phase = GamePhase.specialPower;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        gameState.currentPlayerIndex = 0;
        
        expect(validator.canUsePower(gameState, gameState.players[0]), isTrue);
      });

      test('returns true when phase specialPower and current player match even if waiting flag is false', () {
        gameState.phase = GamePhase.specialPower;
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        expect(validator.canUsePower(gameState, gameState.players[0]), isTrue);
      });

      test('returns false when no special card', () {
        gameState.phase = GamePhase.specialPower;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = null;
        
        expect(validator.canUsePower(gameState, gameState.players[0]), isFalse);
      });

      test('returns false for non-current player', () {
        gameState.phase = GamePhase.specialPower;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        gameState.currentPlayerIndex = 0;
        
        expect(validator.canUsePower(gameState, gameState.players[1]), isFalse);
      });
    });

    group('ValidationResult', () {
      test('toString returns valid message when valid', () {
        final result = ValidationResult(isValid: true, errors: []);
        
        expect(result.toString(), contains('valide'));
      });

      test('toString returns errors when invalid', () {
        final result = ValidationResult(
          isValid: false, 
          errors: ['Error 1', 'Error 2'],
        );
        
        expect(result.toString(), contains('invalide'));
        expect(result.toString(), contains('Error 1'));
        expect(result.toString(), contains('Error 2'));
      });
    });
  });
}
