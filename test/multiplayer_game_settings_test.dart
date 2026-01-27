import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';

void main() {
  group('Multiplayer GameSettings', () {
    test('serializes and parses min/max players and fillBots', () {
      final settings = GameSettings(
        gameMode: GameMode.tournament,
        minPlayers: 3,
        maxPlayers: 4,
        fillBots: false,
        reactionTimeMs: 4500,
      );

      final json = settings.toJson();
      expect(json['minPlayers'], 3);
      expect(json['maxPlayers'], 4);
      expect(json['fillBots'], isFalse);
      expect(json['gameMode'], GameMode.tournament.index);

      final parsed = GameSettings.fromJson(json);
      expect(parsed.gameMode, GameMode.tournament);
      expect(parsed.minPlayers, 3);
      expect(parsed.maxPlayers, 4);
      expect(parsed.fillBots, isFalse);
      expect(parsed.reactionTimeMs, 4500);
    });
  });
}
