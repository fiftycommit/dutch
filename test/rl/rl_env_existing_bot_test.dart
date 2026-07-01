// Tests de la policy de collecte `existing_bot` (capture-par-exécution) du runner
// RL. Vérifient : forçage difficile de TOUS les joueurs (p0 inclus), pilotage
// `bot_auto` complet, action réellement appliquée toujours légale, couverture des
// types d'action, et parsing des options. Ne touchent pas au chemin par défaut
// (parité #5) ni à random/safe_heuristic (côté Python).

import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_settings.dart' show BotSkillLevel;
import 'package:dutch_game/services/game/engine_random.dart';

import '../../tool/rl_env_runner.dart'
    show RlEnv, parseExistingBotSkill, parseExistingBotOpponent;

Set<String> _legalKeys(Map<String, dynamic> obs) {
  final actions =
      ((obs['legal_action_v2'] as Map?)?['actions'] as List?) ?? const [];
  return {
    for (final a in actions)
      _key((a as Map)['action_v2'] as Map),
  };
}

String _key(Map action) {
  final sorted = action.keys.map((k) => '$k=${action[k]}').toList()..sort();
  return sorted.join('|');
}

void main() {
  group('existing_bot : forçage difficile de tous les joueurs', () {
    test('forceAllSkill=difficile => p0 ET adversaires en difficile', () async {
      for (var s = 0; s < 20; s++) {
        final env = RlEnv(
          episodeId: 'hard$s',
          forceAllSkill: BotSkillLevel.difficile,
        );
        await env.reset(s);
        expect(env.players, isNotEmpty);
        for (final p in env.players) {
          expect(p.botSkillLevel, BotSkillLevel.difficile,
              reason: 'seed $s joueur ${p.id} devrait être difficile');
        }
      }
    });
  });

  group('existing_bot : benchmark hétérogène (p0 fort vs adversaires faibles)', () {
    test('forcedOpponentSkillOverride => p0 difficile, adversaires bronze',
        () async {
      for (var s = 0; s < 15; s++) {
        final env = RlEnv(
          episodeId: 'het$s',
          forcedNumPlayers: 6,
          forceAllSkill: BotSkillLevel.difficile,
          forcedOpponentSkillOverride: BotSkillLevel.bronze,
        );
        await env.reset(s);
        expect(env.players[0].botSkillLevel, BotSkillLevel.difficile,
            reason: 'seed $s : p0 doit rester difficile');
        for (final p in env.players.skip(1)) {
          expect(p.botSkillLevel, BotSkillLevel.bronze,
              reason: 'seed $s : adversaire ${p.id} doit être bronze');
        }
      }
    });

    test('opponentsMixed => p0 difficile, adversaires variés', () async {
      final oppSkills = <BotSkillLevel>{};
      for (var s = 0; s < 30; s++) {
        final env = RlEnv(
          episodeId: 'mix$s',
          forcedNumPlayers: 6,
          forceAllSkill: BotSkillLevel.difficile,
          opponentsMixed: true,
        );
        await env.reset(s);
        expect(env.players[0].botSkillLevel, BotSkillLevel.difficile);
        for (final p in env.players.skip(1)) {
          oppSkills.add(p.botSkillLevel!);
        }
      }
      // Sur 30 seeds, plusieurs niveaux adverses doivent apparaître.
      expect(oppSkills.length, greaterThan(1),
          reason: 'mixed devrait produire des niveaux adverses variés');
    });

    test('homogène (forceAllSkill seul) : adversaires = p0', () async {
      final env = RlEnv(
        episodeId: 'homo',
        forcedNumPlayers: 6,
        forceAllSkill: BotSkillLevel.silver,
      );
      await env.reset(0);
      for (final p in env.players) {
        expect(p.botSkillLevel, BotSkillLevel.silver);
      }
    });

    test('parseExistingBotOpponent', () {
      expect(parseExistingBotOpponent(const {}), (null, false));
      expect(parseExistingBotOpponent({'opponent_bot_difficulty': 'bronze'}),
          (BotSkillLevel.bronze, false));
      expect(parseExistingBotOpponent({'opponent_bot_difficulty': 'hard'}),
          (BotSkillLevel.difficile, false));
      expect(parseExistingBotOpponent({'opponent_bot_difficulty': 'mixed'}),
          (null, true));
      expect(
          () => parseExistingBotOpponent({'opponent_bot_difficulty': 'xyz'}),
          throwsA(isA<FormatException>()));
    });
  });

  group('existing_bot : pilotage bot_auto complet', () {
    test('épisodes terminent, applied_action_v2 toujours légal', () async {
      final seenTypes = <String>{};
      for (var s = 0; s < 30; s++) {
        final env = RlEnv(
          episodeId: 'auto$s',
          forceAllSkill: BotSkillLevel.difficile,
        );
        var obs = await env.reset(s);
        var guard = 0;
        while (obs['done'] != true && guard++ < 3000) {
          final legalBefore = _legalKeys(obs);
          final next = await env.step({'kind': 'bot_auto'});
          expect(next['type'], isNot('error'),
              reason: 'seed $s : erreur runner ${next['message']}');
          final applied = next['applied_action_v2'] as Map?;
          expect(applied, isNotNull,
              reason: 'seed $s : applied_action_v2 manquant');
          // Vigilance 1 : l'action appliquée appartient au légal d'AVANT l'action.
          expect(legalBefore.contains(_key(applied!)), isTrue,
              reason: 'seed $s : action appliquée hors légal: $applied');
          seenTypes.add(applied['action_type'] as String);
          obs = next;
        }
        expect(obs['done'], true, reason: 'seed $s : épisode non terminé');
      }
      // Couverture : les actions cœur doivent apparaître sur 30 seeds.
      for (final t in ['draw', 'post_draw_replace', 'post_draw_discard',
          'match', 'pass_tick']) {
        expect(seenTypes.contains(t), isTrue, reason: 'type $t jamais capturé');
      }
    });
  });

  group('existing_bot : capture exacte du slot de match (bots faibles)', () {
    test('bronze p0 : faux/bons matchs capturés, slot légal, pas de crash',
        () async {
      var matchActions = 0;
      var falseMatches = 0;
      for (var s = 0; s < 25; s++) {
        final env =
            RlEnv(episodeId: 'br$s', forceAllSkill: BotSkillLevel.bronze);
        var obs = await env.reset(s);
        var guard = 0;
        while (obs['done'] != true && guard++ < 3000) {
          final legalBefore = _legalKeys(obs);
          final next = await env.step({'kind': 'bot_auto'});
          expect(next['type'], isNot('error'),
              reason: 'seed $s : ${next['message']}');
          final applied = next['applied_action_v2'] as Map;
          expect(legalBefore.contains(_key(applied)), isTrue,
              reason: 'seed $s : slot capturé hors légal: $applied');
          if (applied['action_type'] == 'match') {
            matchActions++;
            expect(applied['slot'], isA<int>());
            // Faux match : un évènement match_failure_penalty apparaît pour p0.
            final events = (next['recent_events'] as List?) ?? const [];
            if (events.any((e) =>
                (e as Map)['event_type'] == 'match_failure_penalty' &&
                e['actor'] == env.rlSeat.id)) {
              falseMatches++;
            }
          }
          obs = next;
        }
        expect(obs['done'], true);
      }
      // Bronze produit des matchs, dont des faux (capturés sans best-effort).
      expect(matchActions, greaterThan(0), reason: 'aucun match bronze capturé');
      expect(falseMatches, greaterThan(0),
          reason: 'bronze devrait produire des faux matchs capturés');
    });
  });

  group('existing_bot : parsing des options', () {
    test('p0_policy existing_bot => difficile par défaut', () {
      expect(parseExistingBotSkill({'p0_policy': 'existing_bot'}),
          BotSkillLevel.difficile);
    });
    test('bot_difficulty hard => difficile', () {
      expect(parseExistingBotSkill({'bot_difficulty': 'hard'}),
          BotSkillLevel.difficile);
      expect(parseExistingBotSkill({'bot_difficulty': 'difficile'}),
          BotSkillLevel.difficile);
    });
    test('bot_difficulty explicite l\'emporte sur le défaut existing_bot', () {
      expect(
          parseExistingBotSkill(
              {'p0_policy': 'existing_bot', 'bot_difficulty': 'silver'}),
          BotSkillLevel.silver);
    });
    test('aucune option existing_bot => null (chemin défaut inchangé)', () {
      expect(parseExistingBotSkill(const {}), isNull);
      expect(parseExistingBotSkill({'num_players': 4}), isNull);
    });
    test('p0_policy inconnu => FormatException', () {
      expect(() => parseExistingBotSkill({'p0_policy': 'foo'}),
          throwsA(isA<FormatException>()));
    });
    test('bot_difficulty inconnu => FormatException', () {
      expect(() => parseExistingBotSkill({'bot_difficulty': 'legendary'}),
          throwsA(isA<FormatException>()));
    });
  });

  group('existing_bot : déterminisme (pas de double-apply visible)', () {
    test('même seed => mêmes rangs/scores finaux', () async {
      for (var s = 0; s < 10; s++) {
        final a = RlEnv(episodeId: 'd$s', forceAllSkill: BotSkillLevel.difficile);
        var obsA = await a.reset(s);
        while (obsA['done'] != true) {
          obsA = await a.step({'kind': 'bot_auto'});
        }
        final ranksA = a.gs.getFinalRanksWithTies();
        final scoresA = {for (final p in a.players) p.id: a.gs.getFinalScore(p)};

        EngineRandom.seed(999); // bruit RNG entre les deux runs
        final b = RlEnv(episodeId: 'd$s', forceAllSkill: BotSkillLevel.difficile);
        var obsB = await b.reset(s);
        while (obsB['done'] != true) {
          obsB = await b.step({'kind': 'bot_auto'});
        }
        final ranksB = b.gs.getFinalRanksWithTies();
        final scoresB = {for (final p in b.players) p.id: b.gs.getFinalScore(p)};

        expect(ranksB, ranksA, reason: 'seed $s : rangs non déterministes');
        expect(scoresB, scoresA, reason: 'seed $s : scores non déterministes');
      }
    });
  });
}
