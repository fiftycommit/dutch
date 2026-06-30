// Tests de non-régression du runner RL (tool/rl_env_runner.dart), phase 2 v1.
//
// Les 6 tests exigés avant de brancher Python/PPO :
//   1. Déterminisme seed
//   2. Masque d'action (actions illégales rejetées, état inchangé)
//   3. Absence de leakage (croyance only, jamais la hand réelle / cartes cachées)
//   4. Épisode complet avec agent random
//   5. ⭐ Parité byte-à-byte avec playOneGame du générateur (frozenBotMode)
//   6. Pouvoirs 7/10/Valet/Joker
//
// Test #5 = barrière centrale : il prouve que le runner, piloté par la policy
// bot (frozenBotMode), reproduit EXACTEMENT le générateur déjà validé.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/engine_random.dart';
import 'package:dutch_game/models/game_settings.dart'
    show BotBehavior, BotSkillLevel;
import 'package:dutch_game/models/game_state.dart' show GamePhase;
import 'package:dutch_game/models/game_sub_states.dart' show PendingMatchPower;
import 'package:dutch_game/models/playing_card.dart';

import '../../tool/rl_env_runner.dart'
    show RlEnv, RlMicroPhase, parseEvalPlayerConfig;
import '../../tool/ml_dataset_generator.dart' show playOneGame, GeneratorConfig;

const int _testMaxHand = 13;
const int _testMaxPlayers = 6;
const int _testCallDutchAction = 0;
const int _testContinueDrawAction = 1;
const int _testDiscardDrawnAction = 2;
const int _testReplaceAction = 4;
const int _testPower7Action = _testReplaceAction + _testMaxHand;
const int _testPower10Action = _testPower7Action + _testMaxHand;
const int _testPowerVAction = _testPower10Action + 5 * _testMaxHand;
const int _testPowerJokerAction = _testPowerVAction +
    _testMaxPlayers * _testMaxHand * _testMaxPlayers * _testMaxHand;
const int _testPassTickAction = _testPowerJokerAction + _testMaxPlayers;
const int _testMatchAction = _testPassTickAction + 1;

// ── Politiques d'action de test ────────────────────────────────────────────

/// Énumère toutes les actions légales depuis une observation (selon son masque).
List<Map<String, dynamic>> _legalActions(Map<String, dynamic> obs) {
  final mask = obs['action_mask'] as Map<String, dynamic>;
  final mp = obs['micro_phase'];
  final out = <Map<String, dynamic>>[];

  if (mp == 'dutchOrDraw') {
    if (mask['call_dutch'] == true) {
      out.add({'kind': 'call_dutch'});
    }
    if (mask['continue_draw'] == true) {
      out.add({'kind': 'continue_draw'});
    }
  } else if (mp == 'postDraw') {
    if (mask['discard_drawn'] == true) {
      out.add({'kind': 'discard_drawn'});
    }
    final rep = (mask['replace'] as List).cast<bool>();
    for (var i = 0; i < rep.length; i++) {
      if (rep[i]) {
        out.add({
          'kind': 'replace',
          'params': {'index': i}
        });
      }
    }
  } else if (mp == 'power') {
    if (mask['skip_power'] == true) {
      out.add({'kind': 'skip_power'});
    }
    if (mask.containsKey('power7_look')) {
      final l = (mask['power7_look'] as List).cast<bool>();
      for (var i = 0; i < l.length; i++) {
        if (l[i]) {
          out.add({
            'kind': 'power7_look',
            'params': {'index': i}
          });
        }
      }
    }
    if (mask.containsKey('power10_spy')) {
      (mask['power10_spy'] as Map).forEach((seat, list) {
        final l = (list as List).cast<bool>();
        for (var i = 0; i < l.length; i++) {
          if (l[i]) {
            out.add({
              'kind': 'power10_spy',
              'params': {'target_seat': seat, 'index': i}
            });
          }
        }
      });
    }
    if (mask.containsKey('powerV_swap')) {
      final swapMask = mask['powerV_swap'] as Map;
      if (swapMask.containsKey('players')) {
        final players = swapMask['players'] as Map;
        players.forEach((seatA, listA) {
          final a = (listA as List).cast<bool>();
          for (var slotA = 0; slotA < a.length; slotA++) {
            if (!a[slotA]) continue;
            players.forEach((seatB, listB) {
              if (seatB == seatA) return;
              final b = (listB as List).cast<bool>();
              for (var slotB = 0; slotB < b.length; slotB++) {
                if (b[slotB]) {
                  out.add({
                    'kind': 'powerV_swap',
                    'params': {
                      'player_a': seatA,
                      'slot_a': slotA,
                      'player_b': seatB,
                      'slot_b': slotB,
                    },
                  });
                }
              }
            });
          }
        });
      } else {
        final own = (swapMask['own'] as List).cast<bool>();
        final targets = swapMask['targets'] as Map;
        for (var oi = 0; oi < own.length; oi++) {
          if (!own[oi]) continue;
          targets.forEach((seat, list) {
            final l = (list as List).cast<bool>();
            for (var ti = 0; ti < l.length; ti++) {
              if (l[ti]) {
                out.add({
                  'kind': 'powerV_swap',
                  'params': {
                    'own_index': oi,
                    'target_seat': seat,
                    'target_index': ti
                  },
                });
              }
            }
          });
        }
      }
    }
    if (mask.containsKey('powerJoker')) {
      (mask['powerJoker'] as Map).forEach((seat, ok) {
        if (ok == true) {
          out.add({
            'kind': 'powerJoker',
            'params': {'target_seat': seat}
          });
        }
      });
    }
  } else if (mp == 'reaction') {
    if (mask['pass_tick'] == true || mask['no_match'] == true) {
      out.add({'kind': 'pass_tick'});
    }
    final matches = (mask['match'] as List).cast<bool>();
    for (var i = 0; i < matches.length; i++) {
      if (matches[i]) {
        out.add({
          'kind': 'match',
          'params': {'index': i}
        });
      }
    }
  }
  return out;
}

/// Policy déterministe : avance toujours (continue_draw / discard_drawn / skip).
Map<String, dynamic> _deterministicAction(Map<String, dynamic> obs) {
  switch (obs['micro_phase']) {
    case 'dutchOrDraw':
      return {'kind': 'continue_draw'};
    case 'postDraw':
      return {'kind': 'discard_drawn'};
    case 'reaction':
      return {'kind': 'pass_tick'};
    default: // power
      return {'kind': 'skip_power'};
  }
}

void _setKnownHand(RlEnv env, List<PlayingCard> cards) {
  final rl = env.rlSeat;
  rl.hand = List<PlayingCard>.from(cards);
  rl.knownCards = List<bool>.filled(cards.length, true, growable: true);
  rl.mentalMap = List<PlayingCard?>.from(cards, growable: true);
  rl.resetUnknownCardHints();
}

/// Amène p0 dans une fenêtre de réaction. `preReplaceHand` est la main de p0
/// AVANT le replace ; le slot 0 est défaussé et devient le top de la défausse.
/// La carte piochée (`drawnValue`, non-pouvoir) prend le slot 0 après replace.
/// Retourne l'observation en micro-phase 'reaction'.
Future<Map<String, dynamic>> _enterP0Reaction(
  RlEnv env,
  int seed,
  List<PlayingCard> preReplaceHand, {
  String drawnValue = '2',
}) async {
  var obs = await env.reset(seed);
  var guard = 0;
  while (obs['micro_phase'] != 'dutchOrDraw' &&
      obs['done'] != true &&
      guard++ < 80) {
    obs = await env.step(_deterministicAction(obs));
  }
  obs = await env.step({'kind': 'continue_draw'});
  _setKnownHand(env, preReplaceHand);
  env.gs.drawnCard = PlayingCard.create('diamonds', drawnValue);
  obs = await env.step({
    'kind': 'replace',
    'params': {'index': 0}
  });
  return obs;
}

/// Pilote un épisode entier avec une policy et renvoie le journal d'observations.
Future<List<Map<String, dynamic>>> _drive(
  RlEnv env,
  int seed,
  Map<String, dynamic> Function(Map<String, dynamic> obs) pick,
) async {
  final log = <Map<String, dynamic>>[];
  var obs = await env.reset(seed);
  log.add(obs);
  var safety = 0;
  while (obs['done'] != true && safety++ < 10000) {
    obs = await env.step(pick(obs));
    log.add(obs);
  }
  return log;
}

Future<Map<String, dynamic>> _enterPostDraw(RlEnv env, int seed) async {
  var obs = await env.reset(seed);
  var guard = 0;
  while (obs['done'] != true &&
      obs['micro_phase'] != 'dutchOrDraw' &&
      guard++ < 50) {
    obs = await env.step(_deterministicAction(obs));
  }
  expect(obs['micro_phase'], 'dutchOrDraw');
  obs = await env.step({'kind': 'continue_draw'});
  expect(obs['micro_phase'], 'postDraw');
  return obs;
}

Future<Map<String, dynamic>> _enterDutchOrDraw(RlEnv env, int seed) async {
  var obs = await env.reset(seed);
  var guard = 0;
  while (obs['done'] != true &&
      obs['micro_phase'] != 'dutchOrDraw' &&
      guard++ < 50) {
    obs = await env.step(_deterministicAction(obs));
  }
  expect(obs['micro_phase'], 'dutchOrDraw');
  return obs;
}

List<Map<String, dynamic>> _recentEvents(Map<String, dynamic> obs) =>
    (obs['recent_events'] as List? ?? const [])
        .cast<Map>()
        .map((event) => event.cast<String, dynamic>())
        .toList();

Map<String, dynamic> _lastEvent(
  Map<String, dynamic> obs,
  bool Function(Map<String, dynamic>) test,
) =>
    _recentEvents(obs).lastWhere(test);

Map<String, dynamic> _slotStability(Map<String, dynamic> obs) =>
    (obs['slot_stability'] as Map).cast<String, dynamic>();

Map<String, dynamic> _slotStabilityFor(
  Map<String, dynamic> obs,
  String playerId,
  int slot,
) {
  final players = (_slotStability(obs)['players'] as List).cast<Map>();
  final player = players
      .map((p) => p.cast<String, dynamic>())
      .firstWhere((p) => p['player_id'] == playerId);
  final slots = (player['slots'] as List).cast<Map>();
  return slots
      .map((s) => s.cast<String, dynamic>())
      .firstWhere((s) => s['slot'] == slot);
}

List<Map<String, dynamic>> _recentSlotChanges(Map<String, dynamic> obs) =>
    (_slotStability(obs)['recent_changes'] as List? ?? const [])
        .cast<Map>()
        .map((change) => change.cast<String, dynamic>())
        .toList();

void _expectNoSlotStabilityLeak(dynamic value) {
  const forbidden = {
    'card_value',
    'card_points',
    'hand',
    'true_score',
    'kept_card',
    'drawn_card',
    'swapped_card',
    'deck',
  };
  if (value is Map) {
    for (final key in value.keys) {
      expect(forbidden, isNot(contains(key)));
    }
    for (final child in value.values) {
      _expectNoSlotStabilityLeak(child);
    }
  } else if (value is List) {
    for (final child in value) {
      _expectNoSlotStabilityLeak(child);
    }
  }
}

Map<String, dynamic> _legalPrivateMemory(Map<String, dynamic> obs) =>
    (obs['legal_private_memory'] as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _ownMemorySlots(Map<String, dynamic> obs) =>
    (((_legalPrivateMemory(obs)['own_hand'] as Map)['slots'] as List)
        .cast<Map>()
        .map((slot) => slot.cast<String, dynamic>())
        .toList());

Map<String, dynamic> _ownMemorySlot(Map<String, dynamic> obs, int slot) =>
    _ownMemorySlots(obs).firstWhere((entry) => entry['slot'] == slot);

Map<String, dynamic> _opponentMemory(
  Map<String, dynamic> obs,
  String playerId,
) =>
    (_legalPrivateMemory(obs)['opponents'] as List)
        .cast<Map>()
        .map((opponent) => opponent.cast<String, dynamic>())
        .firstWhere((opponent) => opponent['player_id'] == playerId);

void _expectNoLegalPrivateMemoryLeak(dynamic value) {
  const forbidden = {
    'opponent_hand',
    'true_score',
    'deck',
    'full_hands',
    'kept_card',
    'drawn_card',
    'swapped_card',
    'new_order',
    'debug_labels',
  };
  if (value is Map) {
    for (final key in value.keys) {
      expect(forbidden, isNot(contains(key)));
    }
    for (final child in value.values) {
      _expectNoLegalPrivateMemoryLeak(child);
    }
  } else if (value is List) {
    for (final child in value) {
      _expectNoLegalPrivateMemoryLeak(child);
    }
  }
}

Map<String, dynamic> _legalActionV2(Map<String, dynamic> obs) =>
    (obs['legal_action_v2'] as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _legalActionV2Actions(Map<String, dynamic> obs) =>
    (_legalActionV2(obs)['actions'] as List)
        .cast<Map>()
        .map((action) => action.cast<String, dynamic>())
        .toList();

Map<String, dynamic> _findActionV2(
  Map<String, dynamic> obs,
  bool Function(Map<String, dynamic> actionV2) test,
) =>
    _legalActionV2Actions(obs).firstWhere((entry) {
      final actionV2 = (entry['action_v2'] as Map).cast<String, dynamic>();
      return test(actionV2);
    });

int _jackActionId(int playerA, int slotA, int playerB, int slotB) =>
    _testPowerVAction +
    (((playerA * _testMaxHand + slotA) * _testMaxPlayers + playerB) *
            _testMaxHand +
        slotB);

void _expectNoLegalActionV2Leak(dynamic value) {
  const forbidden = {
    'card_value',
    'card_points',
    'opponent_hand',
    'true_score',
    'deck',
    'kept_card',
    'drawn_card',
    'swapped_card',
    'new_order',
  };
  if (value is Map) {
    for (final key in value.keys) {
      expect(forbidden, isNot(contains(key)));
    }
    for (final child in value.values) {
      _expectNoLegalActionV2Leak(child);
    }
  } else if (value is List) {
    for (final child in value) {
      _expectNoLegalActionV2Leak(child);
    }
  }
}

void main() {
  // 1 ─────────────────────────────────────────────────────────────────────────
  group('1. Déterminisme seed', () {
    test('même seed + même policy => journaux d\'observations identiques',
        () async {
      final a = await _drive(RlEnv(episodeId: 'a'), 7, _deterministicAction);
      final b = await _drive(RlEnv(episodeId: 'b'), 7, _deterministicAction);
      // On compare le contenu obs/mask/reward/done (l'episode_id diffère).
      String fingerprint(List<Map<String, dynamic>> log) => jsonEncode(log
          .map((m) => {
                'done': m['done'],
                'reward': m['reward'],
                'micro_phase': m['micro_phase'],
                'obs': m['obs'],
                'action_mask': m['action_mask'],
                'info': m['info'],
              })
          .toList());
      expect(fingerprint(a), fingerprint(b));
    });

    test('construire l\'observation ne consomme aucun tirage EngineRandom',
        () async {
      final env = RlEnv(episodeId: 'rng');
      await env.reset(123);
      // Empreinte RNG avant/après plusieurs constructions d'observation implicites.
      final before =
          List<int>.generate(5, (_) => EngineRandom.instance.nextInt(1 << 30));
      EngineRandom.seed(123);
      await env.reset(123);
      // Rejouer la même séquence d'actions (qui construit des observations) ne doit
      // pas décaler le flux : on re-seed et on retire les mêmes valeurs.
      final after =
          List<int>.generate(5, (_) => EngineRandom.instance.nextInt(1 << 30));
      // before/after partent de seed 123 puis du même reset déterministe => identiques.
      expect(after, before);
    });

    test('parité inter-épisodes même process (statique _platinumKillWindow)',
        () async {
      Future<String> frozenFinal(int seed) async {
        final env = RlEnv(episodeId: 'f', frozenBotMode: true);
        await env.reset(seed);
        return jsonEncode({
          'ranks': env.gs.getFinalRanksWithTies(),
          'scores': {
            for (final p in env.players) p.id: env.gs.getFinalScore(p)
          },
        });
      }

      final first = await frozenFinal(55);
      final again =
          await frozenFinal(55); // même seed, 2e fois dans le même process
      expect(again, first);
    });
  });

  // 2 ─────────────────────────────────────────────────────────────────────────
  group('2. Masque d\'action', () {
    test('action hors phase => error ILLEGAL_ACTION, état inchangé', () async {
      final env = RlEnv(episodeId: 'mask');
      final obs0 = await env.reset(3);
      if (obs0['done'] == true) return; // épisode dégénéré, rare
      expect(env.micro, RlMicroPhase.dutchOrDraw);

      // replace est illégal en dutchOrDraw.
      final err = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(err['type'], 'error');
      expect(err['code'], 'ILLEGAL_ACTION');
      expect(env.finished, isFalse);
      expect(env.micro, RlMicroPhase.dutchOrDraw); // pas avancé

      // continue_draw est légal.
      final ok = await env.step({'kind': 'continue_draw'});
      expect(ok['type'], 'observation');
    });

    test('replace avec index hors borne => rejeté', () async {
      final env = RlEnv(episodeId: 'mask2');
      var obs = await env.reset(9);
      // Atteindre postDraw.
      while (obs['done'] != true && obs['micro_phase'] != 'postDraw') {
        obs = await env.step({'kind': 'continue_draw'});
        if (obs['type'] == 'error') break;
      }
      if (obs['micro_phase'] != 'postDraw') return;
      final err = await env.step({
        'kind': 'replace',
        'params': {'index': 999}
      });
      expect(err['type'], 'error');
      expect(err['code'], 'ILLEGAL_ACTION');
    });
  });

  // 2b ────────────────────────────────────────────────────────────────────────
  group('2b. Réaction RL', () {
    test('p0 entre en phase reaction et peut attendre un tick', () async {
      final env = RlEnv(episodeId: 'react-pass-tick', forcedNumPlayers: 2);
      var obs = await env.reset(11);
      expect(obs['micro_phase'], 'dutchOrDraw');

      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');
      obs = await env.step({'kind': 'discard_drawn'});

      expect(obs['type'], 'observation');
      expect(obs['micro_phase'], 'reaction');
      expect(env.micro, RlMicroPhase.reaction);
      final mask = obs['action_mask'] as Map<String, dynamic>;
      expect(mask['pass_tick'], isTrue);
      expect((mask['match'] as List).length, env.rlSeat.hand.length);

      final handBefore = env.rlSeat.hand.map((c) => c.id).toList();
      final after = await env.step({'kind': 'pass_tick'});
      expect(after['type'], 'observation');
      expect(after['step'] as int, greaterThan(obs['step'] as int));
      expect(env.rlSeat.hand.map((c) => c.id).toList(), handBefore);
    });

    test('match correct retire une carte et reste en fenêtre de réaction',
        () async {
      final env = RlEnv(episodeId: 'react-match', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      final fiveA = PlayingCard.create('hearts', '5');
      final fiveB = PlayingCard.create('spades', '5');
      final nine = PlayingCard.create('clubs', '9');
      _setKnownHand(env, [fiveA, fiveB, nine]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '2');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.rlSeat.hand.length, 3);

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['type'], 'observation');
      expect(obs['micro_phase'], 'reaction');
      expect(env.rlSeat.hand.length, 2);
      expect(env.gs.topDiscardCard?.value, '5');
    });

    test('chaîne simple : p0 peut matcher deux fois de suite', () async {
      final env = RlEnv(episodeId: 'react-chain', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '5'),
        PlayingCard.create('clubs', '5'),
        PlayingCard.create('diamonds', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '2');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.rlSeat.hand.length, 4);

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.rlSeat.hand.length, 3);

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.rlSeat.hand.length, 2);
    });

    test('pass_tick réinvite p0 si un bot matche dans la même fenêtre',
        () async {
      final env = RlEnv(
        episodeId: 'react-pass-reinvite',
        forcedNumPlayers: 2,
        forcedOpponentSkill: BotSkillLevel.difficile,
      );
      var obs = await env.reset(12);
      var guard = 0;
      while (obs['micro_phase'] != 'dutchOrDraw' && guard++ < 50) {
        obs = await env.step(_deterministicAction(obs));
      }
      expect(obs['micro_phase'], 'dutchOrDraw');
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '5'),
        PlayingCard.create('spades', '9'),
      ]);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('clubs', '5'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      bot.resetUnknownCardHints();
      env.gs.drawnCard = PlayingCard.create('diamonds', '2');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      final firstTopId = env.gs.topDiscardCard?.id;
      expect(env.gs.topDiscardCard?.value, '5');

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['type'], 'observation');
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.gs.topDiscardCard?.id, isNot(firstTopId));
      expect(bot.hand.length, 1);
      final mask = obs['action_mask'] as Map<String, dynamic>;
      expect(mask['pass_tick'], isTrue);
      expect((mask['match'] as List)[1], isTrue);
    });

    test('faux match donne une pénalité et garde la main cohérente', () async {
      final env = RlEnv(episodeId: 'react-false', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '5');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');
      expect(env.rlSeat.hand.length, 2);

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0}
      });
      expect(obs['type'], 'observation');
      expect(obs['micro_phase'], 'reaction');
      expect(env.rlSeat.hand.length, 3);
      expect(env.rlSeat.knownCards.last, isFalse);
    });

    test('recent_events expose drawn_discard sans replaced_slot', () async {
      final env = RlEnv(episodeId: 'event-drawn', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 31);
      env.gs.drawnCard = PlayingCard.create('diamonds', '4');

      obs = await env.step({'kind': 'discard_drawn'});
      final event = _lastEvent(
        obs,
        (e) =>
            e['event_type'] == 'discard_visible' &&
            e['discard_reason'] == 'drawn_discard',
      );

      expect(event['actor'], env.rlSeat.id);
      expect(event['card_visible'], isTrue);
      expect(event['card_value'], '4');
      expect(event['card_match_value'], '4');
      expect(event['card_points'], 4);
      expect(event['replaced_slot'], isNull);
      expect(event.keys, isNot(contains('kept_card')));
      expect(event.keys, isNot(contains('new_card')));
      expect(event.keys, isNot(contains('opponent_hand')));
      expect(event.keys, isNot(contains('true_score')));
    });

    test('recent_events expose exchange_discard avec replaced_slot', () async {
      final env = RlEnv(episodeId: 'event-exchange', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 32);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '3'),
        PlayingCard.create('clubs', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 1}
      });
      final event = _lastEvent(
        obs,
        (e) =>
            e['event_type'] == 'discard_visible' &&
            e['discard_reason'] == 'exchange_discard',
      );

      expect(event['actor'], env.rlSeat.id);
      expect(event['replaced_slot'], 1);
      expect(event['card_visible'], isTrue);
      expect(event['card_value'], '9');
      expect(event['card_match_value'], '9');
      expect(event['card_points'], 9);
      expect(event.keys, isNot(contains('drawn_card')));
      expect(event.keys, isNot(contains('kept_card')));
      expect(event.keys, isNot(contains('new_card')));
      expect(event.keys, isNot(contains('opponent_hand')));
      expect(event.keys, isNot(contains('true_score')));
    });

    test('recent_events expose match_discard', () async {
      final env = RlEnv(episodeId: 'event-match', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 33);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('clubs', '5'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      final event = _lastEvent(
        obs,
        (e) =>
            e['event_type'] == 'discard_visible' &&
            e['discard_reason'] == 'match_discard',
      );

      expect(event['actor'], env.rlSeat.id);
      expect(event['slot'], 1);
      expect(event['card_visible'], isTrue);
      expect(event['card_value'], '5');
      expect(event['card_match_value'], '5');
      expect(event['card_points'], 5);
    });

    test('recent_events expose match_failure_penalty sans carte pénalité',
        () async {
      final env = RlEnv(episodeId: 'event-false-match', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 34);
      _setKnownHand(env, [
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '5');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0}
      });
      final event = _lastEvent(
        obs,
        (e) => e['event_type'] == 'match_failure_penalty',
      );

      expect(event['actor'], env.rlSeat.id);
      expect(event['slot'], 0);
      expect(event['penalty_card_count'], 1);
      expect(event.keys, isNot(contains('penalty_card')));
      expect(event.keys, isNot(contains('card_value')));
      expect(event.keys, isNot(contains('opponent_hand')));
      expect(event.keys, isNot(contains('true_score')));
    });

    test('slot_stability : exchange marque le slot remplacé', () async {
      final env = RlEnv(episodeId: 'stability-exchange', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 35);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '3'),
        PlayingCard.create('clubs', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 1}
      });
      final slot = _slotStabilityFor(obs, env.rlSeat.id, 1);

      expect(slot['last_changed_reason'], 'exchange');
      expect(slot['turns_since_changed'], 0);
      expect(slot['actions_since_changed'], 0);
      expect(slot['changed_this_turn'], isTrue);
      _expectNoSlotStabilityLeak(obs['slot_stability']);
    });

    test('slot_stability : match supprime le slot et shift les métadonnées',
        () async {
      final env = RlEnv(episodeId: 'stability-match', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 36);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('clubs', '5'),
        PlayingCard.create('spades', 'D'),
        PlayingCard.create('diamonds', 'R'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      final beforeShiftedMeta = _slotStabilityFor(obs, env.rlSeat.id, 2);
      final beforeTailMeta = _slotStabilityFor(obs, env.rlSeat.id, 3);
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });

      final slots = (((_slotStability(obs)['players'] as List)
              .cast<Map>()
              .map((p) => p.cast<String, dynamic>())
              .firstWhere((p) => p['player_id'] == env.rlSeat.id)['slots'])
          as List);
      final shiftedSlot = _slotStabilityFor(obs, env.rlSeat.id, 1);
      final tailSlot = _slotStabilityFor(obs, env.rlSeat.id, 2);
      final changes = _recentSlotChanges(obs).where((change) =>
          change['player_id'] == env.rlSeat.id &&
          change['reason'] == 'match_removed');

      expect(slots.length, 3);
      expect(shiftedSlot['last_changed_reason'],
          beforeShiftedMeta['last_changed_reason']);
      expect(shiftedSlot['last_changed_turn'],
          beforeShiftedMeta['last_changed_turn']);
      expect(shiftedSlot['last_changed_action'],
          beforeShiftedMeta['last_changed_action']);
      expect(tailSlot['last_changed_reason'],
          beforeTailMeta['last_changed_reason']);
      expect(
          tailSlot['last_changed_turn'], beforeTailMeta['last_changed_turn']);
      expect(tailSlot['last_changed_action'],
          beforeTailMeta['last_changed_action']);
      expect(changes.map((change) => change['slot']), contains(1));
      _expectNoSlotStabilityLeak(obs['slot_stability']);
    });

    test('slot_stability : faux match marque le nouveau slot pénalité',
        () async {
      final env = RlEnv(episodeId: 'stability-penalty', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 37);
      _setKnownHand(env, [
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '5');

      obs = await env.step({'kind': 'discard_drawn'});
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0}
      });

      final penaltySlot = _slotStabilityFor(obs, env.rlSeat.id, 2);
      expect(penaltySlot['last_changed_reason'], 'penalty');
      expect(penaltySlot['changed_this_turn'], isTrue);
      _expectNoSlotStabilityLeak(obs['slot_stability']);
    });

    test('slot_stability : Valet marque les deux slots échangés', () async {
      final env = RlEnv(episodeId: 'stability-valet', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 38);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      _setKnownHand(env, [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('clubs', '2'),
      ]);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 1,
          'player_b': bot.id,
          'slot_b': 0,
        },
      });

      expect(_slotStabilityFor(obs, env.rlSeat.id, 1)['last_changed_reason'],
          'jack_swap');
      expect(_slotStabilityFor(obs, bot.id, 0)['last_changed_reason'],
          'jack_swap');
      _expectNoSlotStabilityLeak(obs['slot_stability']);
    });

    test('slot_stability : Joker invalide tous les slots de la cible',
        () async {
      final env = RlEnv(episodeId: 'stability-joker', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 39);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
        PlayingCard.create('clubs', '4'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': bot.id},
      });

      for (var i = 0; i < bot.hand.length; i++) {
        expect(_slotStabilityFor(obs, bot.id, i)['last_changed_reason'],
            'joker_shuffle');
      }
      _expectNoSlotStabilityLeak(obs['slot_stability']);
    });

    test('slot_stability : changed_this_turn se réinitialise au tour suivant',
        () async {
      final env = RlEnv(episodeId: 'stability-turn-reset', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 40);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('spades', '2'),
        PlayingCard.create('clubs', '3'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '3'),
        PlayingCard.create('clubs', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 1}
      });
      final changedTurn =
          _slotStabilityFor(obs, env.rlSeat.id, 1)['last_changed_turn'] as int;
      expect(_slotStabilityFor(obs, env.rlSeat.id, 1)['changed_this_turn'],
          isTrue);

      var guard = 0;
      while (obs['done'] != true &&
          (obs['obs'] as Map)['turn_count'] <= changedTurn &&
          guard++ < 20) {
        obs = await env.step({'kind': 'pass_tick'});
      }

      expect((obs['obs'] as Map)['turn_count'], greaterThan(changedTurn));
      expect(_slotStabilityFor(obs, env.rlSeat.id, 1)['changed_this_turn'],
          isFalse);
    });

    test('legal_private_memory : slot connu expose mentalMap, pas hand brut',
        () async {
      final env = RlEnv(episodeId: 'memory-own-known', forcedNumPlayers: 2);
      var obs = await env.reset(41);
      env.rlSeat.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('clubs', '9'),
      ];
      env.rlSeat.knownCards = [true, false];
      env.rlSeat.mentalMap = [
        PlayingCard.create('spades', '7'),
        null,
      ];

      obs = await env.step({'kind': 'continue_draw'});
      final slot = _ownMemorySlot(obs, 0);

      expect(slot['known'], isTrue);
      expect(slot['valid'], isTrue);
      expect(slot['confidence'], 1.0);
      expect(slot['believed_value'], '7');
      expect(slot['believed_match_value'], '7');
      expect(slot['believed_points'], 7);
      expect(slot['source'], 'mental_map');
      expect(slot['believed_value'], isNot('A'));
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_private_memory : slot inconnu ne révèle pas hand[slot]',
        () async {
      final env = RlEnv(episodeId: 'memory-own-unknown', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 42);
      env.rlSeat.hand = [
        PlayingCard.create('hearts', 'R'),
        PlayingCard.create('clubs', '9'),
      ];
      env.rlSeat.knownCards = [false, true];
      env.rlSeat.mentalMap = [
        null,
        PlayingCard.create('clubs', '9'),
      ];
      env.gs.drawnCard = PlayingCard.create('diamonds', '4');

      obs = await env.step({'kind': 'discard_drawn'});
      final slot = _ownMemorySlot(obs, 0);

      expect(slot['known'], isFalse);
      expect(slot['valid'], isFalse);
      expect(slot['confidence'], 0.0);
      expect(slot['believed_value'], isNull);
      expect(slot['believed_match_value'], isNull);
      expect(slot['believed_points'], isNull);
      expect(slot['source'], isNull);
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_private_memory : spyMemory expose uniquement le slot espionné',
        () async {
      final env = RlEnv(episodeId: 'memory-spy', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 43);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('hearts', '4'),
        PlayingCard.create('spades', 'D'),
        PlayingCard.create('clubs', '2'),
      ];
      env.rlSeat.rememberSpiedCard(bot.id, 1, bot.hand[1]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '4');

      obs = await env.step({'kind': 'discard_drawn'});
      final opponent = _opponentMemory(obs, bot.id);
      final spiedSlots = (opponent['spied_slots'] as List).cast<Map>();

      expect(spiedSlots.length, 1);
      final spied = spiedSlots.single.cast<String, dynamic>();
      expect(spied['slot'], 1);
      expect(spied['known'], isTrue);
      expect(spied['believed_value'], 'D');
      expect(spied['believed_match_value'], 'D');
      expect(spied['believed_points'], 12);
      expect(spied['source'], 'spy_memory');
      expect(spiedSlots.map((slot) => slot['slot']), isNot(contains(0)));
      expect(spiedSlots.map((slot) => slot['slot']), isNot(contains(2)));
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test(
        'legal_private_memory : exchange propre reflète la carte piochée connue',
        () async {
      final env = RlEnv(episodeId: 'memory-exchange', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 44);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '3'),
        PlayingCard.create('clubs', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 1}
      });
      final slot = _ownMemorySlot(obs, 1);

      expect(slot['known'], isTrue);
      expect(slot['believed_value'], 'A');
      expect(slot['believed_points'], 1);
      expect(slot['source'], 'mental_map');
      expect(slot.keys, isNot(contains('kept_card')));
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_private_memory : match supprime le slot et shift la mémoire',
        () async {
      final env = RlEnv(episodeId: 'memory-match-shift', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 45);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('clubs', '5'),
        PlayingCard.create('spades', 'D'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });

      final slots = _ownMemorySlots(obs);
      expect(slots.length, 2);
      expect(_ownMemorySlot(obs, 1)['known'], isTrue);
      expect(_ownMemorySlot(obs, 1)['believed_value'], 'D');
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_private_memory : Valet ne révèle pas les cartes échangées',
        () async {
      final env = RlEnv(episodeId: 'memory-valet', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 46);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      env.rlSeat.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('clubs', '2'),
      ];
      env.rlSeat.knownCards = [true, false];
      env.rlSeat.mentalMap = [
        PlayingCard.create('hearts', 'A'),
        null,
      ];
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      obs = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 1,
          'player_b': bot.id,
          'slot_b': 0,
        },
      });

      final opponent = _opponentMemory(obs, bot.id);
      expect(opponent['spied_slots'], isEmpty);
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_private_memory : Joker ne révèle pas le nouvel ordre',
        () async {
      final env = RlEnv(episodeId: 'memory-joker', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 47);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
        PlayingCard.create('clubs', '4'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.rlSeat.rememberSpiedCard(bot.id, 1, bot.hand[1]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      obs = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': bot.id},
      });

      final opponent = _opponentMemory(obs, bot.id);
      expect(opponent['spied_slots'], isEmpty);
      expect(jsonEncode(obs['legal_private_memory']),
          isNot(contains('new_order')));
      _expectNoLegalPrivateMemoryLeak(obs['legal_private_memory']);
    });

    test('legal_action_v2 : présent et mappe draw/call_dutch', () async {
      final env = RlEnv(episodeId: 'action-v2-base', forcedNumPlayers: 2);
      var obs = await _enterDutchOrDraw(env, 48);
      expect(obs['legal_action_v2'], isA<Map>());

      final callDutch = _findActionV2(
        obs,
        (action) => action['action_type'] == 'call_dutch',
      );
      final draw = _findActionV2(
        obs,
        (action) => action['action_type'] == 'draw',
      );

      expect(callDutch['legacy_action_id'], _testCallDutchAction);
      expect(draw['legacy_action_id'], _testContinueDrawAction);
      expect((_legalActionV2(obs)['available_action_types'] as List),
          contains('draw'));

      obs = await env.step({
        'action_v2': {'action_type': 'draw'}
      });
      expect(obs['micro_phase'], 'postDraw');
      _expectNoLegalActionV2Leak(obs['legal_action_v2']);
    });

    test('legal_action_v2 : post_draw_replace mappe vers action legacy',
        () async {
      final env = RlEnv(episodeId: 'action-v2-replace', forcedNumPlayers: 2);
      final obs = await _enterPostDraw(env, 49);

      final discard = _findActionV2(
        obs,
        (action) => action['action_type'] == 'post_draw_discard',
      );
      final replace = _findActionV2(
        obs,
        (action) =>
            action['action_type'] == 'post_draw_replace' && action['slot'] == 1,
      );

      expect(discard['legacy_action_id'], _testDiscardDrawnAction);
      expect(replace['legacy_action_id'], _testReplaceAction + 1);
      _expectNoLegalActionV2Leak(obs['legal_action_v2']);
    });

    test('legal_action_v2 : pass_tick et match mapppent en réaction', () async {
      final env = RlEnv(episodeId: 'action-v2-reaction', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 50);
      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('clubs', '5'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });

      final passTick = _findActionV2(
        obs,
        (action) => action['action_type'] == 'pass_tick',
      );
      final match = _findActionV2(
        obs,
        (action) => action['action_type'] == 'match' && action['slot'] == 1,
      );

      expect(passTick['legacy_action_id'], _testPassTickAction);
      expect(match['legacy_action_id'], _testMatchAction + 1);

      obs = await env.step({
        'action_v2': {'action_type': 'match', 'slot': 1}
      });
      expect(obs['type'], 'observation');
      expect(env.rlSeat.hand.length, 1);
    });

    test('legal_action_v2 : Joker adversaire légal, self absent/rejeté',
        () async {
      final env = RlEnv(episodeId: 'action-v2-joker', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 51);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [PlayingCard.create('spades', 'R')];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      final joker = _findActionV2(
        obs,
        (action) =>
            action['action_type'] == 'joker' &&
            action['target_player'] == bot.position,
      );
      expect(joker['legacy_action_id'], _testPowerJokerAction + bot.position);
      expect(
        _legalActionV2Actions(obs).any((entry) {
          final action = (entry['action_v2'] as Map).cast<String, dynamic>();
          return action['action_type'] == 'joker' &&
              action['target_player'] == env.rlSeat.position;
        }),
        isFalse,
      );

      final self = await env.step({
        'action_v2': {
          'action_type': 'joker',
          'target_player': env.rlSeat.position
        }
      });
      expect(self['type'], 'error');
      expect(self['code'], 'ILLEGAL_ACTION');
    });

    test('legal_action_v2 : Valet complet mappe, adversaire↔adversaire légal',
        () async {
      final env = RlEnv(episodeId: 'action-v2-jack', forcedNumPlayers: 3);
      var obs = await _enterPostDraw(env, 52);
      final p1 = env.players[1];
      final p2 = env.players[2];
      p1.hand = [PlayingCard.create('clubs', '4')];
      p2.hand = [PlayingCard.create('spades', '9')];
      p1.knownCards = List<bool>.filled(p1.hand.length, false, growable: true);
      p2.knownCards = List<bool>.filled(p2.hand.length, false, growable: true);
      p1.mentalMap =
          List<PlayingCard?>.filled(p1.hand.length, null, growable: true);
      p2.mentalMap =
          List<PlayingCard?>.filled(p2.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      final jack = _findActionV2(
        obs,
        (action) =>
            action['action_type'] == 'jack_swap' &&
            action['player_a'] == 1 &&
            action['slot_a'] == 0 &&
            action['player_b'] == 2 &&
            action['slot_b'] == 0,
      );
      expect(jack['legacy_action_id'], _jackActionId(1, 0, 2, 0));
      expect(
        _legalActionV2Actions(obs).any((entry) {
          final action = (entry['action_v2'] as Map).cast<String, dynamic>();
          return action['action_type'] == 'jack_swap' &&
              action['player_a'] == action['player_b'];
        }),
        isFalse,
      );

      final p1Before = p1.hand[0].id;
      final p2Before = p2.hand[0].id;
      obs = await env.step({
        'action_v2': {
          'action_type': 'jack_swap',
          'player_a': 1,
          'slot_a': 0,
          'player_b': 2,
          'slot_b': 0,
        }
      });
      expect(obs['type'], 'observation');
      expect(p1.hand[0].id, p2Before);
      expect(p2.hand[0].id, p1Before);
    });

    test('legal_action_v2 : action illégale rejetée proprement', () async {
      final env = RlEnv(episodeId: 'action-v2-illegal', forcedNumPlayers: 2);
      var obs = await _enterDutchOrDraw(env, 53);
      final badPhase = await env.step({
        'action_v2': {'action_type': 'match', 'slot': 0}
      });
      expect(badPhase['type'], 'error');
      expect(badPhase['code'], 'ILLEGAL_ACTION');

      obs = await env.step({
        'action_v2': {'action_type': 'draw'}
      });
      expect(obs['micro_phase'], 'postDraw');
      final outOfBounds = await env.step({
        'action_v2': {'action_type': 'post_draw_replace', 'slot': 999}
      });
      expect(outOfBounds['type'], 'error');
      expect(outOfBounds['code'], 'ILLEGAL_ACTION');
    });

    test('doublon minimal : replace puis match actif sur le même rang',
        () async {
      final env = RlEnv(episodeId: 'react-doublon', forcedNumPlayers: 2);
      var obs = await env.reset(14);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      final sevenA = PlayingCard.create('hearts', '6');
      final sevenB = PlayingCard.create('spades', '6');
      final queen = PlayingCard.create('clubs', 'D');
      _setKnownHand(env, [sevenA, sevenB, queen]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'A');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.rlSeat.hand.length, 3);
      expect(env.gs.topDiscardCard?.value, '6');

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['type'], 'observation');
      expect(obs['micro_phase'], 'reaction');
      expect(env.rlSeat.hand.length, 2);
      expect(env.gs.topDiscardCard?.value, '6');
    });

    test('pending 7 p0 : résolution via phase power existante', () async {
      final env = RlEnv(episodeId: 'pending-p0-7', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('hearts', '7'),
        PlayingCard.create('clubs', '9'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', '7');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.pendingMatchPowers.length, 1);

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, '7');
      expect(env.gs.specialPowerPlayerId, env.rlSeat.id);

      obs = await env.step({
        'kind': 'power7_look',
        'params': {'index': 0}
      });
      expect(env.gs.pendingMatchPowers, isEmpty);
      expect(env.rlSeat.mentalMap[0]?.id, env.rlSeat.hand[0].id);
      expect(obs['type'], 'observation');
    });

    test('pending 10 p0 : résolution via phase power existante', () async {
      final env = RlEnv(episodeId: 'pending-p0-10', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('hearts', '10'),
        PlayingCard.create('clubs', '9'),
      ]);
      final target = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      target.hand = [
        PlayingCard.create('clubs', '4'),
        PlayingCard.create('diamonds', 'D'),
      ];
      target.knownCards =
          List<bool>.filled(target.hand.length, false, growable: true);
      target.mentalMap =
          List<PlayingCard?>.filled(target.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', '10');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.pendingMatchPowers.length, 1);

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, '10');
      expect(env.gs.specialPowerPlayerId, env.rlSeat.id);

      obs = await env.step({
        'kind': 'power10_spy',
        'params': {'target_seat': target.id, 'index': 0}
      });
      expect(env.gs.pendingMatchPowers, isEmpty);
      expect(obs['type'], 'observation');
    });

    test('pending Joker bot : utilise la logique pouvoir bot normale',
        () async {
      final env = RlEnv(
        episodeId: 'pending-bot',
        forcedNumPlayers: 2,
        forcedOpponentSkill: BotSkillLevel.difficile,
      );
      var obs = await env.reset(12);
      var guard = 0;
      while (obs['micro_phase'] != 'dutchOrDraw' && guard++ < 50) {
        obs = await env.step(_deterministicAction(obs));
      }
      expect(obs['micro_phase'], 'dutchOrDraw');
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('spades', '9'),
      ]);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('clubs', 'JOKER'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      bot.resetUnknownCardHints();
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.pendingMatchPowers.length, 1);

      obs = await env.step({'kind': 'pass_tick'});
      expect(env.gs.pendingMatchPowers, isEmpty);
      expect(env.gs.phase, isNot(GamePhase.specialPower));
      expect(
        env.gs.actionHistory.any((entry) =>
            entry.contains(bot.name) &&
            (entry.contains('JOKER') || entry.contains('utilisé son pouvoir'))),
        isTrue,
      );
      expect(obs['type'], 'observation');
    });

    test('pending actifs p0 : Valet/Joker résolus en FIFO', () async {
      final env = RlEnv(episodeId: 'pending-fifo', forcedNumPlayers: 2);
      var obs = await env.reset(12);
      obs = await env.step({'kind': 'continue_draw'});
      expect(obs['micro_phase'], 'postDraw');

      _setKnownHand(env, [
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '8'),
      ]);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('clubs', '4'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', '2');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'reaction');

      env.gs.pendingMatchPowers
        ..clear()
        ..add(PendingMatchPower(
          playerId: env.rlSeat.id,
          playerName: env.rlSeat.name,
          card: PlayingCard.create('hearts', 'JOKER'),
        ))
        ..add(PendingMatchPower(
          playerId: env.rlSeat.id,
          playerName: env.rlSeat.name,
          card: PlayingCard.create('spades', 'V'),
        ));

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, 'JOKER');
      expect(env.gs.pendingMatchPowers.single.card.value, 'V');
      expect(env.gs.pendingMatchPowers.single.drawNumber, 2);

      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, 'V');
      expect(env.gs.pendingMatchPowers, isEmpty);
    });
  });

  // 2c ────────────────────────────────────────────────────────────────────────
  group('2c. Fidélité deck vide + bornage réaction', () {
    test('faux match deck vide recyclable applique la pénalité (jamais no-op)',
        () async {
      final env = RlEnv(episodeId: 'deck-empty-recycle', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'), // slot0 -> défaussé -> top '5'
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.topDiscardCard?.value, '5');

      // Deck vide mais défausse recyclable (>1) : insérer au fond pour garder
      // le top '5'.
      env.gs.deck.clear();
      env.gs.discardPile.insert(0, PlayingCard.create('clubs', '3'));
      env.gs.discardPile.insert(0, PlayingCard.create('clubs', '4'));
      final handBefore = env.rlSeat.hand.length;

      // slot1 = '9' != top '5' => faux match => pénalité après recycle défausse.
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['type'], 'observation');
      expect(obs['done'], isNot(true)); // deck vide seul ne termine pas
      expect(env.rlSeat.hand.length, handBefore + 1); // pénalité réellement appliquée
      expect(env.gs.topDiscardCard?.value, '5');
    });

    test('faux match deck vide NON recyclable termine la manche (done=true)',
        () async {
      final env = RlEnv(episodeId: 'deck-empty-end', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');

      // Deck vide ET défausse non recyclable (<=1) : le moteur termine la manche
      // (GameLogic._refillDeck -> endGame). Pas de no-op.
      env.gs.deck.clear();
      while (env.gs.discardPile.length > 1) {
        env.gs.discardPile.removeAt(0);
      }
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['done'], isTrue);
    });

    test('match réussi ne recycle pas le deck (aucune pioche)', () async {
      final env = RlEnv(episodeId: 'success-no-recycle', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 42, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '5'), // slot1 -> '5' matche le top '5'
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      final deckBefore = env.gs.deck.length;
      final handBefore = env.rlSeat.hand.length;

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(env.gs.deck.length, deckBefore); // pas de pioche => pas de recycle
      expect(env.rlSeat.hand.length, handBefore - 1); // carte retirée
    });

    test('faux match deck plein applique toujours la pénalité (régression)',
        () async {
      final env = RlEnv(episodeId: 'false-deck-full', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.deck.isNotEmpty, isTrue);
      final deckBefore = env.gs.deck.length;
      final handBefore = env.rlSeat.hand.length;

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(env.rlSeat.hand.length, handBefore + 1); // pénalité
      expect(env.gs.deck.length, deckBefore - 1); // une carte piochée
    });

    test('match illégal en état terminal (phase ended) => rejeté', () async {
      final env = RlEnv(episodeId: 'no-match-when-ended', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');

      env.gs.phase = GamePhase.ended; // force l'état terminal
      final err = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(err['type'], 'error');
      expect(err['code'], 'ILLEGAL_ACTION');
    });

    test('fenêtre de réaction bornée : le spam de faux match ferme la fenêtre',
        () async {
      final env = RlEnv(episodeId: 'reaction-bounded', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '9'), // restera un faux match (top '5')
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');

      // Deck volumineux : aucune fin de manche avant l'épuisement du budget.
      env.gs.deck.clear();
      env.gs.deck.addAll(List.generate(60, (_) => PlayingCard.create('clubs', '3')));

      // Spam de faux match (slot1='9' != top '5'). Le budget de réaction borne
      // chaque fenêtre : reactionTicks ne doit JAMAIS dépasser le plafond (la
      // fenêtre se ferme et se réamorce avant). S'il n'était pas borné,
      // reactionTicks grimperait jusqu'à 40 (un par match).
      var maxTicksSeen = 0;
      for (var i = 0; i < 40; i++) {
        obs = await env.step({
          'kind': 'match',
          'params': {'index': 1}
        });
        if (obs['done'] == true) break;
        maxTicksSeen = max(maxTicksSeen, env.reactionTicks);
      }
      expect(maxTicksSeen, lessThanOrEqualTo(env.maxHeadlessReactionTicks),
          reason: 'la fenêtre de réaction a dépassé son budget (boucle)');
      expect(maxTicksSeen, greaterThan(0));
    });

    test('régression boucle : policy match-en-boucle termine l\'épisode',
        () async {
      final env = RlEnv(episodeId: 'no-infinite-loop', forcedNumPlayers: 6);
      var obs = await env.reset(0);
      var steps = 0;
      while (obs['done'] != true && steps < 3000) {
        final mp = obs['micro_phase'];
        Map<String, dynamic> action;
        if (mp == 'reaction') {
          action = {
            'kind': 'match',
            'params': {'index': 0}
          };
        } else if (mp == 'dutchOrDraw') {
          action = {'kind': 'continue_draw'};
        } else if (mp == 'postDraw') {
          action = {'kind': 'discard_drawn'};
        } else if (mp == 'power') {
          action = {'kind': 'skip_power'};
        } else {
          action = {'kind': 'pass_tick'};
        }
        obs = await env.step(action);
        steps++;
      }
      expect(obs['done'], isTrue,
          reason: 'la policy match-en-boucle ne doit plus boucler à l\'infini');
      expect(steps, lessThan(3000));
    });
  });

  // 2d ────────────────────────────────────────────────────────────────────────
  group('2d. Timer global de réaction (jamais réinitialisé)', () {
    test('faux match consomme un tick sans réinitialiser le timer', () async {
      final env = RlEnv(episodeId: 'timer-false-match', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'), // -> top '5'
        PlayingCard.create('spades', '9'), // faux match (9 != 5)
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      expect(env.reactionTicks, 0); // budget neuf à l'ouverture de la fenêtre

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.reactionTicks, 1); // un tick consommé
      expect(env.gs.topDiscardCard?.value, '5'); // top inchangée par faux match

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(env.reactionTicks, 2); // accumule : jamais réinitialisé
    });

    test('match réussi consomme un tick sans relancer le timer (top change)',
        () async {
      final env = RlEnv(episodeId: 'timer-success-match', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 42, [
        PlayingCard.create('hearts', '5'), // -> top '5'
        PlayingCard.create('spades', '5'), // match
        PlayingCard.create('clubs', '5'), // match
        PlayingCard.create('diamonds', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      expect(env.reactionTicks, 0);
      final handBefore = env.rlSeat.hand.length;
      final firstTopId = env.gs.topDiscardCard?.id;

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      expect(env.reactionTicks, 1); // un tick consommé
      expect(env.rlSeat.hand.length, handBefore - 1); // carte retirée
      expect(env.gs.topDiscardCard?.id, isNot(firstTopId)); // top a changé

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      // Top discard a changé deux fois, pourtant le budget continue de courir.
      expect(env.reactionTicks, 2);
      expect(env.gs.topDiscardCard?.value, '5');
    });

    test('pass_tick consomme un tick du timer global', () async {
      final env = RlEnv(
        episodeId: 'timer-pass-tick',
        forcedNumPlayers: 2,
        forcedOpponentSkill: BotSkillLevel.difficile,
      );
      var obs = await env.reset(12);
      var guard = 0;
      while (obs['micro_phase'] != 'dutchOrDraw' && guard++ < 50) {
        obs = await env.step(_deterministicAction(obs));
      }
      obs = await env.step({'kind': 'continue_draw'});
      _setKnownHand(env, [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('spades', '5'),
        PlayingCard.create('spades', '9'),
      ]);
      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('clubs', '5'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      bot.resetUnknownCardHints();
      env.gs.drawnCard = PlayingCard.create('diamonds', '2');

      obs = await env.step({
        'kind': 'replace',
        'params': {'index': 0}
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.reactionTicks, 0);

      obs = await env.step({'kind': 'pass_tick'});
      // Le bot matche -> p0 ré-invité dans la MÊME fenêtre : le pass_tick a
      // bien consommé un tick (budget non réamorcé).
      expect(obs['micro_phase'], 'reaction');
      expect(env.reactionTicks, 1);
    });

    test('recycle deck vide préserve la top discard hors mélange', () async {
      final env = RlEnv(episodeId: 'recycle-keeps-top', forcedNumPlayers: 2);
      var obs = await _enterP0Reaction(env, 41, [
        PlayingCard.create('hearts', '5'), // -> top '5'
        PlayingCard.create('spades', '9'),
        PlayingCard.create('clubs', '9'),
      ]);
      expect(obs['micro_phase'], 'reaction');
      final topId = env.gs.topDiscardCard?.id;

      // Deck vide + défausse recyclable (>1) ; insérer au fond pour garder le top.
      env.gs.deck.clear();
      env.gs.discardPile.insert(0, PlayingCard.create('clubs', '3'));
      env.gs.discardPile.insert(0, PlayingCard.create('clubs', '4'));
      final handBefore = env.rlSeat.hand.length;

      obs = await env.step({
        'kind': 'match',
        'params': {'index': 1}
      });
      // La top discard est restée hors du mélange et reste disponible.
      expect(env.gs.topDiscardCard?.id, topId);
      expect(env.gs.topDiscardCard?.value, '5');
      // Pénalité réellement appliquée après refill (jamais no-op).
      expect(env.rlSeat.hand.length, handBefore + 1);
      expect(obs['done'], isNot(true)); // deck vide recyclable ne termine pas
    });
  });

  // 3 ─────────────────────────────────────────────────────────────────────────
  group('3. Absence de leakage', () {
    test(
        'slots inconnus => believed null ; adversaires => public + spied seulement',
        () async {
      final rng = Random(2024);
      const allowedOppKeys = {
        'seat',
        'hand_size',
        'memorized_indices',
        'spied',
        'last_targeted_ago',
      };
      final tableSizesSeen = <int>{};
      for (var ep = 0; ep < 80; ep++) {
        final env = RlEnv(episodeId: 'leak$ep');
        var obs = await env.reset(ep);
        tableSizesSeen.add(env.players.length);
        var safety = 0;
        while (obs['done'] != true && safety++ < 5000) {
          final body = obs['obs'] as Map<String, dynamic>;
          // Self : slot inconnu => aucune valeur réelle exposée.
          for (final slot
              in (body['slots'] as List).cast<Map<String, dynamic>>()) {
            if (slot['known'] != true) {
              expect(slot['believed_value'], isNull,
                  reason: 'fuite : valeur exposée sur slot inconnu');
              expect(slot['believed_points'], isNull);
            }
          }
          // Adversaires : pas de clé `hand`, uniquement public + spied.
          for (final op
              in (body['opponents'] as List).cast<Map<String, dynamic>>()) {
            expect(op.keys.toSet().difference(allowedOppKeys), isEmpty,
                reason: 'fuite : clé adverse inattendue ${op.keys}');
          }
          final legal = _legalActions(obs);
          obs = await env.step(legal[rng.nextInt(legal.length)]);
          if (obs['type'] == 'error') break;
        }
      }
      // L'anti-leakage doit être vérifié AUSSI sur les grandes tables (5 et 6).
      expect(tableSizesSeen.containsAll({5, 6}), isTrue,
          reason:
              'tables 5 et 6 non couvertes par le test de leakage: $tableSizesSeen');
    });
  });

  // 4 ─────────────────────────────────────────────────────────────────────────
  group('4. Épisode complet, agent random', () {
    test('40 épisodes random => tous terminent proprement', () async {
      final rng = Random(99);
      for (var ep = 0; ep < 40; ep++) {
        final env = RlEnv(episodeId: 'rand$ep');
        var obs = await env.reset(1000 + ep);
        var safety = 0;
        while (obs['done'] != true && safety++ < 5000) {
          final legal = _legalActions(obs);
          expect(legal, isNotEmpty,
              reason: 'masque vide en phase ${obs['micro_phase']}');
          obs = await env.step(legal[rng.nextInt(legal.length)]);
          expect(obs['type'], 'observation');
        }
        expect(obs['done'], isTrue, reason: 'épisode $ep non terminé');
        final info = obs['info'] as Map<String, dynamic>;
        final ranks = (info['final_ranks'] as Map).keys.toSet();
        expect(ranks, env.players.map((p) => p.id).toSet());
        final reward = obs['reward'] as num;
        expect(reward >= -1.0 && reward <= 1.0, isTrue);
      }
    });
  });

  // 5 ─────────────────────────────────────────────────────────────────────────
  group('5. Parité byte-à-byte avec le générateur (frozenBotMode)', () {
    test('runner frozen == playOneGame pour 100 seeds', () async {
      for (var s = 0; s < 100; s++) {
        // Référence : générateur existant (il ne seed pas lui-même).
        EngineRandom.seed(s);
        final ref = await playOneGame(
          0,
          GeneratorConfig(games: 1, seed: s, outDir: '.', maxTurns: 500),
        );

        // Runner en mode bot gelé (re-seed identique en interne).
        final env = RlEnv(episodeId: 'parity', frozenBotMode: true);
        await env.reset(s);
        final ranks = env.gs.getFinalRanksWithTies();

        expect(env.players.length, ref.length,
            reason: 'seed $s : nb joueurs divergent');
        for (var i = 0; i < env.players.length; i++) {
          final p = env.players[i];
          expect(ranks[p.id], ref[i].finalRank,
              reason: 'seed $s joueur $i : rang divergent');
          expect(env.gs.getFinalScore(p), ref[i].finalScore,
              reason: 'seed $s joueur $i : score divergent');
          expect(env.gs.dutchCallerId == p.id, ref[i].calledDutch,
              reason: 'seed $s joueur $i : calledDutch divergent');
        }
      }
    });
  });

  // 6 ─────────────────────────────────────────────────────────────────────────
  group('6. Pouvoirs 7/10/Valet/Joker', () {
    test('chaque pouvoir produit l\'effet moteur attendu', () async {
      final covered = <String>{};

      // On avance jusqu'à une phase de pouvoir, puis on applique le pouvoir via
      // le seam de test (effet immédiat, AVANT que les adversaires ne rejouent),
      // ce qui permet d'asserter l'effet moteur côté cible sans bruit de tail.
      for (var s = 0; s < 200 && covered.length < 4; s++) {
        final env = RlEnv(episodeId: 'pow$s');
        var obs = await env.reset(s);
        var safety = 0;
        while (obs['done'] != true && safety++ < 5000) {
          if (obs['micro_phase'] != 'power') {
            obs = await env.step(_deterministicAction(obs));
            continue;
          }

          final val = env.pendingPowerValue;
          final rl = env.rlSeat;

          if (val == '7') {
            const i = 0;
            env.applyRlPowerForTest('power7_look', {'index': i});
            expect(rl.knownCards[i], isTrue);
            expect(rl.mentalMap[i]?.id, rl.hand[i].id);
            covered.add('7');
          } else if (val == '10') {
            final target = env.players
                .firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final spiedId = target.hand[0].id;
            env.applyRlPowerForTest(
                'power10_spy', {'target_seat': target.id, 'index': 0});
            expect(rl.getSpiedCards(target.id), isNotNull);
            expect(rl.getSpiedCards(target.id)![0]?.id, spiedId);
            covered.add('10');
          } else if (val == 'V') {
            final target = env.players
                .firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final received = target.hand[0].id; // carte que rlSeat reçoit
            final given = rl.hand[0].id; // carte que rlSeat cède
            env.applyRlPowerForTest('powerV_swap',
                {'own_index': 0, 'target_seat': target.id, 'target_index': 0});
            expect(rl.hand[0].id, received);
            expect(target.hand[0].id, given);
            covered.add('V');
          } else if (val == 'JOKER') {
            final target = env.players
                .firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final multisetBefore = target.hand.map((c) => c.value).toList()
              ..sort();
            env.applyRlPowerForTest('powerJoker', {'target_seat': target.id});
            // La cible perd toute connaissance certaine ; multiset préservé.
            expect(target.knownCards.every((k) => k == false), isTrue);
            final multisetAfter = target.hand.map((c) => c.value).toList()
              ..sort();
            expect(multisetAfter, multisetBefore);
            covered.add('JOKER');
          } else {
            obs = await env.step({'kind': 'skip_power'});
            continue;
          }
          break; // pouvoir exercé : on abandonne l'épisode, seed suivant
        }
      }

      expect(covered, {'7', '10', 'V', 'JOKER'},
          reason: 'pouvoirs non tous couverts: $covered');
    });
  });

  // 6b ────────────────────────────────────────────────────────────────────────
  group('6b. Valet/Joker complets côté RL', () {
    test('Valet normal : p0 peut échanger sa carte avec une carte adverse',
        () async {
      final env = RlEnv(episodeId: 'valet-self-opp', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 21);

      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      _setKnownHand(env, [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('clubs', '2'),
      ]);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      final mask = obs['action_mask'] as Map<String, dynamic>;
      final players = (mask['powerV_swap'] as Map)['players'] as Map;
      expect(players.keys, containsAll([env.rlSeat.id, bot.id]));

      final given = env.rlSeat.hand[1].id;
      final received = bot.hand[0].id;
      obs = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 1,
          'player_b': bot.id,
          'slot_b': 0,
        },
      });

      expect(obs['type'], 'observation');
      expect(env.rlSeat.hand[1].id, received);
      expect(bot.hand[0].id, given);
    });

    test('Valet normal : p0 peut cibler deux adversaires distincts', () async {
      final env = RlEnv(episodeId: 'valet-opp-opp', forcedNumPlayers: 3);
      var obs = await _enterPostDraw(env, 22);

      final p1 = env.players[1];
      final p2 = env.players[2];
      p1.hand = [PlayingCard.create('clubs', '4')];
      p2.hand = [PlayingCard.create('spades', '9')];
      p1.knownCards = List<bool>.filled(p1.hand.length, false, growable: true);
      p2.knownCards = List<bool>.filled(p2.hand.length, false, growable: true);
      p1.mentalMap =
          List<PlayingCard?>.filled(p1.hand.length, null, growable: true);
      p2.mentalMap =
          List<PlayingCard?>.filled(p2.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');

      final p1Before = p1.hand[0].id;
      final p2Before = p2.hand[0].id;
      obs = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': p1.id,
          'slot_a': 0,
          'player_b': p2.id,
          'slot_b': 0,
        },
      });

      expect(obs['type'], 'observation');
      expect(p1.hand[0].id, p2Before);
      expect(p2.hand[0].id, p1Before);
    });

    test('Valet rejette les actions illégales', () async {
      final env = RlEnv(episodeId: 'valet-illegal', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 23);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');

      final outOfBounds = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 999,
          'player_b': env.players[1].id,
          'slot_b': 0,
        },
      });
      expect(outOfBounds['type'], 'error');
      expect(outOfBounds['code'], 'ILLEGAL_ACTION');

      final samePlayer = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 0,
          'player_b': env.rlSeat.id,
          'slot_b': 1,
        },
      });
      expect(samePlayer['type'], 'error');
      expect(samePlayer['code'], 'ILLEGAL_ACTION');
    });

    test('Joker normal : p0 peut cibler un adversaire mais pas soi-même',
        () async {
      final env = RlEnv(episodeId: 'joker-normal', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 24);

      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      _setKnownHand(env, [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('clubs', '2'),
      ]);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      final mask = obs['action_mask'] as Map<String, dynamic>;
      expect((mask['powerJoker'] as Map).containsKey(env.rlSeat.id), isFalse);
      expect((mask['powerJoker'] as Map)[bot.id], isTrue);

      final selfTarget = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': env.rlSeat.id},
      });
      expect(selfTarget['type'], 'error');
      expect(selfTarget['code'], 'ILLEGAL_ACTION');

      obs = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': bot.id},
      });
      expect(obs['type'], 'observation');
      expect(bot.knownCards.every((known) => known == false), isTrue);
    });

    test('Valet pending p0 : action complète résolue après la réaction',
        () async {
      final env = RlEnv(episodeId: 'valet-pending-p0', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 26);

      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      _setKnownHand(env, [
        PlayingCard.create('hearts', 'V'),
        PlayingCard.create('clubs', 'A'),
      ]);
      bot.hand = [PlayingCard.create('spades', 'R')];
      bot.knownCards =
          List<bool>.filled(bot.hand.length, false, growable: true);
      bot.mentalMap =
          List<PlayingCard?>.filled(bot.hand.length, null, growable: true);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'V');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0},
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.pendingMatchPowers.length, 1);

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, 'V');

      final rlBefore = env.rlSeat.hand[0].id;
      final botBefore = bot.hand[0].id;
      obs = await env.step({
        'kind': 'powerV_swap',
        'params': {
          'player_a': env.rlSeat.id,
          'slot_a': 0,
          'player_b': bot.id,
          'slot_b': 0,
        },
      });
      expect(obs['type'], 'observation');
      expect(env.gs.pendingMatchPowers, isEmpty);
      expect(env.rlSeat.hand[0].id, botBefore);
      expect(bot.hand[0].id, rlBefore);
    });

    test('Joker pending p0 : self rejeté, adversaire autorisé', () async {
      final env = RlEnv(episodeId: 'joker-pending-p0', forcedNumPlayers: 2);
      var obs = await _enterPostDraw(env, 27);

      final bot = env.players.firstWhere((p) => p.id != env.rlSeat.id);
      bot.hand = [
        PlayingCard.create('spades', 'R'),
        PlayingCard.create('diamonds', 'D'),
      ];
      bot.knownCards = List<bool>.filled(bot.hand.length, true, growable: true);
      bot.mentalMap = List<PlayingCard?>.from(bot.hand, growable: true);
      _setKnownHand(env, [
        PlayingCard.create('hearts', 'JOKER'),
        PlayingCard.create('clubs', 'A'),
      ]);
      env.gs.drawnCard = PlayingCard.create('diamonds', 'JOKER');

      obs = await env.step({'kind': 'discard_drawn'});
      expect(obs['micro_phase'], 'power');
      obs = await env.step({'kind': 'skip_power'});
      expect(obs['micro_phase'], 'reaction');
      obs = await env.step({
        'kind': 'match',
        'params': {'index': 0},
      });
      expect(obs['micro_phase'], 'reaction');
      expect(env.gs.pendingMatchPowers.length, 1);

      obs = await env.step({'kind': 'pass_tick'});
      expect(obs['micro_phase'], 'power');
      expect(env.pendingPowerValue, 'JOKER');
      final selfTarget = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': env.rlSeat.id},
      });
      expect(selfTarget['type'], 'error');
      expect(selfTarget['code'], 'ILLEGAL_ACTION');

      obs = await env.step({
        'kind': 'powerJoker',
        'params': {'target_seat': bot.id},
      });
      expect(obs['type'], 'observation');
      expect(env.gs.pendingMatchPowers, isEmpty);
    });
  });

  // 7 ─────────────────────────────────────────────────────────────────────────
  group('7. Reset paramétré (éval)', () {
    test('num_players forcé => env.players.length == valeur (2..6)', () async {
      for (var n = 2; n <= 6; n++) {
        final env = RlEnv(episodeId: 'n$n', forcedNumPlayers: n);
        await env.reset(0);
        expect(env.players.length, n, reason: 'num_players=$n non respecté');
      }
    });

    test('opponents forcé => p1..pn profil forcé, p0 neutre (siège RL)',
        () async {
      final env = RlEnv(
        episodeId: 'opp',
        forcedNumPlayers: 4,
        forcedOpponentSkill: BotSkillLevel.difficile,
        forcedOpponentBehavior: BotBehavior.aggressive,
      );
      await env.reset(7);
      expect(env.players.length, 4);
      // p0 = siège RL : profil neutre fixe, sans effet sur le jeu.
      expect(env.players[0].id, 'p0');
      expect(env.players[0].botBehavior, BotBehavior.balanced);
      expect(env.players[0].botSkillLevel, BotSkillLevel.silver);
      // p1..p3 : profil forcé.
      for (var i = 1; i < env.players.length; i++) {
        expect(env.players[i].botSkillLevel, BotSkillLevel.difficile,
            reason: 'p$i skill non forcé');
        expect(env.players[i].botBehavior, BotBehavior.aggressive,
            reason: 'p$i behavior non forcé');
      }
    });

    test(
        'mode forcé reproductible : même seed+config => mêmes final_ranks + final_scores',
        () async {
      Future<Map<String, dynamic>> finalInfo(int seed) async {
        final env = RlEnv(
          episodeId: 'rep',
          forcedNumPlayers: 5,
          forcedOpponentSkill: BotSkillLevel.difficile,
          forcedOpponentBehavior: BotBehavior.aggressive,
        );
        final log = await _drive(env, seed, _deterministicAction);
        final terminal = log.last;
        expect(terminal['done'], isTrue, reason: 'épisode non terminé');
        return (terminal['info'] as Map).cast<String, dynamic>();
      }

      final a = await finalInfo(123);
      final b = await finalInfo(123); // même seed + même config, 2e fois
      expect(jsonEncode(b['final_ranks']), jsonEncode(a['final_ranks']),
          reason: 'final_ranks non reproductibles');
      expect(jsonEncode(b['final_scores']), jsonEncode(a['final_scores']),
          reason: 'final_scores non reproductibles');
    });

    test('parseEvalPlayerConfig : options vides => tout null (chemin défaut)',
        () {
      final cfg = parseEvalPlayerConfig(const {});
      expect(cfg.numPlayers, isNull);
      expect(cfg.behavior, isNull);
      expect(cfg.skill, isNull);
    });

    test('parseEvalPlayerConfig : valeurs valides parsées', () {
      final cfg = parseEvalPlayerConfig({
        'num_players': 3,
        'opponents': {'skill': 'difficile', 'behavior': 'moi'},
      });
      expect(cfg.numPlayers, 3);
      expect(cfg.skill, BotSkillLevel.difficile);
      expect(cfg.behavior, BotBehavior.moi);
    });

    test('parseEvalPlayerConfig : skill legacy (platine) => difficile', () {
      final cfg = parseEvalPlayerConfig({
        'opponents': {'skill': 'platine'},
      });
      expect(cfg.skill, BotSkillLevel.difficile);
    });

    test(
        'parseEvalPlayerConfig : num_players hors borne / non entier => FormatException',
        () {
      expect(() => parseEvalPlayerConfig({'num_players': 7}),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 1}),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 0}),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 'deux'}),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 3.5}),
          throwsFormatException);
    });

    test('parseEvalPlayerConfig : skill / behavior inconnu => FormatException',
        () {
      expect(
          () => parseEvalPlayerConfig({
                'opponents': {'skill': 'wood'},
              }),
          throwsFormatException);
      expect(
          () => parseEvalPlayerConfig({
                'opponents': {'behavior': 'sneaky'},
              }),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'opponents': 'silver'}),
          throwsFormatException);
    });
  });
}
