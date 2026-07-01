// Verrou d'alignement : l'orchestration bot NORMALE (`BotAI.playBotTurn`) doit
// produire EXACTEMENT le même déroulé que l'orchestration HEADLESS de référence
// (`playOneGame` du générateur, elle-même byte-parity avec `tool/rl_env_runner`
// via le test #5 `frozenBotMode`).
//
// Motivation : le test #5 prouve « runner == générateur ». Ce test ferme la
// dernière boucle : « générateur == BotAI.playBotTurn (chemin de jeu normal) »,
// pour garantir que le headless reste aligné avec la VRAIE logique bot et pas
// seulement avec le générateur.
//
// Pourquoi c'est comparable malgré les différences documentées :
//  - `getThinkingTime` / délais post-draw : arithmétique pure, AUCUN EngineRandom
//    (vérifié) ; neutralisés ici par `fakeAsync` (temps virtuel).
//  - `GameLoggerService` : désactivé (`setEnabled(false)`) → aucune I/O.
//  - `BotFairPlayAudit` (asserts) : `shouldCallDutch` ne consomme PAS EngineRandom,
//    donc l'audit est RNG-neutre.
//  - `BotGossipService.onBotTurn` : utilise un `Random` privé (pas EngineRandom) et
//    ne propose une alliance que contre un LEADER HUMAIN. `buildBots()` ne crée que
//    des bots → aucune alliance ne se forme → ZÉRO effet décision. On `reset()`
//    quand même le service par prudence. (Décision gossip/alliance : ignorée
//    volontairement pour la collecte RL bot-vs-bot ; cf.
//    docs/ai/RL_HEADLESS_BOT_ALIGNMENT_AUDIT.md.)
//  - `skipDelay` (power) : ne gate qu'un `Future.delayed` (aucun RNG/logique).
//
// Conséquence : la séquence de tirages EngineRandom et les décisions sont
// identiques → rangs / scores / dutchCaller finaux doivent coïncider.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dutch_game/models/game_settings.dart' show Difficulty;
import 'package:dutch_game/models/game_state.dart' show GamePhase, GameMode;
import 'package:dutch_game/models/player.dart' show Player;
import 'package:dutch_game/services/game/engine_random.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot_ai.dart' show BotAI;
import 'package:dutch_game/services/game/bot/bot_gossip_service.dart'
    show BotGossipService;
import 'package:dutch_game/services/logging/game_logger_service.dart'
    show GameLoggerService;

import '../../tool/ml_dataset_generator.dart'
    show playOneGame, GeneratorConfig, buildBots;

class _Outcome {
  _Outcome({
    required this.id,
    required this.finalScore,
    required this.finalRank,
    required this.calledDutch,
    required this.turns,
  });
  final String id;
  final int finalScore;
  final int finalRank;
  final bool calledDutch;
  final int turns;
}

/// Rejoue une partie complète via l'orchestration bot NORMALE (`BotAI`), avec la
/// MÊME structure de boucle que `playOneGame`. Le power et la réaction sont
/// pilotés hors de `playBotTurn`, exactement comme le fait l'orchestrateur réel.
Future<List<_Outcome>> _runViaBotAI(int maxTurns) async {
  final players = buildBots();
  final gs = GameLogic.initializeGame(
    players: players,
    gameMode: GameMode.quick,
    difficulty: Difficulty.medium,
  );
  gs.phase = GamePhase.playing;

  var guard = 0;
  while (gs.phase != GamePhase.ended &&
      gs.phase != GamePhase.dutchCalled &&
      guard < maxTurns) {
    guard++;

    // Décay + Dutch + pioche + décision carte : tout dans le chemin normal.
    await BotAI.playBotTurn(gs);
    if (gs.phase == GamePhase.ended || gs.phase == GamePhase.dutchCalled) {
      break;
    }

    // Pouvoir spécial éventuel (7/10/Valet/Joker) via le chemin normal.
    if (gs.phase == GamePhase.specialPower) {
      await BotAI.useBotSpecialPower(gs);
      gs.phase = GamePhase.playing;
      gs.isWaitingForSpecialPower = false;
      gs.specialCardToActivate = null;
    }

    // Phase de réaction (déclenchée manuellement, comme le vrai orchestrateur).
    gs.phase = GamePhase.reaction;
    for (final p in gs.players) {
      if (p.isHuman) continue;
      if (gs.phase != GamePhase.reaction) break;
      await BotAI.tryReactionMatch(gs, p);
    }
    if (gs.phase == GamePhase.reaction) gs.phase = GamePhase.playing;

    if (gs.deck.isEmpty && gs.discardPile.length <= 1) break;
    GameLogic.nextPlayer(gs);
  }

  GameLogic.endGame(gs);
  final ranks = gs.getFinalRanksWithTies();
  return [
    for (final Player p in gs.players)
      _Outcome(
        id: p.id,
        finalScore: gs.getFinalScore(p),
        finalRank: ranks[p.id] ?? gs.players.length,
        calledDutch: gs.dutchCallerId == p.id,
        turns: guard,
      ),
  ];
}

/// Exécute `_runViaBotAI` sous temps virtuel pour neutraliser les `Future.delayed`
/// (réflexion / post-draw / power) qui ne consomment aucun EngineRandom.
List<_Outcome> _runViaBotAIFast(int maxTurns) {
  List<_Outcome>? result;
  Object? error;
  fakeAsync((async) {
    () async {
      try {
        result = await _runViaBotAI(maxTurns);
      } catch (e) {
        error = e;
      }
    }();
    async.elapse(const Duration(minutes: 30));
  });
  if (error != null) {
    fail('BotAI orchestration threw: $error');
  }
  if (result == null) {
    fail('BotAI orchestration did not complete under fakeAsync');
  }
  return result!;
}

void main() {
  const int seeds = 100;
  const int maxTurns = 500;

  setUp(() {
    GameLoggerService.instance.setEnabled(false);
    BotGossipService.instance.reset();
  });

  group('Alignement orchestration headless (générateur) vs bot normal (BotAI)', () {
    test('rangs / scores / dutchCaller identiques sur $seeds seeds', () async {
      for (var s = 0; s < seeds; s++) {
        // Référence headless : générateur (byte-parity avec le runner, test #5).
        EngineRandom.seed(s);
        final ref = await playOneGame(
          0,
          GeneratorConfig(games: 1, seed: s, outDir: '.', maxTurns: maxTurns),
        );

        // Chemin bot normal : BotAI.playBotTurn (même seed, délais neutralisés).
        EngineRandom.seed(s);
        BotGossipService.instance.reset();
        final got = _runViaBotAIFast(maxTurns);

        expect(got.length, ref.length,
            reason: 'seed $s : nombre de joueurs divergent');
        for (var i = 0; i < ref.length; i++) {
          expect(got[i].finalRank, ref[i].finalRank,
              reason: 'seed $s joueur $i : rang final divergent');
          expect(got[i].finalScore, ref[i].finalScore,
              reason: 'seed $s joueur $i : score final divergent');
          expect(got[i].calledDutch, ref[i].calledDutch,
              reason: 'seed $s joueur $i : dutchCaller divergent');
        }
      }
    });
  });
}
