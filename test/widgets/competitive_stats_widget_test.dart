import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/competitive_stats_widget.dart';
import 'package:dutch_game/services/competitive_service.dart';

void main() {
  group('CompetitiveStatsWidget', () {
    final testStats = CompetitiveStats(
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

    testWidgets('should display compact view', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveStatsWidget(
              stats: testStats,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('1500 MMR'), findsOneWidget);
      expect(find.text('Or'), findsOneWidget);
      expect(find.text('🥇'), findsOneWidget);
    });

    testWidgets('should display full view with all stats', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveStatsWidget(
              stats: testStats,
              compact: false,
            ),
          ),
        ),
      );

      expect(find.text('Or'), findsOneWidget);
      expect(find.text('Rang #10'), findsOneWidget);
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2)); // 5 losses et 5 bestWinStreak
      expect(find.text('66.7%'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('should display correct tier icon for each tier', (WidgetTester tester) async {
      final tiers = [
        ('Bronze', '🥉'),
        ('Argent', '🥈'),
        ('Or', '🥇'),
        ('Platine', '🏆'),
        ('Diamant', '💎'),
      ];

      for (final (tier, icon) in tiers) {
        final stats = CompetitiveStats(
          mmr: 1000,
          wins: 0,
          losses: 0,
          gamesPlayed: 0,
          winStreak: 0,
          bestWinStreak: 0,
          rank: 0,
          tier: tier,
          lastPlayed: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CompetitiveStatsWidget(
                stats: stats,
                compact: true,
              ),
            ),
          ),
        );

        expect(find.text(icon), findsOneWidget, reason: 'Tier $tier should show icon $icon');

        await tester.pumpWidget(Container());
      }
    });

    testWidgets('should display win rate correctly', (WidgetTester tester) async {
      final perfectStats = CompetitiveStats(
        mmr: 2000,
        wins: 10,
        losses: 0,
        gamesPlayed: 10,
        winStreak: 10,
        bestWinStreak: 10,
        rank: 1,
        tier: 'Platine',
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveStatsWidget(
              stats: perfectStats,
              compact: false,
            ),
          ),
        ),
      );

      expect(find.text('100.0%'), findsOneWidget);
    });
  });

  group('CompetitiveMatchResult', () {
    testWidgets('should display victory message for first place', (WidgetTester tester) async {
      final stats = CompetitiveStats(
        mmr: 1050,
        wins: 1,
        losses: 0,
        gamesPlayed: 1,
        winStreak: 1,
        bestWinStreak: 1,
        rank: 5,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveMatchResult(
              mmrChange: 50,
              newStats: stats,
              playerRank: 1,
              totalPlayers: 4,
            ),
          ),
        ),
      );

      expect(find.text('🏆 VICTOIRE !'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('→ 1050'), findsOneWidget);
      expect(find.text('Classement: 1/4'), findsOneWidget);
    });

    testWidgets('should display match result for non-victory', (WidgetTester tester) async {
      final stats = CompetitiveStats(
        mmr: 980,
        wins: 0,
        losses: 1,
        gamesPlayed: 1,
        winStreak: 0,
        bestWinStreak: 0,
        rank: 50,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveMatchResult(
              mmrChange: -20,
              newStats: stats,
              playerRank: 3,
              totalPlayers: 4,
            ),
          ),
        ),
      );

      expect(find.text('📊 PARTIE TERMINÉE'), findsOneWidget);
      expect(find.text('-20'), findsOneWidget);
      expect(find.text('→ 980'), findsOneWidget);
      expect(find.text('Classement: 3/4'), findsOneWidget);
    });

    testWidgets('should show positive MMR change with green color', (WidgetTester tester) async {
      final stats = CompetitiveStats(
        mmr: 1030,
        wins: 1,
        losses: 0,
        gamesPlayed: 1,
        winStreak: 1,
        bestWinStreak: 1,
        rank: 10,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveMatchResult(
              mmrChange: 30,
              newStats: stats,
              playerRank: 1,
              totalPlayers: 4,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('+30'), findsOneWidget);
    });

    testWidgets('should show negative MMR change with red color', (WidgetTester tester) async {
      final stats = CompetitiveStats(
        mmr: 970,
        wins: 0,
        losses: 1,
        gamesPlayed: 1,
        winStreak: 0,
        bestWinStreak: 0,
        rank: 50,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetitiveMatchResult(
              mmrChange: -30,
              newStats: stats,
              playerRank: 4,
              totalPlayers: 4,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.text('-30'), findsOneWidget);
    });
  });
}
