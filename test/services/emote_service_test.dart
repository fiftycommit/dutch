import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/emote_service.dart';

void main() {
  group('EmoteService', () {
    late EmoteService emoteService;

    setUp(() {
      emoteService = EmoteService();
    });

    test('should emit emote events when sendEmote is called', () async {
      final emotes = <EmoteEvent>[];
      final subscription = emoteService.emoteStream.listen((emote) {
        emotes.add(emote);
      });

      emoteService.sendEmote('😂', 'Player1', 'player1_id');
      emoteService.sendEmote('🎉', 'Player2', 'player2_id');

      await Future.delayed(const Duration(milliseconds: 100));

      expect(emotes.length, 2);
      expect(emotes[0].emoji, '😂');
      expect(emotes[0].playerName, 'Player1');
      expect(emotes[0].playerId, 'player1_id');
      expect(emotes[1].emoji, '🎉');
      expect(emotes[1].playerName, 'Player2');
      expect(emotes[1].playerId, 'player2_id');

      await subscription.cancel();
    });

    test('should create EmoteEvent with timestamp', () async {
      final before = DateTime.now();
      
      EmoteEvent? receivedEmote;
      final subscription = emoteService.emoteStream.listen((emote) {
        receivedEmote = emote;
      });

      emoteService.sendEmote('👍', 'TestPlayer', 'test_id');

      await Future.delayed(const Duration(milliseconds: 100));

      final after = DateTime.now();

      expect(receivedEmote, isNotNull);
      expect(receivedEmote!.timestamp.isAfter(before) || 
             receivedEmote!.timestamp.isAtSameMomentAs(before), isTrue);
      expect(receivedEmote!.timestamp.isBefore(after) || 
             receivedEmote!.timestamp.isAtSameMomentAs(after), isTrue);

      await subscription.cancel();
    });

    test('should support multiple listeners', () async {
      final emotes1 = <EmoteEvent>[];
      final emotes2 = <EmoteEvent>[];

      final subscription1 = emoteService.emoteStream.listen((emote) {
        emotes1.add(emote);
      });

      final subscription2 = emoteService.emoteStream.listen((emote) {
        emotes2.add(emote);
      });

      emoteService.sendEmote('🔥', 'Player1', 'player1_id');

      await Future.delayed(const Duration(milliseconds: 100));

      expect(emotes1.length, 1);
      expect(emotes2.length, 1);
      expect(emotes1[0].emoji, '🔥');
      expect(emotes2[0].emoji, '🔥');

      await subscription1.cancel();
      await subscription2.cancel();
    });

    test('should handle rapid emote sending', () async {
      final emotes = <EmoteEvent>[];
      final subscription = emoteService.emoteStream.listen((emote) {
        emotes.add(emote);
      });

      for (int i = 0; i < 10; i++) {
        emoteService.sendEmote('😎', 'Player$i', 'player${i}_id');
      }

      await Future.delayed(const Duration(milliseconds: 100));

      expect(emotes.length, 10);
      for (int i = 0; i < 10; i++) {
        expect(emotes[i].playerName, 'Player$i');
      }

      await subscription.cancel();
    });
  });
}
