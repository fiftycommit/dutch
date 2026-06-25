// Tests de la formule de menace re-dérivée headless (Piste 5, signal de
// déstabilisation MORL) + de la règle de proxy STABLE inter-step du runner RL.
//
// 1. Équivalence arithmétique avec la formule Flutter originale (lignes 116-173
//    de human_threat_tracker.dart), décorrélée du sourcing.
// 2. Réactions directionnelles aux mêmes événements (match, cartes, score).
// 3. Équivalence de NIVEAU avec HumanThreatTracker original sur états alignés.
// 4. Déterminisme + pureté RNG (ne perturbe pas EngineRandom).
// 5. Sélection du proxy dynamique (leader BotThreatAnalyzer, exclut le siège RL).
// 6. ⭐ Changement d'identité de proxy entre 2 steps => reward_destab == 0
//    (pas de récompense gratuite due au changement de leader).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/engine_random.dart';
import 'package:dutch_game/services/game/bot/discard_tracker.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_threat_analyzer.dart';
import 'package:dutch_game/services/game/bot/human_threat_tracker.dart';
import 'package:dutch_game/services/game/bot/headless_threat_signal.dart';

import '../../tool/rl_env_runner.dart' show RlEnv;

// Ré-implémentation LITTÉRALE de l'arithmétique originale (human_threat_tracker
// .dart:116-173), pour le test d'équivalence #1 (décorrélée du sourcing).
double _originalArithmetic(
    int initial, int current, int cards, int matches, bool recent) {
  double t = 0;
  final red = initial - current;
  if (red >= 20) {
    t += 25;
  } else if (red >= 12) {
    t += 18;
  } else if (red >= 6) {
    t += 10;
  }
  if (matches >= 3) {
    t += 30;
  } else if (matches >= 2) {
    t += 20;
  } else if (matches >= 1) {
    t += 10;
  }
  if (cards == 1) {
    t += 25;
  } else if (cards == 2) {
    t += 18;
  } else if (cards == 3) {
    t += 8;
  }
  if (current <= 3) {
    t += 20;
  } else if (current <= 6) {
    t += 15;
  } else if (current <= 10) {
    t += 8;
  }
  if (recent) t += 10;
  return t;
}

// Mêmes paliers que HumanThreatTracker (25/45/70).
HumanThreatLevel _levelOf(double score) {
  if (score >= 70) return HumanThreatLevel.critical;
  if (score >= 45) return HumanThreatLevel.high;
  if (score >= 25) return HumanThreatLevel.medium;
  return HumanThreatLevel.low;
}

Player _player(String id, List<String> values, {bool isHuman = false}) {
  final hand = values.map((v) => PlayingCard.create('hearts', v)).toList();
  return Player(
    id: id,
    name: id,
    isHuman: isHuman,
    hand: hand,
    knownCards: List<bool>.filled(hand.length, false),
    position: 0,
  );
}

GameState _gameStateWith(List<Player> players, {int turnCount = 5}) {
  return GameState(
    players: players,
    deck: const [],
    discardPile: const [],
    gameMode: GameMode.quick,
    difficulty: Difficulty.medium,
    turnCount: turnCount,
  );
}

// Pioche d'action légale aléatoire (compact) pour le test #6.
Map<String, dynamic> _pick(Map<String, dynamic> obs, Random rng) {
  final mp = obs['micro_phase'];
  final mask = obs['action_mask'] as Map<String, dynamic>;
  if (mp == 'dutchOrDraw') return {'kind': 'continue_draw'};
  if (mp == 'postDraw') {
    final rep = (mask['replace'] as List).cast<bool>();
    final idxs = [for (var i = 0; i < rep.length; i++) if (rep[i]) i];
    if (idxs.isEmpty || rng.nextBool()) return {'kind': 'discard_drawn'};
    return {'kind': 'replace', 'params': {'index': idxs[rng.nextInt(idxs.length)]}};
  }
  return {'kind': 'skip_power'};
}

void main() {
  // Isolation : trackers partagés réinitialisés autour de chaque test.
  setUp(() {
    BotDutchStrategy.discardTracker.reset();
    HumanThreatTracker().reset();
    EngineRandom.reset();
  });
  tearDown(() {
    BotDutchStrategy.discardTracker.reset();
    HumanThreatTracker().reset();
    EngineRandom.reset();
  });

  // 1 ──────────────────────────────────────────────────────────────────────
  test('1. formula() reproduit exactement l\'arithmétique originale', () {
    for (final initial in [0, 10, 26, 40]) {
      for (final current in [2, 5, 9, 15, 26]) {
        for (final cards in [1, 2, 3, 4, 5]) {
          for (final matches in [0, 1, 2, 3, 4]) {
            for (final recent in [false, true]) {
              final got = HeadlessThreatSignal.formula(
                initialScore: initial,
                currentScore: current,
                currentCards: cards,
                matchCount: matches,
                recentMatch: recent,
              );
              expect(got,
                  _originalArithmetic(initial, current, cards, matches, recent),
                  reason: 'i=$initial c=$current k=$cards m=$matches r=$recent');
            }
          }
        }
      }
    }
  });

  // 2 ──────────────────────────────────────────────────────────────────────
  test('2. scoreFor réagit dans le bon sens aux mêmes événements', () {
    final tracker = DiscardTracker();
    final target = _player('p1', ['5', '5', '5', '5']);
    final gs = _gameStateWith([target], turnCount: 5);
    tracker.recordRoundStartScore(target.id, target.calculateScore());

    final base = HeadlessThreatSignal.scoreFor(gs, target, tracker);

    // (a) un match réussi => menace plus haute (composante 2 + momentum)
    tracker.trackDiscard(PlayingCard.create('spades', '5'),
        discardedBy: target.id,
        actionType: DiscardActionType.matchDiscard,
        turnCount: gs.turnCount);
    final afterMatch = HeadlessThreatSignal.scoreFor(gs, target, tracker);
    expect(afterMatch, greaterThan(base),
        reason: 'un match doit augmenter la menace');

    // (b) moins de cartes + score plus bas => menace plus haute
    final fewer = _player('p1', ['2']);
    final gs2 = _gameStateWith([fewer], turnCount: 5);
    final t2 = DiscardTracker()..recordRoundStartScore(fewer.id, 2);
    final lowCards = HeadlessThreatSignal.scoreFor(gs2, fewer, t2);
    final manyCards = HeadlessThreatSignal.scoreFor(
        _gameStateWith([_player('p1', ['2', '2', '2', '2'])], turnCount: 5),
        _player('p1', ['2', '2', '2', '2']),
        DiscardTracker());
    expect(lowCards, greaterThan(manyCards),
        reason: 'moins de cartes => plus menaçant');

    // (c) borne : score >= 0
    expect(base, greaterThanOrEqualTo(0));
  });

  // 3 ──────────────────────────────────────────────────────────────────────
  test('3. même NIVEAU que HumanThreatTracker original sur états alignés', () {
    final tracker = BotDutchStrategy.discardTracker; // partagé par les deux

    // Scénario LOW : humain 4 cartes, aucune action -> menace nulle des deux côtés.
    {
      final human = _player('human', ['4', '4', '4', '4'], isHuman: true);
      final gs = _gameStateWith([human, _player('bot', ['9', '9'])], turnCount: 4);
      HumanThreatTracker().initializeRound(gs); // initial == current (0 défausse)
      // headless : round-start = score estimé courant => composante 1 == 0
      final cur = human.getEstimatedScoreForOpponent(discardCount: 0);
      tracker.recordRoundStartScore(human.id, cur);

      final headless = _levelOf(HeadlessThreatSignal.scoreFor(gs, human, tracker));
      final original = HumanThreatTracker().calculateThreatLevel(gs);
      expect(headless, original, reason: 'LOW');
    }

    BotDutchStrategy.discardTracker.reset();
    HumanThreatTracker().reset();

    // Scénario MEDIUM : 2 matchs récents -> +20 (matchs) +10 (momentum) = 30 -> medium.
    {
      final human = _player('human', ['4', '4', '4', '4'], isHuman: true);
      final gs = _gameStateWith([human, _player('bot', ['9', '9'])], turnCount: 6);
      HumanThreatTracker().initializeRound(gs);
      final cur = human.getEstimatedScoreForOpponent(discardCount: 0);
      tracker.recordRoundStartScore(human.id, cur);
      // Aligner le compteur de matchs des deux côtés (2 matchs au tour courant).
      for (var i = 0; i < 2; i++) {
        HumanThreatTracker().recordHumanMatch(0, gs.turnCount);
        tracker.trackDiscard(PlayingCard.create('clubs', '4'),
            discardedBy: human.id,
            actionType: DiscardActionType.matchDiscard,
            turnCount: gs.turnCount);
      }
      final headless = _levelOf(HeadlessThreatSignal.scoreFor(gs, human, tracker));
      final original = HumanThreatTracker().calculateThreatLevel(gs);
      expect(headless, original, reason: 'MEDIUM');
    }
  });

  // 4 ──────────────────────────────────────────────────────────────────────
  test('4. déterministe et RNG-pur (ne consomme aucun EngineRandom)', () {
    final tracker = DiscardTracker();
    final target = _player('p1', ['7', '7', '7']);
    final gs = _gameStateWith([target], turnCount: 3);
    tracker.recordRoundStartScore(target.id, target.calculateScore());

    final a = HeadlessThreatSignal.scoreFor(gs, target, tracker);
    final b = HeadlessThreatSignal.scoreFor(gs, target, tracker);
    expect(a, b);

    EngineRandom.seed(123);
    final before = List<int>.generate(4, (_) => EngineRandom.instance.nextInt(1 << 30));
    EngineRandom.seed(123);
    for (var i = 0; i < 5; i++) {
      HeadlessThreatSignal.scoreFor(gs, target, tracker);
    }
    final after = List<int>.generate(4, (_) => EngineRandom.instance.nextInt(1 << 30));
    expect(after, before, reason: 'scoreFor ne doit pas tirer d\'EngineRandom');
  });

  // 5 ──────────────────────────────────────────────────────────────────────
  test('5. proxy = leader BotThreatAnalyzer (score min, hors siège RL)', () {
    final rl = _player('p0', ['3', '3', '3', '3']);
    final weakLeader = _player('p1', ['2']); // 1 carte -> score estimé minimal
    final other = _player('p2', ['6', '6', '6', '6']);
    final gs = _gameStateWith([rl, weakLeader, other], turnCount: 5);

    final report = BotThreatAnalyzer.analyzeOpponents(gs, rl);
    expect(report.leader, isNotNull);
    expect(report.leader!.id, 'p1');
    expect(report.leader!.id, isNot('p0')); // jamais le siège RL
  });

  // 6 ──────────────────────────────────────────────────────────────────────
  test('6. changement d\'identité de proxy => reward_destab == 0 ce step-là',
      () async {
    final rng = Random(7);
    var proxyChanges = 0;

    for (var seed = 0; seed < 40; seed++) {
      final env = RlEnv(episodeId: 'pc$seed');
      var obs = await env.reset(seed);
      String? prevProxy = obs['proxy_seat'] as String?;
      var safety = 0;
      while (obs['done'] != true && safety++ < 5000) {
        obs = await env.step(_pick(obs, rng));
        if (obs['type'] == 'error') break;
        final curProxy = obs['proxy_seat'] as String?;
        final destab = (obs['rewards'] as Map)['destab'] as num;

        if (prevProxy != null && curProxy != null && curProxy != prevProxy) {
          proxyChanges++;
          expect(destab, 0,
              reason: 'seed $seed : proxy $prevProxy->$curProxy doit donner '
                  'destab=0 (pas de comparaison entre deux joueurs)');
        }
        // destab toujours >= 0 (max(0, .))
        expect(destab, greaterThanOrEqualTo(0));
        prevProxy = curProxy;
      }
    }

    expect(proxyChanges, greaterThan(0),
        reason: 'aucun changement de proxy observé sur 40 épisodes — '
            'le test ne prouve rien, augmenter la variété/seed');
  });
}
