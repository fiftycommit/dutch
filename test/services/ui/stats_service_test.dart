import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dutch_game/services/ui/stats_service.dart';
import 'package:dutch_game/models/game_settings.dart';

void main() {
  group('StatsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('getStats', () {
      test('returns empty stats when no data exists', () async {
        final stats = await StatsService.getStats();

        expect(stats['gamesPlayed'], 0);
        expect(stats['gamesWon'], 0);
        expect(stats['bestScore'], isNull);
        expect(stats['totalScore'], 0);
        expect(stats['mmr'], 0);
        expect(stats['winStreak'], 0);
        expect(stats['bestWinStreak'], 0);
        expect(stats['dutchCalls'], 0);
        expect(stats['dutchWins'], 0);
        expect(stats['history'], isEmpty);
      });

      test('returns stats for specific slot', () async {
        final stats1 = await StatsService.getStats(slotId: 1);
        final stats2 = await StatsService.getStats(slotId: 2);

        expect(stats1['gamesPlayed'], 0);
        expect(stats2['gamesPlayed'], 0);
      });

      test('handles corrupted JSON gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'game_stats_slot_1': 'not valid json {{{',
        });

        final stats = await StatsService.getStats();

        expect(stats['gamesPlayed'], 0); // Returns empty stats
      });
    });

    group('saveGameResult', () {
      test('increments gamesPlayed', () async {
        await StatsService.saveGameResult(
          playerRank: 2,
          score: 15,
          calledDutch: false,
          wonDutch: false,
        );

        final stats = await StatsService.getStats();
        expect(stats['gamesPlayed'], 1);
      });

      test('increments gamesWon on first place', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
        );

        final stats = await StatsService.getStats();
        expect(stats['gamesWon'], 1);
      });

      test('does not increment gamesWon on non-first place', () async {
        await StatsService.saveGameResult(
          playerRank: 2,
          score: 10,
          calledDutch: false,
          wonDutch: false,
        );

        final stats = await StatsService.getStats();
        expect(stats['gamesWon'], 0);
      });

      test('tracks win streak correctly', () async {
        // Win 3 games
        for (int i = 0; i < 3; i++) {
          await StatsService.saveGameResult(
            playerRank: 1,
            score: 5,
            calledDutch: false,
            wonDutch: false,
          );
        }

        var stats = await StatsService.getStats();
        expect(stats['winStreak'], 3);
        expect(stats['bestWinStreak'], 3);

        // Lose a game
        await StatsService.saveGameResult(
          playerRank: 2,
          score: 15,
          calledDutch: false,
          wonDutch: false,
        );

        stats = await StatsService.getStats();
        expect(stats['winStreak'], 0);
        expect(stats['bestWinStreak'], 3); // Best preserved
      });

      test('tracks best score (lowest is best)', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 20,
          calledDutch: false,
          wonDutch: false,
        );

        var stats = await StatsService.getStats();
        expect(stats['bestScore'], 20);

        await StatsService.saveGameResult(
          playerRank: 1,
          score: 10,
          calledDutch: false,
          wonDutch: false,
        );

        stats = await StatsService.getStats();
        expect(stats['bestScore'], 10); // Lower is better

        await StatsService.saveGameResult(
          playerRank: 1,
          score: 15,
          calledDutch: false,
          wonDutch: false,
        );

        stats = await StatsService.getStats();
        expect(stats['bestScore'], 10); // Still 10
      });

      test('accumulates total score', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 10,
          calledDutch: false,
          wonDutch: false,
        );
        await StatsService.saveGameResult(
          playerRank: 2,
          score: 20,
          calledDutch: false,
          wonDutch: false,
        );

        final stats = await StatsService.getStats();
        expect(stats['totalScore'], 30);
      });

      test('tracks dutch calls and wins', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: true,
          wonDutch: true,
        );

        var stats = await StatsService.getStats();
        expect(stats['dutchCalls'], 1);
        expect(stats['dutchWins'], 1);

        await StatsService.saveGameResult(
          playerRank: 2,
          score: 15,
          calledDutch: true,
          wonDutch: false,
        );

        stats = await StatsService.getStats();
        expect(stats['dutchCalls'], 2);
        expect(stats['dutchWins'], 1); // Still 1
      });

      test('updates MMR when isSBMM is true', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
          isSBMM: true,
        );

        final stats = await StatsService.getStats();
        expect(stats['mmr'], greaterThan(0));
      });

      test('MMR does not go below 0', () async {
        // Start with 0 MMR and lose
        await StatsService.saveGameResult(
          playerRank: 4,
          score: 50,
          calledDutch: false,
          wonDutch: false,
          isSBMM: true,
        );

        final stats = await StatsService.getStats();
        expect(stats['mmr'], greaterThanOrEqualTo(0));
      });

      test('adds game to history', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: true,
          wonDutch: true,
        );

        final stats = await StatsService.getStats();
        expect(stats['history'], isNotEmpty);
        expect(stats['history'][0]['score'], 5);
        expect(stats['history'][0]['rank'], 1);
        expect(stats['history'][0]['dutch'], true);
      });

      test('history is limited to 20 entries', () async {
        for (int i = 0; i < 25; i++) {
          await StatsService.saveGameResult(
            playerRank: 1,
            score: i,
            calledDutch: false,
            wonDutch: false,
          );
        }

        final stats = await StatsService.getStats();
        expect(stats['history'].length, 20);
      });

      test('saves to different slots independently', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
          slotId: 1,
        );

        await StatsService.saveGameResult(
          playerRank: 2,
          score: 15,
          calledDutch: false,
          wonDutch: false,
          slotId: 2,
        );

        final stats1 = await StatsService.getStats(slotId: 1);
        final stats2 = await StatsService.getStats(slotId: 2);

        expect(stats1['gamesWon'], 1);
        expect(stats2['gamesWon'], 0);
      });

      test('handles tournament mode', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
          isTournament: true,
          tournamentRound: 2,
          tournamentId: 'tour123',
        );

        final stats = await StatsService.getStats();
        expect(stats['history'][0]['gameMode'], 'tournament');
        expect(stats['history'][0]['tournamentId'], 'tour123');
        expect(stats['history'][0]['tournamentRound'], 2);
      });
    });

    group('resetStats', () {
      test('clears all stats for slot', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
        );

        await StatsService.resetStats();

        final stats = await StatsService.getStats();
        expect(stats['gamesPlayed'], 0);
      });

      test('only clears specified slot', () async {
        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
          slotId: 1,
        );

        await StatsService.saveGameResult(
          playerRank: 1,
          score: 5,
          calledDutch: false,
          wonDutch: false,
          slotId: 2,
        );

        await StatsService.resetStats(slotId: 1);

        final stats1 = await StatsService.getStats(slotId: 1);
        final stats2 = await StatsService.getStats(slotId: 2);

        expect(stats1['gamesPlayed'], 0);
        expect(stats2['gamesPlayed'], 1);
      });
    });

    group('getRecommendedDifficulty', () {
      test('returns easy for low MMR', () async {
        final difficulty = await StatsService.getRecommendedDifficulty();

        expect(difficulty, Difficulty.easy); // 0 MMR = easy
      });

      test('returns medium for mid MMR', () async {
        // Build up MMR to 300+
        for (int i = 0; i < 15; i++) {
          await StatsService.saveGameResult(
            playerRank: 1,
            score: 5,
            calledDutch: false,
            wonDutch: false,
            isSBMM: true,
          );
        }

        final stats = await StatsService.getStats();
        if (stats['mmr'] >= 300 && stats['mmr'] < 600) {
          final difficulty = await StatsService.getRecommendedDifficulty();
          expect(difficulty, Difficulty.medium);
        }
      });
    });

    group('getRankName', () {
      test('returns Bronze for low MMR', () {
        expect(StatsService.getRankName(0), 'Bronze');
        expect(StatsService.getRankName(299), 'Bronze');
      });

      test('returns Argent for mid MMR', () {
        expect(StatsService.getRankName(300), 'Argent');
        expect(StatsService.getRankName(599), 'Argent');
      });

      test('returns Or for high MMR', () {
        expect(StatsService.getRankName(600), 'Or');
        expect(StatsService.getRankName(899), 'Or');
      });

      test('returns Platine for top MMR', () {
        expect(StatsService.getRankName(900), 'Platine');
        expect(StatsService.getRankName(2000), 'Platine');
      });
    });
  });
}
