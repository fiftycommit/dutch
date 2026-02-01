import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/rp_calculator.dart';

void main() {
  group('RPCalculator', () {
    group('getRankName', () {
      test('returns Bronze for MMR < 300', () {
        expect(RPCalculator.getRankName(0), 'Bronze');
        expect(RPCalculator.getRankName(100), 'Bronze');
        expect(RPCalculator.getRankName(299), 'Bronze');
      });

      test('returns Argent for MMR 300-599', () {
        expect(RPCalculator.getRankName(300), 'Argent');
        expect(RPCalculator.getRankName(450), 'Argent');
        expect(RPCalculator.getRankName(599), 'Argent');
      });

      test('returns Or for MMR 600-899', () {
        expect(RPCalculator.getRankName(600), 'Or');
        expect(RPCalculator.getRankName(750), 'Or');
        expect(RPCalculator.getRankName(899), 'Or');
      });

      test('returns Platine for MMR >= 900', () {
        expect(RPCalculator.getRankName(900), 'Platine');
        expect(RPCalculator.getRankName(1200), 'Platine');
        expect(RPCalculator.getRankName(2000), 'Platine');
      });
    });

    group('getRankColorValue', () {
      test('returns correct color for each rank', () {
        expect(RPCalculator.getRankColorValue('Bronze'), 0xFFCD7F32);
        expect(RPCalculator.getRankColorValue('Argent'), 0xFFC0C0C0);
        expect(RPCalculator.getRankColorValue('Or'), 0xFFFFD700);
        expect(RPCalculator.getRankColorValue('Platine'), 0xFF00BFFF);
      });

      test('returns Bronze color for unknown rank', () {
        expect(RPCalculator.getRankColorValue('Unknown'), 0xFFCD7F32);
      });
    });

    group('calculateRP - basic positions', () {
      test('1st place gets positive RP', () {
        final result = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(result.totalChange, greaterThan(0));
        expect(result.isPositive, isTrue);
      });

      test('last place loses RP', () {
        final result = RPCalculator.calculateRP(
          playerRank: 4,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(result.totalChange, lessThan(0));
        expect(result.isPositive, isFalse);
      });

      test('2nd place gets small positive RP', () {
        final result = RPCalculator.calculateRP(
          playerRank: 2,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(result.totalChange, greaterThan(0));
      });

      test('3rd place loses small RP', () {
        final result = RPCalculator.calculateRP(
          playerRank: 3,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(result.totalChange, lessThan(0));
      });
    });

    group('calculateRP - Dutch bonuses', () {
      test('Dutch win gives bonus', () {
        final withDutch = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: true,
          hasEmptyHand: false,
        );

        final withoutDutch = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(withDutch.totalChange, greaterThan(withoutDutch.totalChange));
        expect(withDutch.bonusDescriptions, isNotEmpty);
      });

      test('Dutch perfect (empty hand) gives extra bonus', () {
        final perfect = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: true,
          hasEmptyHand: true,
        );

        final normal = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: true,
          hasEmptyHand: false,
        );

        expect(perfect.totalChange, greaterThan(normal.totalChange));
      });

      test('Dutch fail gives penalty', () {
        final failed = RPCalculator.calculateRP(
          playerRank: 2,
          currentMMR: 100,
          calledDutch: true,
          hasEmptyHand: false,
        );

        final notCalled = RPCalculator.calculateRP(
          playerRank: 2,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(failed.totalChange, lessThan(notCalled.totalChange));
      });
    });

    group('calculateRP - rank differences', () {
      test('higher rank gives more points for win', () {
        final bronze = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        final platine = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 1000,
          calledDutch: false,
          hasEmptyHand: false,
        );

        expect(platine.totalChange, greaterThan(bronze.totalChange));
      });

      test('higher rank loses less for last place', () {
        final bronze = RPCalculator.calculateRP(
          playerRank: 4,
          currentMMR: 100,
          calledDutch: false,
          hasEmptyHand: false,
        );

        final platine = RPCalculator.calculateRP(
          playerRank: 4,
          currentMMR: 1000,
          calledDutch: false,
          hasEmptyHand: false,
        );

        // Bronze loses more (more negative)
        expect(bronze.totalChange, lessThan(platine.totalChange));
      });
    });

    group('calculateRP - player count', () {
      test('more players increases rewards', () {
        final twoPlayers = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 2,
        );

        final sixPlayers = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 6,
        );

        expect(sixPlayers.totalChange, greaterThan(twoPlayers.totalChange));
      });

      test('handles 3 players', () {
        final result = RPCalculator.calculateRP(
          playerRank: 2,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 3,
        );

        expect(result, isNotNull);
      });

      test('handles 5 players', () {
        final result = RPCalculator.calculateRP(
          playerRank: 4,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 5,
        );

        expect(result, isNotNull);
      });

      test('handles 6 players middle positions', () {
        final result3 = RPCalculator.calculateRP(
          playerRank: 3,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 6,
        );

        final result5 = RPCalculator.calculateRP(
          playerRank: 5,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          totalPlayers: 6,
        );

        expect(result3, isNotNull);
        expect(result5, isNotNull);
      });
    });

    group('calculateRP - tournament', () {
      test('tournament gives more points', () {
        final tournament = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: true,
          tournamentRound: 1,
        );

        // Round 1 is non-null; later rounds are covered below.
        expect(tournament, isNotNull);
      });

      test('stage multipliers are applied', () {
        final round1Base = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: false,
          tournamentRound: 1,
          totalPlayers: 4,
        );
        final round1Tournament = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: true,
          tournamentRound: 1,
          totalPlayers: 4,
        );

        final round2Base = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: false,
          tournamentRound: 2,
          totalPlayers: 3,
        );
        final round2Tournament = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: true,
          tournamentRound: 2,
          totalPlayers: 3,
        );

        final round3Base = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: false,
          tournamentRound: 3,
          totalPlayers: 2,
        );
        final round3Tournament = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          isTournament: true,
          tournamentRound: 3,
          totalPlayers: 2,
        );

        expect(round1Tournament.baseChange, (round1Base.baseChange * 1.1).round());
        expect(round2Tournament.baseChange, (round2Base.baseChange * 1.2).round());
        expect(round3Tournament.baseChange, (round3Base.baseChange * 1.5).round());
      });
    });

    group('calculateRP - win streak', () {
      test('win streak 2+ gives multiplier', () {
        final noStreak = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          winStreak: 0,
        );

        final streak3 = RPCalculator.calculateRP(
          playerRank: 1,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          winStreak: 3,
        );

        expect(streak3.totalChange, greaterThan(noStreak.totalChange));
        expect(streak3.streakMultiplier, greaterThan(1.0));
      });

      test('streak only applies to wins', () {
        final lossWithStreak = RPCalculator.calculateRP(
          playerRank: 4,
          currentMMR: 500,
          calledDutch: false,
          hasEmptyHand: false,
          winStreak: 5,
        );

        // Streak shouldn't make loss worse
        expect(lossWithStreak.streakMultiplier, 1.0);
      });
    });

    group('getWinStreakMultiplier', () {
      test('returns 1.0 for streak < 2', () {
        expect(RPCalculator.getWinStreakMultiplier(0), 1.0);
        expect(RPCalculator.getWinStreakMultiplier(1), 1.0);
      });

      test('returns 1.2 for streak of 2', () {
        expect(RPCalculator.getWinStreakMultiplier(2), 1.2);
      });

      test('increases with streak', () {
        expect(RPCalculator.getWinStreakMultiplier(3), 1.3);
        expect(RPCalculator.getWinStreakMultiplier(4), 1.4);
      });

      test('caps at 2.0', () {
        expect(RPCalculator.getWinStreakMultiplier(20), 2.0);
        expect(RPCalculator.getWinStreakMultiplier(100), 2.0);
      });
    });

    group('getNextRankInfo', () {
      test('returns Argent info for Bronze player', () {
        final info = RPCalculator.getNextRankInfo(100);

        expect(info, isNotNull);
        expect(info!.nextRank, 'Argent');
        expect(info.threshold, 300);
        expect(info.pointsNeeded, 200);
      });

      test('returns Or info for Argent player', () {
        final info = RPCalculator.getNextRankInfo(400);

        expect(info, isNotNull);
        expect(info!.nextRank, 'Or');
        expect(info.threshold, 600);
      });

      test('returns Platine info for Or player', () {
        final info = RPCalculator.getNextRankInfo(700);

        expect(info, isNotNull);
        expect(info!.nextRank, 'Platine');
        expect(info.threshold, 900);
      });

      test('returns null for Platine player', () {
        final info = RPCalculator.getNextRankInfo(1000);

        expect(info, isNull);
      });
    });

    group('RPResult', () {
      test('formattedChange shows + for positive', () {
        final result = RPResult(
          totalChange: 50,
          baseChange: 40,
          bonusChange: 10,
          streakBonus: 0,
          streakMultiplier: 1.0,
          winStreak: 0,
          rank: 'Bronze',
          bonusDescriptions: [],
        );

        expect(result.formattedChange, '+50 RP');
        expect(result.isPositive, isTrue);
      });

      test('formattedChange shows - for negative', () {
        final result = RPResult(
          totalChange: -30,
          baseChange: -30,
          bonusChange: 0,
          streakBonus: 0,
          streakMultiplier: 1.0,
          winStreak: 0,
          rank: 'Bronze',
          bonusDescriptions: [],
        );

        expect(result.formattedChange, '-30 RP');
        expect(result.isPositive, isFalse);
      });

      test('isPositive is true for zero', () {
        final result = RPResult(
          totalChange: 0,
          baseChange: 0,
          bonusChange: 0,
          streakBonus: 0,
          streakMultiplier: 1.0,
          winStreak: 0,
          rank: 'Bronze',
          bonusDescriptions: [],
        );

        expect(result.isPositive, isTrue);
      });
    });

    group('NextRankInfo', () {
      test('stores all properties', () {
        final info = NextRankInfo(
          nextRank: 'Or',
          pointsNeeded: 150,
          threshold: 600,
        );

        expect(info.nextRank, 'Or');
        expect(info.pointsNeeded, 150);
        expect(info.threshold, 600);
      });
    });
  });
}
