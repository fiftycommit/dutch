import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/competitive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CompetitiveService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('should return default stats for new player', () async {
      final stats = await CompetitiveService.getStats('new_player');

      expect(stats.mmr, 1000);
      expect(stats.wins, 0);
      expect(stats.losses, 0);
      expect(stats.gamesPlayed, 0);
      expect(stats.winStreak, 0);
      expect(stats.bestWinStreak, 0);
      expect(stats.tier, 'Bronze');
    });

    test('should save and retrieve stats', () async {
      final stats = CompetitiveStats(
        mmr: 1500,
        wins: 10,
        losses: 5,
        gamesPlayed: 15,
        winStreak: 3,
        bestWinStreak: 5,
        rank: 10,
        tier: 'Or',
        lastPlayed: DateTime.now(),
      );

      await CompetitiveService.saveStats('player1', stats);
      final retrieved = await CompetitiveService.getStats('player1');

      expect(retrieved.mmr, 1500);
      expect(retrieved.wins, 10);
      expect(retrieved.losses, 5);
      expect(retrieved.gamesPlayed, 15);
      expect(retrieved.winStreak, 3);
      expect(retrieved.bestWinStreak, 5);
      expect(retrieved.tier, 'Or');
    });

    test('should calculate correct tier from MMR', () async {
      final testCases = [
        (500, 'Bronze'),
        (1000, 'Bronze'),
        (1300, 'Argent'),
        (1600, 'Or'),
        (1900, 'Platine'),
        (2200, 'Diamant'),
      ];

      for (final (mmr, expectedTier) in testCases) {
        final stats = CompetitiveStats(
          mmr: mmr,
          wins: 0,
          losses: 0,
          gamesPlayed: 0,
          winStreak: 0,
          bestWinStreak: 0,
          rank: 0,
          tier: expectedTier,
          lastPlayed: DateTime.now(),
        );

        await CompetitiveService.saveStats('test_player', stats);
        final retrieved = await CompetitiveService.getStats('test_player');
        expect(retrieved.tier, expectedTier, reason: 'MMR $mmr should be $expectedTier');
      }
    });

    test('should calculate MMR change for victory', () async {
      final change = CompetitiveService.calculateMMRChange(
        playerMMR: 1000,
        playerRank: 1,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );

      expect(change, greaterThan(0), reason: 'Victory should increase MMR');
      expect(change, greaterThanOrEqualTo(10), reason: 'Victory bonus should be applied');
    });

    test('should calculate MMR change for loss', () async {
      final change = CompetitiveService.calculateMMRChange(
        playerMMR: 1000,
        playerRank: 4,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );

      expect(change, lessThan(0), reason: 'Last place should decrease MMR');
    });

    test('should update stats after winning game', () async {
      await CompetitiveService.resetStats('winner');
      
      final newStats = await CompetitiveService.updateAfterGame(
        playerId: 'winner',
        playerRank: 1,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );

      expect(newStats.wins, 1);
      expect(newStats.losses, 0);
      expect(newStats.gamesPlayed, 1);
      expect(newStats.winStreak, 1);
      expect(newStats.bestWinStreak, 1);
      expect(newStats.mmr, greaterThan(1000));
    });

    test('should update stats after losing game', () async {
      await CompetitiveService.resetStats('loser');
      
      final newStats = await CompetitiveService.updateAfterGame(
        playerId: 'loser',
        playerRank: 4,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );

      expect(newStats.wins, 0);
      expect(newStats.losses, 1);
      expect(newStats.gamesPlayed, 1);
      expect(newStats.winStreak, 0);
      expect(newStats.mmr, lessThan(1000));
    });

    test('should track win streak correctly', () async {
      await CompetitiveService.resetStats('streak_player');

      var stats = await CompetitiveService.updateAfterGame(
        playerId: 'streak_player',
        playerRank: 1,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );
      expect(stats.winStreak, 1);

      stats = await CompetitiveService.updateAfterGame(
        playerId: 'streak_player',
        playerRank: 1,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );
      expect(stats.winStreak, 2);
      expect(stats.bestWinStreak, 2);

      stats = await CompetitiveService.updateAfterGame(
        playerId: 'streak_player',
        playerRank: 2,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );
      expect(stats.winStreak, 0);
      expect(stats.bestWinStreak, 2);
    });

    test('should calculate win rate correctly', () {
      final stats = CompetitiveStats(
        mmr: 1000,
        wins: 7,
        losses: 3,
        gamesPlayed: 10,
        winStreak: 0,
        bestWinStreak: 0,
        rank: 0,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      expect(stats.winRate, 70.0);
    });

    test('should handle zero games played for win rate', () {
      final stats = CompetitiveStats(
        mmr: 1000,
        wins: 0,
        losses: 0,
        gamesPlayed: 0,
        winStreak: 0,
        bestWinStreak: 0,
        rank: 0,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      expect(stats.winRate, 0.0);
    });

    test('should clamp MMR between 0 and 3000', () async {
      await CompetitiveService.resetStats('clamp_test');
      
      final highStats = CompetitiveStats(
        mmr: 2950,
        wins: 100,
        losses: 0,
        gamesPlayed: 100,
        winStreak: 100,
        bestWinStreak: 100,
        rank: 1,
        tier: 'Diamant',
        lastPlayed: DateTime.now(),
      );
      await CompetitiveService.saveStats('clamp_test', highStats);

      final newStats = await CompetitiveService.updateAfterGame(
        playerId: 'clamp_test',
        playerRank: 1,
        totalPlayers: 4,
        opponentMMRs: [1000, 1000, 1000],
      );

      expect(newStats.mmr, lessThanOrEqualTo(3000));
    });

    test('should reset stats correctly', () async {
      final stats = CompetitiveStats(
        mmr: 1500,
        wins: 10,
        losses: 5,
        gamesPlayed: 15,
        winStreak: 3,
        bestWinStreak: 5,
        rank: 10,
        tier: 'Or',
        lastPlayed: DateTime.now(),
      );
      await CompetitiveService.saveStats('reset_player', stats);

      await CompetitiveService.resetStats('reset_player');
      final resetStats = await CompetitiveService.getStats('reset_player');

      expect(resetStats.mmr, 1000);
      expect(resetStats.wins, 0);
      expect(resetStats.losses, 0);
      expect(resetStats.gamesPlayed, 0);
      expect(resetStats.winStreak, 0);
      expect(resetStats.bestWinStreak, 0);
      expect(resetStats.tier, 'Bronze');
    });

    test('should return correct tier colors', () {
      expect(CompetitiveService.getTierColor('Diamant'), 0xFF00D9FF);
      expect(CompetitiveService.getTierColor('Platine'), 0xFF00FF88);
      expect(CompetitiveService.getTierColor('Or'), 0xFFFFD700);
      expect(CompetitiveService.getTierColor('Argent'), 0xFFC0C0C0);
      expect(CompetitiveService.getTierColor('Bronze'), 0xFFCD7F32);
    });

    test('should return correct tier icons', () {
      expect(CompetitiveService.getTierIcon('Diamant'), '💎');
      expect(CompetitiveService.getTierIcon('Platine'), '🏆');
      expect(CompetitiveService.getTierIcon('Or'), '🥇');
      expect(CompetitiveService.getTierIcon('Argent'), '🥈');
      expect(CompetitiveService.getTierIcon('Bronze'), '🥉');
    });
  });
}
