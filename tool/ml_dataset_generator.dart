// Générateur de dataset ML self-play pour Dutch'78.
//
// Objectif : produire, par auto-jeu (bots vs bots) headless et FIDÈLE au vrai
// moteur Dart, des `BotGameRecord` JSON locaux pour entraîner un modèle qui
// prédit, depuis un état de partie en cours, si un joueur finira rang 1.
//
// Principes (validés avec l'auteur, cf. documentation/PROMPT_ML_DATASET.md) :
//  - Fidélité absolue au moteur réel : on réutilise GameLogic + les stratégies
//    pures + BotPowerHandler. On N'IMPORTE PAS BotAI (il tire dart:ui via
//    package:flutter/material.dart) ; on remire sa boucle avec les modules purs.
//  - PAS de "final lap" : annoncer Dutch termine la manche immédiatement (break).
//  - Pouvoirs (7/10/Valet/Joker) exécutés réellement via
//    BotPowerHandler.useBotSpecialPower(gs, diff, null, skipDelay: true)
//    (headless-safe : stub de notifications no-op + gardes `if (target.isHuman)`).
//  - Snapshot des features pris APRÈS applyMemoryDecay et AVANT que le bot
//    pioche/décide (= la connaissance réelle sur laquelle il joue). Jamais `hand`.
//  - Déterminisme : tout l'aléa passe par EngineRandom (seedé) ; les timestamps
//    viennent d'une horloge virtuelle (aucun DateTime.now()). Même --seed => JSON
//    byte-identique.
//  - Cible : `finalRank` via GameState.getFinalRanksWithTies() (fait foi : score
//    min, départage Dutch/ex-aequo). `won` = finalRank == 1 (dérivé côté Python).
//
// Usage :
//   dart run tool/ml_dataset_generator.dart --games=N --seed=S \
//     [--out=ml/data/raw/games] [--max-turns=500]

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/bot_learning_data.dart';
import 'package:dutch_game/services/game/engine_random.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/bot_personality.dart';

// ════════════════════════════════════════════════════════════════════════════
// Configuration CLI
// ════════════════════════════════════════════════════════════════════════════

class GeneratorConfig {
  final int games;
  final int seed;
  final String outDir;
  final int maxTurns;

  const GeneratorConfig({
    required this.games,
    required this.seed,
    required this.outDir,
    required this.maxTurns,
  });

  factory GeneratorConfig.parse(List<String> args) {
    final map = <String, String>{};
    for (final a in args) {
      final m = RegExp(r'^--([a-zA-Z\-]+)=(.*)$').firstMatch(a);
      if (m != null) map[m.group(1)!] = m.group(2)!;
    }
    return GeneratorConfig(
      games: int.tryParse(map['games'] ?? '') ?? 10,
      seed: int.tryParse(map['seed'] ?? '') ?? 42,
      outDir: map['out'] ?? 'ml/data/raw/games',
      maxTurns: int.tryParse(map['max-turns'] ?? '') ?? 500,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Horloge virtuelle : timestamps déterministes (jamais DateTime.now()).
// Un compteur monotone => un même --seed produit des dates identiques.
// ════════════════════════════════════════════════════════════════════════════

class VirtualClock {
  static final DateTime _base = DateTime.utc(2026, 1, 1);
  static const int _stepMs = 1000;
  int _tick = 0;

  DateTime next() => _base.add(Duration(milliseconds: _tick++ * _stepMs));
}

// ════════════════════════════════════════════════════════════════════════════
// Enregistreur local d'une partie (réutilise les modèles BotAction/BotGameRecord
// pour la sérialisation, MAIS n'envoie rien au serveur — écriture JSON locale).
// ════════════════════════════════════════════════════════════════════════════

class GameRecorder {
  GameRecorder({required this.gameId, required this.clock});

  final String gameId;
  final VirtualClock clock;

  final Map<String, List<BotAction>> _actions = {};
  final Map<String, DateTime> _startTime = {};
  final Map<String, int> _initialHandSize = {};
  final Map<String, int> _powerUses = {};
  final Map<String, List<Map<String, dynamic>>> _opponents = {};

  void startRecording(Player bot, GameState gs) {
    _actions[bot.id] = [];
    _startTime[bot.id] = clock.next();
    _initialHandSize[bot.id] = bot.hand.length;
    _powerUses[bot.id] = 0;
    _opponents[bot.id] = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'isHuman': p.isHuman,
              'behavior': p.botBehavior?.toString().split('.').last,
              'skillLevel': p.botSkillLevel?.toString().split('.').last,
            })
        .toList();
  }

  /// Snapshot pris AU DÉBUT du tour (après decay, avant décision).
  /// `actionType`/`result` restent provisoires (remplis post-action, métadonnée).
  void recordSnapshot(Player bot, GameState gs, int turnNumber) {
    _actions[bot.id]?.add(BotAction(
      actionType: '',
      turnNumber: turnNumber,
      timestamp: clock.next(),
      gameState: _captureSnapshot(gs, bot),
      actionDetails: const {},
      result: const {},
    ));
  }

  /// Renseigne l'action effectivement jouée (métadonnée ; `result.*` blocklisté ML).
  void updateLastResult(
      String botId, String actionType, Map<String, dynamic> result) {
    final list = _actions[botId];
    if (list == null || list.isEmpty) return;
    final last = list.last;
    list[list.length - 1] = BotAction(
      actionType: actionType,
      turnNumber: last.turnNumber,
      timestamp: last.timestamp,
      gameState: last.gameState,
      actionDetails: last.actionDetails,
      result: result,
    );
  }

  void notePowerUse(String botId) =>
      _powerUses[botId] = (_powerUses[botId] ?? 0) + 1;

  BotGameRecord finalize(
    Player bot,
    GameState gs, {
    required int finalScore,
    required int finalRank,
  }) {
    final actions = _actions[bot.id] ?? const <BotAction>[];
    final calledDutch = gs.dutchCallerId == bot.id;
    final behavior = bot.botBehavior?.toString().split('.').last ?? 'unknown';
    final skill = bot.botSkillLevel?.toString().split('.').last ?? 'unknown';

    // avgDecisionTime dérivé de l'horloge virtuelle (déterministe ; blocklisté ML).
    final times = actions.map((a) => a.timestamp).toList();
    double avgDecisionTime = 0;
    if (times.length >= 2) {
      var sum = 0;
      for (var i = 1; i < times.length; i++) {
        sum += times[i].difference(times[i - 1]).inMilliseconds;
      }
      avgDecisionTime = sum / (times.length - 1);
    }

    return BotGameRecord(
      gameId: gameId,
      botId: '${behavior}_$skill',
      botName: bot.name,
      botBehavior: behavior,
      botSkillLevel: skill,
      startTime: _startTime[bot.id] ?? VirtualClock._base,
      endTime: clock.next(),
      numberOfPlayers: gs.players.length,
      gameMode: gs.gameMode.toString().split('.').last,
      usedSBMM: false,
      actions: actions,
      // initialHandScore/Rank laissés null : info dérivée de `hand` (anti-leakage).
      initialHandSize: _initialHandSize[bot.id] ?? bot.hand.length,
      finalScore: finalScore,
      finalRank: finalRank,
      calledDutch: calledDutch,
      wonDutch: calledDutch && finalRank == 1,
      cardsAtDutch: calledDutch ? bot.hand.length : 0,
      scoreAtDutch: calledDutch ? finalScore : 0,
      totalTurns: actions.length,
      avgDecisionTime: avgDecisionTime,
      powerUsesCount: _powerUses[bot.id] ?? 0,
      goodDecisions: 0,
      badDecisions: 0,
      opponents: _opponents[bot.id] ?? const [],
    );
  }

  // ── Snapshot des features (schéma a/b/c). JAMAIS `hand`. ──────────────────
  Map<String, dynamic> _captureSnapshot(GameState gs, Player bot) {
    const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];

    final opponentHandSizes = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => p.hand.length)
        .toList();

    // (b) Croyance : valeur attendue des cartes inconnues (mentalMap == null).
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    double expectedUnknownSum = 0;
    for (final i in unknownIndices) {
      expectedUnknownSum +=
          BotMemoryManager.getUnknownBeliefExpectedValue(gs, bot, i);
    }
    final doublons = BotMemoryManager.findDoublons(bot);
    final believedKnownScore = bot.getKnownScore();

    double bestMatchProb = 0;
    for (final r in ranks) {
      final p = BotMemoryManager.getMatchProbability(gs, bot, r);
      if (p > bestMatchProb) bestMatchProb = p;
    }

    final spiedCount = bot.spyMemory.values
        .fold<int>(0, (sum, m) => sum + m.length);

    final top = gs.topDiscardCard;

    return {
      // (a) Infos publiques au tour t
      'turnCount': gs.turnCount,
      'actionCount': gs.actionCount,
      'phase': gs.phase.toString().split('.').last,
      'numberOfPlayers': gs.players.length,
      'botSeatIndex': bot.position,
      'deckSize': gs.remainingDeckCards,
      'discardPileSize': gs.discardPile.length,
      'topDiscardValue': top?.value,
      'topDiscardPoints': top?.points,
      'botHandSize': bot.hand.length,
      'opponentsHandSizes': opponentHandSizes,
      'minOpponentHandSize':
          opponentHandSizes.isEmpty ? null : opponentHandSizes.reduce(min),
      'expectedDeckCardValue': BotMemoryManager.getExpectedDeckCardValue(gs),
      'discardedRanks': BotMemoryManager.countDiscardedRanks(gs),
      'dutchCalledAlready': gs.dutchCallerId != null,
      // (b) Croyance du bot — mentalMap / knownCards / spyMemory uniquement
      'knownCardCount': bot.knownCardCount, // getter = nb mentalMap != null
      'unknownCardCount': bot.unknownCardCount,
      'memoryConfidence': bot.getMemoryConfidence(),
      'believedKnownScore': believedKnownScore,
      'maxKnownCardValue': BotMemoryManager.getMaxKnownCardValue(bot),
      'hasDoublon': doublons.isNotEmpty,
      'doublonCount': doublons.length,
      'expectedUnknownValueSum': expectedUnknownSum,
      'believedTotalScoreEstimate': believedKnownScore + expectedUnknownSum,
      'spiedOpponentCardsCount': spiedCount,
      'bestMatchProbability': bestMatchProb,
      // (c) Personnalité / paramètres
      'botBehavior': bot.botBehavior?.toString().split('.').last,
      'botSkillLevel': bot.botSkillLevel?.toString().split('.').last,
      'usedSBMM': false,
      // aiParams_* : null en étape 2 (personnalités synthétiques = étape 3)
      'aiParams': bot.aiParameters,
    };
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Construction des bots (étape 2 : skill + behavior variés, aiParameters null).
// Les personnalités synthétiques (aiParameters) seront ajoutées à l'étape 3.
// Tous les tirages passent par EngineRandom (seedé) => reproductible.
// ════════════════════════════════════════════════════════════════════════════

List<Player> buildBots() {
  final rng = EngineRandom.instance;
  final n = 2 + rng.nextInt(3); // {2,3,4}
  final behaviors = BotBehavior.values;
  final skills = BotSkillLevel.values;
  return List<Player>.generate(n, (i) {
    final behavior = behaviors[rng.nextInt(behaviors.length)];
    final skill = skills[rng.nextInt(skills.length)];
    return Player(
      id: 'p$i',
      name: '${behavior.name}_${skill.name}_$i',
      isHuman: false,
      botBehavior: behavior,
      botSkillLevel: skill,
      position: i,
    );
  });
}

// ════════════════════════════════════════════════════════════════════════════
// Une partie : boucle fidèle au moteur (miroir headless de BotAI.playBotTurn).
// ════════════════════════════════════════════════════════════════════════════

Future<List<BotGameRecord>> playOneGame(int gameIndex, GeneratorConfig cfg) async {
  final clock = VirtualClock();
  final players = buildBots();
  final gs = GameLogic.initializeGame(
    players: players,
    gameMode: GameMode.quick,
    difficulty: Difficulty.medium,
  );
  gs.phase = GamePhase.playing;

  final recorder = GameRecorder(gameId: 'game_${cfg.seed}_$gameIndex', clock: clock);
  for (final bot in players) {
    recorder.startRecording(bot, gs);
  }

  var guard = 0;
  while (gs.phase != GamePhase.ended &&
      gs.phase != GamePhase.dutchCalled &&
      guard < cfg.maxTurns) {
    guard++;
    final bot = gs.currentPlayer;
    final diff = BotConfig.getDifficulty(bot, null);
    final phaseBot = BotConfig.getBotPhase(bot, gs);
    final perso = BotPersonality.fromBot(bot);

    // 1) Décroissance mémoire (mutation) AVANT le snapshot : le snapshot doit
    //    refléter la croyance réelle sur laquelle le bot va décider.
    BotMemoryManager.applyMemoryDecay(bot, diff, personality: perso);

    // 2) SNAPSHOT (features a/b/c) — après decay, AVANT toute décision/pioche.
    recorder.recordSnapshot(bot, gs, gs.turnCount);

    // 3) Décision Dutch : annoncer Dutch termine la manche IMMÉDIATEMENT.
    if (BotDutchStrategy.shouldCallDutch(gs, bot, diff, phaseBot, personality: perso)) {
      GameLogic.callDutch(gs);
      recorder.updateLastResult(bot.id, 'call_dutch', const {});
      break; // ⚠ PAS de final lap (fidèle à Dutch'78).
    }

    // 4) Pioche.
    GameLogic.drawCard(gs);
    if (gs.phase == GamePhase.ended || gs.phase == GamePhase.dutchCalled) break;

    // 5) Décision sur la carte piochée (garder/échanger/défausser).
    await BotCardStrategy.decideCardAction(gs, bot, diff, phaseBot, personality: perso);

    // 6) Pouvoir spécial éventuel (7/10/Valet/Joker) — exécuté FIDÈLEMENT.
    if (gs.phase == GamePhase.specialPower) {
      await BotPowerHandler.useBotSpecialPower(gs, diff, null,
          personality: perso, skipDelay: true);
      recorder.notePowerUse(bot.id);
      gs.phase = GamePhase.playing;
      gs.isWaitingForSpecialPower = false;
      gs.specialCardToActivate = null;
    }

    recorder.updateLastResult(
        bot.id, 'play_turn', {'believedScoreAfter': bot.getKnownScore()});

    // 7) Phase de réaction (déclenchée manuellement : discardDrawnCard ne l'ouvre pas).
    await _runReactionPhase(gs);

    // 8) Fin de deck.
    if (gs.deck.isEmpty && gs.discardPile.length <= 1) break;

    GameLogic.nextPlayer(gs);
  }

  // Fin de manche : révèle les cartes et fige les scores.
  GameLogic.endGame(gs);
  final ranks = gs.getFinalRanksWithTies();

  return players
      .map((bot) => recorder.finalize(
            bot,
            gs,
            finalScore: gs.getFinalScore(bot),
            finalRank: ranks[bot.id] ?? gs.players.length,
          ))
      .toList();
}

Future<void> _runReactionPhase(GameState gs) async {
  gs.phase = GamePhase.reaction;
  for (final p in gs.players) {
    if (p.isHuman) continue;
    if (gs.phase != GamePhase.reaction) break;
    final diff = BotConfig.getDifficulty(p, null);
    final phaseBot = BotConfig.getBotPhase(p, gs);
    final perso = BotPersonality.fromBot(p);
    await BotCardStrategy.tryReactionMatch(gs, p, diff, phaseBot,
        personality: perso, skipDelay: true);
  }
  if (gs.phase == GamePhase.reaction) gs.phase = GamePhase.playing;
}

// ════════════════════════════════════════════════════════════════════════════
// Écriture JSON locale (un fichier par bot par partie). Pas de POST serveur.
// ════════════════════════════════════════════════════════════════════════════

void writeRecord(BotGameRecord record, String uniqueId, String outDir) {
  final file = File('$outDir/${record.gameId}_$uniqueId.json');
  file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(record.toJson()));
}

// ════════════════════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  final cfg = GeneratorConfig.parse(args);
  EngineRandom.seed(cfg.seed); // seeding global déterministe (étape 1)

  Directory(cfg.outDir).createSync(recursive: true);

  var totalRecords = 0;
  var totalSnapshots = 0;
  var totalWins = 0;
  final skillCounts = <String, int>{};

  stdout.writeln('[generator] games=${cfg.games} seed=${cfg.seed} out=${cfg.outDir}');

  for (var g = 0; g < cfg.games; g++) {
    // On reconstruit la liste des joueurs pour nommer les fichiers : on récupère
    // donc les Player via le GameState retourné indirectement par les records.
    final records = await playOneGame(g, cfg);
    // L'ordre des records == ordre des players (p0, p1, …) ; l'index sert d'id
    // unique pour le nom de fichier (record.botId = behavior_skill n'est pas unique).
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      writeRecord(record, 'p$i', cfg.outDir);
      totalRecords++;
      totalSnapshots += record.actions.length;
      if (record.finalRank == 1) totalWins++;
      skillCounts[record.botSkillLevel] =
          (skillCounts[record.botSkillLevel] ?? 0) + 1;
    }
  }

  stdout.writeln('[generator] terminé.');
  stdout.writeln('  parties        : ${cfg.games}');
  stdout.writeln('  records (bots) : $totalRecords');
  stdout.writeln('  snapshots      : $totalSnapshots');
  stdout.writeln('  won==1 (rang1) : $totalWins '
      '(${totalRecords == 0 ? 0 : (100 * totalWins / totalRecords).toStringAsFixed(1)}%)');
  stdout.writeln('  par niveau     : $skillCounts');
}
