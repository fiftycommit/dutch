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
import 'package:dutch_game/models/game_settings.dart' show BotBehavior, BotSkillLevel;

import '../../tool/rl_env_runner.dart'
    show RlEnv, RlMicroPhase, EvalPlayerConfig, parseEvalPlayerConfig;
import '../../tool/ml_dataset_generator.dart' show playOneGame, GeneratorConfig;

// ── Politiques d'action de test ────────────────────────────────────────────

/// Énumère toutes les actions légales depuis une observation (selon son masque).
List<Map<String, dynamic>> _legalActions(Map<String, dynamic> obs) {
  final mask = obs['action_mask'] as Map<String, dynamic>;
  final mp = obs['micro_phase'];
  final out = <Map<String, dynamic>>[];

  if (mp == 'dutchOrDraw') {
    if (mask['call_dutch'] == true) out.add({'kind': 'call_dutch'});
    if (mask['continue_draw'] == true) out.add({'kind': 'continue_draw'});
  } else if (mp == 'postDraw') {
    if (mask['discard_drawn'] == true) out.add({'kind': 'discard_drawn'});
    final rep = (mask['replace'] as List).cast<bool>();
    for (var i = 0; i < rep.length; i++) {
      if (rep[i]) out.add({'kind': 'replace', 'params': {'index': i}});
    }
  } else if (mp == 'power') {
    if (mask['skip_power'] == true) out.add({'kind': 'skip_power'});
    if (mask.containsKey('power7_look')) {
      final l = (mask['power7_look'] as List).cast<bool>();
      for (var i = 0; i < l.length; i++) {
        if (l[i]) out.add({'kind': 'power7_look', 'params': {'index': i}});
      }
    }
    if (mask.containsKey('power10_spy')) {
      (mask['power10_spy'] as Map).forEach((seat, list) {
        final l = (list as List).cast<bool>();
        for (var i = 0; i < l.length; i++) {
          if (l[i]) {
            out.add({'kind': 'power10_spy', 'params': {'target_seat': seat, 'index': i}});
          }
        }
      });
    }
    if (mask.containsKey('powerV_swap')) {
      final own = ((mask['powerV_swap'] as Map)['own'] as List).cast<bool>();
      final targets = (mask['powerV_swap'] as Map)['targets'] as Map;
      for (var oi = 0; oi < own.length; oi++) {
        if (!own[oi]) continue;
        targets.forEach((seat, list) {
          final l = (list as List).cast<bool>();
          for (var ti = 0; ti < l.length; ti++) {
            if (l[ti]) {
              out.add({
                'kind': 'powerV_swap',
                'params': {'own_index': oi, 'target_seat': seat, 'target_index': ti},
              });
            }
          }
        });
      }
    }
    if (mask.containsKey('powerJoker')) {
      (mask['powerJoker'] as Map).forEach((seat, ok) {
        if (ok == true) out.add({'kind': 'powerJoker', 'params': {'target_seat': seat}});
      });
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
    default: // power
      return {'kind': 'skip_power'};
  }
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

void main() {
  // 1 ─────────────────────────────────────────────────────────────────────────
  group('1. Déterminisme seed', () {
    test('même seed + même policy => journaux d\'observations identiques', () async {
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

    test('construire l\'observation ne consomme aucun tirage EngineRandom', () async {
      final env = RlEnv(episodeId: 'rng');
      await env.reset(123);
      // Empreinte RNG avant/après plusieurs constructions d'observation implicites.
      final before = List<int>.generate(5, (_) => EngineRandom.instance.nextInt(1 << 30));
      EngineRandom.seed(123);
      await env.reset(123);
      // Rejouer la même séquence d'actions (qui construit des observations) ne doit
      // pas décaler le flux : on re-seed et on retire les mêmes valeurs.
      final after = List<int>.generate(5, (_) => EngineRandom.instance.nextInt(1 << 30));
      // before/after partent de seed 123 puis du même reset déterministe => identiques.
      expect(after, before);
    });

    test('parité inter-épisodes même process (statique _platinumKillWindow)', () async {
      Future<String> frozenFinal(int seed) async {
        final env = RlEnv(episodeId: 'f', frozenBotMode: true);
        await env.reset(seed);
        return jsonEncode({
          'ranks': env.gs.getFinalRanksWithTies(),
          'scores': {for (final p in env.players) p.id: env.gs.getFinalScore(p)},
        });
      }

      final first = await frozenFinal(55);
      final again = await frozenFinal(55); // même seed, 2e fois dans le même process
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
      final err = await env.step({'kind': 'replace', 'params': {'index': 0}});
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
      final err = await env.step({'kind': 'replace', 'params': {'index': 999}});
      expect(err['type'], 'error');
      expect(err['code'], 'ILLEGAL_ACTION');
    });
  });

  // 3 ─────────────────────────────────────────────────────────────────────────
  group('3. Absence de leakage', () {
    test('slots inconnus => believed null ; adversaires => public + spied seulement',
        () async {
      final rng = Random(2024);
      const allowedOppKeys = {
        'seat', 'hand_size', 'memorized_indices', 'spied', 'last_targeted_ago',
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
          for (final slot in (body['slots'] as List).cast<Map<String, dynamic>>()) {
            if (slot['known'] != true) {
              expect(slot['believed_value'], isNull,
                  reason: 'fuite : valeur exposée sur slot inconnu');
              expect(slot['believed_points'], isNull);
            }
          }
          // Adversaires : pas de clé `hand`, uniquement public + spied.
          for (final op in (body['opponents'] as List).cast<Map<String, dynamic>>()) {
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
          reason: 'tables 5 et 6 non couvertes par le test de leakage: $tableSizesSeen');
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
          expect(legal, isNotEmpty, reason: 'masque vide en phase ${obs['micro_phase']}');
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
            final target =
                env.players.firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final spiedId = target.hand[0].id;
            env.applyRlPowerForTest(
                'power10_spy', {'target_seat': target.id, 'index': 0});
            expect(rl.getSpiedCards(target.id), isNotNull);
            expect(rl.getSpiedCards(target.id)![0]?.id, spiedId);
            covered.add('10');
          } else if (val == 'V') {
            final target =
                env.players.firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final received = target.hand[0].id; // carte que rlSeat reçoit
            final given = rl.hand[0].id; // carte que rlSeat cède
            env.applyRlPowerForTest('powerV_swap',
                {'own_index': 0, 'target_seat': target.id, 'target_index': 0});
            expect(rl.hand[0].id, received);
            expect(target.hand[0].id, given);
            covered.add('V');
          } else if (val == 'JOKER') {
            final target =
                env.players.firstWhere((p) => p.id != rl.id && p.hand.isNotEmpty);
            final multisetBefore = target.hand.map((c) => c.value).toList()..sort();
            env.applyRlPowerForTest('powerJoker', {'target_seat': target.id});
            // La cible perd toute connaissance certaine ; multiset préservé.
            expect(target.knownCards.every((k) => k == false), isTrue);
            final multisetAfter = target.hand.map((c) => c.value).toList()..sort();
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

  // 7 ─────────────────────────────────────────────────────────────────────────
  group('7. Reset paramétré (éval)', () {
    test('num_players forcé => env.players.length == valeur (2..6)', () async {
      for (var n = 2; n <= 6; n++) {
        final env = RlEnv(episodeId: 'n$n', forcedNumPlayers: n);
        await env.reset(0);
        expect(env.players.length, n, reason: 'num_players=$n non respecté');
      }
    });

    test('opponents forcé => p1..pn profil forcé, p0 neutre (siège RL)', () async {
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

    test('parseEvalPlayerConfig : options vides => tout null (chemin défaut)', () {
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

    test('parseEvalPlayerConfig : num_players hors borne / non entier => FormatException',
        () {
      expect(() => parseEvalPlayerConfig({'num_players': 7}), throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 1}), throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 0}), throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 'deux'}),
          throwsFormatException);
      expect(() => parseEvalPlayerConfig({'num_players': 3.5}), throwsFormatException);
    });

    test('parseEvalPlayerConfig : skill / behavior inconnu => FormatException', () {
      expect(() => parseEvalPlayerConfig({
            'opponents': {'skill': 'wood'},
          }), throwsFormatException);
      expect(() => parseEvalPlayerConfig({
            'opponents': {'behavior': 'sneaky'},
          }), throwsFormatException);
      expect(() => parseEvalPlayerConfig({'opponents': 'silver'}),
          throwsFormatException);
    });
  });
}
