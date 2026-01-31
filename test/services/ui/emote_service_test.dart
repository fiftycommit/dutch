import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/ui/emote_service.dart';

void main() {
  group('EmoteEvent', () {
    test('stores all properties', () {
      final timestamp = DateTime.now();
      final event = EmoteEvent(
        emoji: '👍',
        playerName: 'Player 1',
        playerId: 'p1',
        timestamp: timestamp,
      );

      expect(event.emoji, '👍');
      expect(event.playerName, 'Player 1');
      expect(event.playerId, 'p1');
      expect(event.timestamp, timestamp);
    });

    test('can be created with different emojis', () {
      final emojis = ['😀', '😂', '🎉', '👏', '🔥', '❤️'];

      for (final emoji in emojis) {
        final event = EmoteEvent(
          emoji: emoji,
          playerName: 'Test',
          playerId: 'test',
          timestamp: DateTime.now(),
        );
        expect(event.emoji, emoji);
      }
    });
  });

  group('EmoteService', () {
    test('is a singleton', () {
      final service1 = EmoteService();
      final service2 = EmoteService();

      expect(identical(service1, service2), isTrue);
    });

    test('emoteStream is broadcast stream', () {
      final service = EmoteService();

      expect(service.emoteStream.isBroadcast, isTrue);
    });

    test('sendEmote emits event to stream', () async {
      final service = EmoteService();
      final completer = Completer<EmoteEvent>();

      final subscription = service.emoteStream.listen((event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      });

      service.sendEmote('🎮', 'Gamer', 'gamer1');

      final event = await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('No event received'),
      );

      expect(event.emoji, '🎮');
      expect(event.playerName, 'Gamer');
      expect(event.playerId, 'gamer1');

      await subscription.cancel();
    });

    test('sendEmote sets timestamp automatically', () async {
      final service = EmoteService();
      final completer = Completer<EmoteEvent>();
      final beforeSend = DateTime.now();

      final subscription = service.emoteStream.listen((event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      });

      service.sendEmote('⏰', 'Timer', 'timer1');

      final event = await completer.future.timeout(
        const Duration(seconds: 1),
      );
      final afterSend = DateTime.now();

      expect(event.timestamp.isAfter(beforeSend.subtract(const Duration(seconds: 1))), isTrue);
      expect(event.timestamp.isBefore(afterSend.add(const Duration(seconds: 1))), isTrue);

      await subscription.cancel();
    });

    test('multiple listeners receive same event', () async {
      final service = EmoteService();
      final events1 = <EmoteEvent>[];
      final events2 = <EmoteEvent>[];

      final sub1 = service.emoteStream.listen(events1.add);
      final sub2 = service.emoteStream.listen(events2.add);

      service.sendEmote('🎯', 'Target', 'target1');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events1.length, 1);
      expect(events2.length, 1);
      expect(events1.first.emoji, '🎯');
      expect(events2.first.emoji, '🎯');

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
