import 'dart:async';
import 'dart:io';

import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_personality.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/discard_tracker.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/logging/game_logger_service.dart';

enum _RunMode { turn, dutch, power }

Future<void> main(List<String> args) async {
  try {
    GameLoggerService.instance.reset();
    GameLoggerService.instance.setEnabled(true);

    final config = _CliConfig.fromArgs(args);
    if (config.help) {
      _printHelp();
      return;
    }

    final injected = _InjectedScenario.fromConfig(config);
    final gameState = injected.gameState;
    final bot = injected.bot;

    stdout.writeln('=== BOT HAND INJECTION CLI ===');
    stdout.writeln(
      'mode=${config.runMode.name} '
      'botSkill=${bot.botSkillLevel?.name ?? 'none'} '
      'botBehavior=${bot.botBehavior?.name ?? 'none'} '
      'players=${gameState.players.length}',
    );
    stdout.writeln('');

    _printStateSnapshot('AVANT', gameState, bot, showTable: config.showTable);
    _printDutchTrace(gameState, bot);

    final historyBefore = gameState.actionHistory.length;
    await _runScenario(config, gameState, bot);

    stdout.writeln('');
    _printStateSnapshot('APRES', gameState, bot, showTable: config.showTable);
    _printDutchTrace(gameState, bot);
    _printRecentHistory(gameState, historyBefore);
    _printBotDebugLogs();
  } on FormatException catch (e) {
    stderr.writeln('Configuration invalide: ${e.message}');
    stderr.writeln('');
    _printHelp();
    exitCode = 64;
  }
}

Future<void> _runScenario(
  _CliConfig config,
  GameState gs,
  Player bot,
) async {
  switch (config.runMode) {
    case _RunMode.dutch:
      final difficulty = BotConfig.getDifficulty(bot, null);
      final phase = BotConfig.getBotPhase(bot, gs);
      final personality = BotPersonality.fromBot(bot);
      final shouldCall = BotDutchStrategy.shouldCallDutch(
        gs,
        bot,
        difficulty,
        phase,
        personality: personality,
      );
      stdout.writeln('DECISION DUTCH = ${shouldCall ? 'CALL' : 'WAIT'}');
      if (shouldCall) {
        GameLogic.callDutch(gs, reason: 'cli_injection');
      }
      break;
    case _RunMode.power:
      if (config.activatePowerValue == null) {
        throw const FormatException(
          'mode=power nécessite --activate-power=7|10|V|JOKER',
        );
      }
      gs.isWaitingForSpecialPower = true;
      gs.specialCardToActivate =
          PlayingCard.create('hearts', config.activatePowerValue!);
      final difficulty = BotConfig.getDifficulty(bot, null);
      final personality = BotPersonality.fromBot(bot);
      await BotPowerHandler.useBotSpecialPower(
        gs,
        difficulty,
        null,
        personality: personality,
        skipDelay: true,
      );
      break;
    case _RunMode.turn:
      await _playBotTurnHeadless(gs);
      break;
  }
}

Future<void> _playBotTurnHeadless(GameState gs) async {
  final bot = gs.currentPlayer;
  if (bot.isHuman) return;

  final difficulty = BotConfig.getDifficulty(bot, null);
  final phase = BotConfig.getBotPhase(bot, gs);
  final personality = BotPersonality.fromBot(bot);

  BotMemoryManager.applyMemoryDecay(
    bot,
    difficulty,
    personality: personality,
  );

  final shouldCallDutch = BotDutchStrategy.shouldCallDutch(
    gs,
    bot,
    difficulty,
    phase,
    personality: personality,
  );
  if (shouldCallDutch) {
    GameLogic.callDutch(gs, reason: 'cli_injection_turn');
    return;
  }

  GameLogic.drawCard(gs);
  if (gs.drawnCard == null) return;

  await BotCardStrategy.decideCardAction(
    gs,
    bot,
    difficulty,
    phase,
    personality: personality,
  );

  if (gs.isWaitingForSpecialPower && gs.specialCardToActivate != null) {
    await BotPowerHandler.useBotSpecialPower(
      gs,
      difficulty,
      null,
      personality: personality,
      skipDelay: true,
    );
  }
}

void _printStateSnapshot(
  String title,
  GameState gs,
  Player bot, {
  required bool showTable,
}) {
  stdout.writeln('--- $title ---');
  stdout.writeln(
    'phase=${gs.phase.name} turnCount=${gs.turnCount} actionCount=${gs.actionCount}',
  );
  stdout.writeln(
    'discardTop=${_fmtCard(gs.topDiscardCard)} deck=${gs.deck.length} '
    'drawn=${_fmtCard(gs.drawnCard)} dutchCaller=${gs.dutchCallerId ?? '-'}',
  );
  stdout.writeln('botHand=${_fmtHand(bot.hand)}');
  stdout.writeln('botMental=${_fmtMental(bot)}');
  stdout.writeln(
    'unknownIndices=${BotMemoryManager.getUnknownIndices(bot)} '
    'knownScore=${bot.getKnownScore()}',
  );
  stdout.writeln('swapHints=${_fmtSwapHints(bot)}');
  stdout.writeln(
    'jokerInference='
    '${bot.jokerInferenceActive ? 'active(${bot.jokerInferenceMode})' : 'off'}',
  );

  if (showTable) {
    stdout.writeln('table=');
    for (int i = 0; i < gs.players.length; i++) {
      final p = gs.players[i];
      stdout.writeln(
        '  #$i ${p.name} '
        '[${p.isHuman ? 'human' : (p.botSkillLevel?.name ?? 'bot')}] '
        'cards=${p.hand.length} score=${p.calculateScore()} hand=${_fmtHand(p.hand)}',
      );
    }
  }
}

void _printDutchTrace(GameState gs, Player bot) {
  final difficulty = BotConfig.getDifficulty(bot, null);
  final phase = BotConfig.getBotPhase(bot, gs);
  final personality = BotPersonality.fromBot(bot);
  final trace = BotDutchStrategy.buildObservationTrace(
    gs,
    bot,
    difficulty,
    phase,
    personality: personality,
  );

  stdout.writeln('traceDutch: ${trace.conclusion}');
  stdout.writeln(
    '  perceived=${trace.perceivedScore} known=${trace.knownScore} '
    'unknown=${trace.unknownCount} bestOpp=${trace.bestOpponentEstimate} '
    'threshold=${trace.hybridThreshold} margin=${trace.margin}',
  );
  if (trace.blockers.isNotEmpty) {
    stdout.writeln('  blockers=${trace.blockers.join(' | ')}');
  }
  if (trace.opportunities.isNotEmpty) {
    stdout.writeln('  opportunities=${trace.opportunities.join(' | ')}');
  }
}

void _printRecentHistory(GameState gs, int historyBefore) {
  final delta = gs.actionHistory.length - historyBefore;
  if (delta <= 0) {
    stdout.writeln('history: aucun nouvel évènement');
    return;
  }
  final recent = gs.actionHistory.take(delta).toList().reversed.toList();
  stdout.writeln('history (+$delta):');
  for (final line in recent) {
    stdout.writeln('  $line');
  }
}

void _printBotDebugLogs() {
  final content = GameLoggerService.instance.getLogContent();
  if (content.trim().isEmpty) {
    stdout.writeln('botDebug: aucune trace');
    return;
  }

  final lines = content.split('\n');
  final captured = <String>[];
  bool inDebugBlock = false;

  for (final line in lines) {
    if (line.contains('[BOT DEBUG]')) {
      captured.add(line.trimRight());
      inDebugBlock = true;
      continue;
    }
    if (!inDebugBlock) continue;

    if (line.trim().isEmpty) {
      inDebugBlock = false;
      continue;
    }
    // Les clés contexte sont indentées.
    if (line.startsWith('    ')) {
      captured.add(line.trimRight());
      continue;
    }
    inDebugBlock = false;
  }

  if (captured.isEmpty) {
    stdout.writeln('botDebug: aucune trace');
    return;
  }

  stdout.writeln('botDebug:');
  for (final line in captured) {
    stdout.writeln('  $line');
  }
}

String _fmtHand(List<PlayingCard> cards) {
  if (cards.isEmpty) return '[]';
  return '[${cards.map(_fmtCardShort).join(', ')}]';
}

String _fmtMental(Player bot) {
  if (bot.hand.isEmpty) return '[]';
  final entries = <String>[];
  for (int i = 0; i < bot.hand.length; i++) {
    final known = i < bot.mentalMap.length ? bot.mentalMap[i] : null;
    entries.add(known == null ? '$i:?' : '$i:${_fmtCardShort(known)}');
  }
  return '[${entries.join(', ')}]';
}

String _fmtSwapHints(Player bot) {
  final hints = <String>[];
  for (int i = 0; i < bot.hand.length; i++) {
    final action = bot.getUnknownCardHintAction(i);
    if (action == null) continue;
    final quality = bot.getUnknownCardHintQuality(i)?.toStringAsFixed(2) ?? '?';
    final confidence =
        bot.getUnknownCardHintConfidence(i)?.toStringAsFixed(2) ?? '?';
    hints.add('$i(a=$action q=$quality c=$confidence)');
  }
  return hints.isEmpty ? 'none' : hints.join(' | ');
}

String _fmtCard(PlayingCard? card) {
  if (card == null) return '-';
  return '${_fmtCardShort(card)}(${card.points})';
}

String _fmtCardShort(PlayingCard card) {
  return '${card.value}${_suitShort(card.suit)}';
}

String _suitShort(String suit) {
  switch (suit) {
    case 'hearts':
      return 'h';
    case 'diamonds':
      return 'd';
    case 'clubs':
      return 'c';
    case 'spades':
      return 's';
    default:
      return '?';
  }
}

class _InjectedScenario {
  final GameState gameState;
  final Player bot;

  const _InjectedScenario({
    required this.gameState,
    required this.bot,
  });

  factory _InjectedScenario.fromConfig(_CliConfig config) {
    final bot = Player(
      id: 'bot_injected',
      name: config.botName,
      isHuman: false,
      botBehavior: config.botBehavior,
      botSkillLevel: config.botSkill,
      position: 0,
      hand: List<PlayingCard>.from(config.botHand),
      knownCards: List<bool>.filled(config.botHand.length, false),
    );

    bot.mentalMap =
        List<PlayingCard?>.filled(config.botHand.length, null, growable: true);
    bot.resetUnknownCardHints();

    if (config.botMentalValues != null) {
      if (config.botMentalValues!.length != bot.hand.length) {
        throw const FormatException(
          '--bot-mental doit avoir la même taille que --bot-hand',
        );
      }
      for (int i = 0; i < bot.hand.length; i++) {
        final value = config.botMentalValues![i];
        if (value == null) continue;
        bot.mentalMap[i] = PlayingCard.create(bot.hand[i].suit, value);
        bot.knownCards[i] = true;
      }
    } else {
      final known = config.botKnownIndices.isNotEmpty
          ? config.botKnownIndices
          : List<int>.generate(
              bot.hand.length >= 2 ? 2 : bot.hand.length,
              (i) => i,
            );
      for (final idx in known) {
        if (idx < 0 || idx >= bot.hand.length) continue;
        bot.mentalMap[idx] = bot.hand[idx];
        bot.knownCards[idx] = true;
      }
    }

    for (final idx in config.valetUncertaintyIndices) {
      if (idx < 0 || idx >= bot.hand.length) continue;
      bot.mentalMap[idx] = null;
      bot.knownCards[idx] = false;
      bot.setUnknownCardHint(
        idx,
        quality: 0.0,
        confidence: 0.0,
        actionCount: config.actionCount,
      );
    }

    final players = <Player>[bot];
    for (int i = 0; i < config.opponents.length; i++) {
      final spec = config.opponents[i];
      final opponent = Player(
        id: 'opponent_$i',
        name: spec.name,
        isHuman: spec.isHuman,
        botBehavior: spec.isHuman ? null : BotBehavior.balanced,
        botSkillLevel: spec.isHuman ? null : spec.skill,
        position: i + 1,
        hand: List<PlayingCard>.from(spec.hand),
        knownCards: List<bool>.filled(spec.hand.length, false),
      );
      opponent.mentalMap = List<PlayingCard?>.filled(
        spec.hand.length,
        null,
        growable: true,
      );
      opponent.resetUnknownCardHints();
      players.add(opponent);
    }

    final discard = config.discard.isNotEmpty
        ? List<PlayingCard>.from(config.discard)
        : <PlayingCard>[PlayingCard.create('clubs', '5')];

    final deck = config.deck != null
        ? List<PlayingCard>.from(config.deck!)
        : _buildDefaultDeck(players, discard);
    if (config.drawCard != null) {
      deck.add(config.drawCard!);
    }
    if (deck.isEmpty) {
      throw const FormatException('Deck vide après injection.');
    }

    final gs = GameState(
      players: players,
      deck: deck,
      discardPile: discard,
      currentPlayerIndex: 0,
      gameMode: GameMode.quick,
      phase: GamePhase.playing,
      difficulty: Difficulty.medium,
      turnCount: config.turnCount,
      actionCount: config.actionCount,
    );

    BotDutchStrategy.discardTracker.reset();
    for (final card in gs.discardPile) {
      BotDutchStrategy.discardTracker.trackDiscard(
        card,
        discardedBy: 'scenario',
        wasExchange: false,
        actionType: DiscardActionType.drawnDiscard,
        turnCount: gs.turnCount,
      );
    }
    final byName = <String, Player>{
      for (final player in players) player.name.toLowerCase(): player,
    };
    for (final observed in config.observedActions) {
      final source = byName[observed.playerName.toLowerCase()];
      if (source == null) {
        throw FormatException(
          'observation inconnue: joueur "${observed.playerName}" absent',
        );
      }
      for (final card in observed.cards) {
        BotDutchStrategy.discardTracker.trackDiscard(
          card,
          discardedBy: source.id,
          wasExchange: observed.actionType == DiscardActionType.exchangeDiscard,
          actionType: observed.actionType,
          turnCount: gs.turnCount,
        );
      }
    }
    BotDutchStrategy.discardTracker.recordTableSnapshot(gs);
    return _InjectedScenario(gameState: gs, bot: bot);
  }

  static List<PlayingCard> _buildDefaultDeck(
    List<Player> players,
    List<PlayingCard> discard,
  ) {
    final deck = GameState.createFullDeck();

    void removeOnce(PlayingCard card) {
      final idx = deck.indexWhere((c) => c.id == card.id);
      if (idx != -1) {
        deck.removeAt(idx);
      }
    }

    for (final player in players) {
      for (final card in player.hand) {
        removeOnce(card);
      }
    }
    for (final card in discard) {
      removeOnce(card);
    }

    if (deck.isEmpty) {
      throw const FormatException(
        'Deck par défaut vide (cartes injectées incohérentes).',
      );
    }
    return deck;
  }
}

class _CliConfig {
  final bool help;
  final _RunMode runMode;
  final String botName;
  final BotSkillLevel botSkill;
  final BotBehavior botBehavior;
  final List<PlayingCard> botHand;
  final List<int> botKnownIndices;
  final List<String?>? botMentalValues;
  final List<_OpponentSpec> opponents;
  final List<PlayingCard> discard;
  final List<PlayingCard>? deck;
  final PlayingCard? drawCard;
  final int turnCount;
  final int actionCount;
  final bool showTable;
  final List<int> valetUncertaintyIndices;
  final String? activatePowerValue;
  final List<_ObservedActionSpec> observedActions;

  const _CliConfig({
    required this.help,
    required this.runMode,
    required this.botName,
    required this.botSkill,
    required this.botBehavior,
    required this.botHand,
    required this.botKnownIndices,
    required this.botMentalValues,
    required this.opponents,
    required this.discard,
    required this.deck,
    required this.drawCard,
    required this.turnCount,
    required this.actionCount,
    required this.showTable,
    required this.valetUncertaintyIndices,
    required this.activatePowerValue,
    required this.observedActions,
  });

  factory _CliConfig.fromArgs(List<String> args) {
    final help = args.contains('--help') || args.contains('-h');
    if (help) {
      return const _CliConfig(
        help: true,
        runMode: _RunMode.turn,
        botName: 'BOT',
        botSkill: BotSkillLevel.platinum,
        botBehavior: BotBehavior.balanced,
        botHand: [],
        botKnownIndices: [],
        botMentalValues: null,
        opponents: [],
        discard: [],
        deck: null,
        drawCard: null,
        turnCount: 0,
        actionCount: 0,
        showTable: true,
        valetUncertaintyIndices: [],
        activatePowerValue: null,
        observedActions: [],
      );
    }

    final botHandRaw = _readArgValue(args, '--bot-hand');
    if (botHandRaw == null || botHandRaw.trim().isEmpty) {
      throw const FormatException(
        '--bot-hand est requis (ex: --bot-hand=Rh,7s,2d,Vc)',
      );
    }

    final runMode = _parseRunMode(_readArgValue(args, '--mode') ?? 'turn');
    final botName = _readArgValue(args, '--bot-name') ?? 'BOT';
    final botSkill =
        _parseSkill(_readArgValue(args, '--bot-skill') ?? 'platinum');
    final botBehavior =
        _parseBehavior(_readArgValue(args, '--bot-behavior') ?? 'balanced');

    final botHand = _parseCardList(botHandRaw);
    final botKnownIndices = _parseIndexList(_readArgValue(args, '--bot-known'));
    final botMentalValues =
        _parseMentalValues(_readArgValue(args, '--bot-mental'));

    final opponentsRaw = _readArgValue(args, '--opponents') ??
        'Opp1:gold:Ah,4d,7s,10c|Opp2:human:2h,3d,5c,9s';
    final opponents = _parseOpponents(opponentsRaw);
    if (opponents.isEmpty) {
      throw const FormatException(
        'Il faut au moins un adversaire via --opponents=...',
      );
    }

    final discard = _parseCardList(_readArgValue(args, '--discard') ?? '5c');
    final deckRaw = _readArgValue(args, '--deck');
    final deck = deckRaw == null ? null : _parseCardList(deckRaw);
    final drawRaw = _readArgValue(args, '--draw');
    final drawCard = drawRaw == null ? null : _parseSingleCard(drawRaw);

    final turnCount = _parseInt(_readArgValue(args, '--turn-count'), 8);
    final actionCount = _parseInt(_readArgValue(args, '--action-count'), 24);
    final showTable = _readBoolArg(args, '--show-table', true);
    final valetUncertaintyIndices =
        _parseIndexList(_readArgValue(args, '--valet-unknown'));

    final activatePowerValue =
        _normalizePowerValue(_readArgValue(args, '--activate-power'));
    final observedActions =
        _parseObservedActions(_readArgValue(args, '--observed'));

    return _CliConfig(
      help: false,
      runMode: runMode,
      botName: botName,
      botSkill: botSkill,
      botBehavior: botBehavior,
      botHand: botHand,
      botKnownIndices: botKnownIndices,
      botMentalValues: botMentalValues,
      opponents: opponents,
      discard: discard,
      deck: deck,
      drawCard: drawCard,
      turnCount: turnCount,
      actionCount: actionCount,
      showTable: showTable,
      valetUncertaintyIndices: valetUncertaintyIndices,
      activatePowerValue: activatePowerValue,
      observedActions: observedActions,
    );
  }
}

class _OpponentSpec {
  final String name;
  final bool isHuman;
  final BotSkillLevel skill;
  final List<PlayingCard> hand;

  const _OpponentSpec({
    required this.name,
    required this.isHuman,
    required this.skill,
    required this.hand,
  });
}

class _ObservedActionSpec {
  final String playerName;
  final DiscardActionType actionType;
  final List<PlayingCard> cards;

  const _ObservedActionSpec({
    required this.playerName,
    required this.actionType,
    required this.cards,
  });
}

void _printHelp() {
  stdout.writeln('''
Usage:
  dart run tool/bot_hand_injection_cli.dart --bot-hand=<cards> [options]

Options clés:
  --mode=turn|dutch|power           (défaut: turn)
  --bot-skill=bronze|silver|gold|platinum
  --bot-behavior=balanced|moi|aggressive|fast
  --bot-hand=Rh,7s,2d,Vc            (obligatoire)
  --bot-known=0,2                   indices connus (sinon 0,1 par défaut)
  --bot-mental=R,?,2,?              mémoire exacte injectée (prioritaire)
  --valet-unknown=1,3               marque des inconnues issues d'un Valet
  --opponents=Opp1:gold:Ah,4d,7s,10c|Opp2:human:2h,3d,5c,9s
  --discard=6c,9d                   top = dernière carte
  --deck=Ah,2h,3h                   top = dernière carte
  --draw=Vh                         carte forcée au sommet de la pioche
  --observed='Opp1:drawn:3,2|Opp1:exchange:D,10'
                                    observations publiques pour le tracker
  --activate-power=7|10|V|JOKER     requis si --mode=power
  --turn-count=8 --action-count=24
  --show-table=true|false

Notation cartes:
  valeurs: A,2..10,V,D,R,JOKER
  couleurs: h(hearts), d(diamonds), c(clubs), s(spades)
  exemples: Rh, Rs, 10d, Vc, JOKERh, JOKERs

Exemples:
  dart run tool/bot_hand_injection_cli.dart \\
    --mode=turn \\
    --bot-skill=platinum \\
    --bot-hand='Rh,7s,2d,Vc' \\
    --bot-mental='R,?,2,?' \\
    --valet-unknown=1 \\
    --opponents='Moi:human:Ah,3d,5c,7h|G1:gold:2s,4s,6s,8s' \\
    --discard=6c --draw=Vd

  dart run tool/bot_hand_injection_cli.dart \\
    --mode=dutch \\
    --bot-skill=gold \\
    --bot-hand='Ah,2d,Rh,3c' \\
    --bot-mental='A,2,?,3' \\
    --valet-unknown=2

  dart run tool/bot_hand_injection_cli.dart \\
    --mode=power --activate-power=V \\
    --bot-skill=platinum \\
    --bot-hand='Ah,2d,3c,7s' --bot-mental='A,2,3,7' \\
    --opponents='Opp:human:Ah' \\
    --observed='Opp:drawn:3,2,4|Opp:exchange:D,10'
''');
}

String? _readArgValue(List<String> args, String key) {
  for (final arg in args) {
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  return null;
}

bool _readBoolArg(List<String> args, String key, bool fallback) {
  final value = _readArgValue(args, key);
  if (value == null) return fallback;
  final lower = value.trim().toLowerCase();
  if (lower == '1' || lower == 'true' || lower == 'yes' || lower == 'on') {
    return true;
  }
  if (lower == '0' || lower == 'false' || lower == 'no' || lower == 'off') {
    return false;
  }
  return fallback;
}

int _parseInt(String? raw, int fallback) {
  if (raw == null) return fallback;
  return int.tryParse(raw.trim()) ?? fallback;
}

_RunMode _parseRunMode(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'turn':
      return _RunMode.turn;
    case 'dutch':
      return _RunMode.dutch;
    case 'power':
      return _RunMode.power;
    default:
      throw FormatException('mode inconnu: $raw');
  }
}

BotSkillLevel _parseSkill(String raw) {
  final normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'bronze':
    case 'b':
      return BotSkillLevel.bronze;
    case 'silver':
    case 'argent':
    case 's':
      return BotSkillLevel.silver;
    case 'gold':
    case 'or':
    case 'g':
      return BotSkillLevel.gold;
    case 'platinum':
    case 'platine':
    case 'p':
      return BotSkillLevel.platinum;
    default:
      throw FormatException('niveau inconnu: $raw');
  }
}

BotBehavior _parseBehavior(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'balanced':
    case 'equilibre':
      return BotBehavior.balanced;
    case 'aggressive':
    case 'agressif':
      return BotBehavior.aggressive;
    case 'fast':
    case 'rapide':
      return BotBehavior.fast;
    case 'moi':
      return BotBehavior.moi;
    default:
      throw FormatException('comportement inconnu: $raw');
  }
}

List<int> _parseIndexList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <int>[];
  final result = <int>[];
  for (final token in raw.split(',')) {
    final t = token.trim();
    if (t.isEmpty) continue;
    final idx = int.tryParse(t);
    if (idx == null) {
      throw FormatException('indice invalide: "$t"');
    }
    result.add(idx);
  }
  return result;
}

List<String?>? _parseMentalValues(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final values = <String?>[];
  for (final token in raw.split(',')) {
    final t = token.trim();
    if (t.isEmpty || t == '?' || t.toLowerCase() == 'x') {
      values.add(null);
      continue;
    }
    values.add(_normalizeValueToken(t));
  }
  return values;
}

List<_OpponentSpec> _parseOpponents(String raw) {
  final parts = raw
      .split('|')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  final opponents = <_OpponentSpec>[];

  for (int i = 0; i < parts.length; i++) {
    final section = parts[i];
    final chunks = section.split(':');
    if (chunks.length < 3) {
      throw FormatException(
        'adversaire invalide "$section" (format: nom:type:main)',
      );
    }

    final name = chunks.first.trim().isEmpty ? 'Opp${i + 1}' : chunks.first;
    final type = chunks[1].trim().toLowerCase();
    final cardsRaw = chunks.sublist(2).join(':');
    final hand = _parseCardList(cardsRaw);
    final isHuman = type == 'human' || type == 'h';
    final skill = isHuman ? BotSkillLevel.gold : _parseSkill(type);

    opponents.add(
      _OpponentSpec(
        name: name,
        isHuman: isHuman,
        skill: skill,
        hand: hand,
      ),
    );
  }

  return opponents;
}

List<_ObservedActionSpec> _parseObservedActions(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <_ObservedActionSpec>[];
  final sections = raw
      .split('|')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  final result = <_ObservedActionSpec>[];

  for (final section in sections) {
    final chunks = section.split(':');
    if (chunks.length < 3) {
      throw FormatException(
        'observation invalide "$section" (format: joueur:type:cartes)',
      );
    }

    final playerName = chunks.first.trim();
    if (playerName.isEmpty) {
      throw FormatException('observation invalide "$section" (joueur vide)');
    }

    final actionType = _parseObservedActionType(chunks[1].trim());
    final cardsRaw = chunks.sublist(2).join(':');
    final cards = _parseCardList(cardsRaw);

    result.add(
      _ObservedActionSpec(
        playerName: playerName,
        actionType: actionType,
        cards: cards,
      ),
    );
  }

  return result;
}

DiscardActionType _parseObservedActionType(String raw) {
  final t = raw.trim().toLowerCase();
  switch (t) {
    case 'drawn':
    case 'draw':
    case 'discard':
    case 'd':
      return DiscardActionType.drawnDiscard;
    case 'exchange':
    case 'swap':
    case 'e':
      return DiscardActionType.exchangeDiscard;
    case 'match':
    case 'm':
      return DiscardActionType.matchDiscard;
    default:
      throw FormatException('type observation invalide: "$raw"');
  }
}

List<PlayingCard> _parseCardList(String raw) {
  final cards = raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map(_parseSingleCard)
      .toList(growable: false);
  if (cards.isEmpty) {
    throw FormatException('liste de cartes vide: "$raw"');
  }
  return cards;
}

PlayingCard _parseSingleCard(String token) {
  final input = token.trim();
  if (input.isEmpty) {
    throw const FormatException('carte vide');
  }

  final normalized = input
      .replaceAll('♥', 'h')
      .replaceAll('♦', 'd')
      .replaceAll('♣', 'c')
      .replaceAll('♠', 's')
      .replaceAll(' ', '');

  String? value;
  String? suit;

  final separators = ['_', '-', ':', '/'];
  String? selectedSeparator;
  for (final sep in separators) {
    if (normalized.contains(sep)) {
      selectedSeparator = sep;
      break;
    }
  }

  if (selectedSeparator != null) {
    final chunks = normalized.split(selectedSeparator);
    if (chunks.length != 2) {
      throw FormatException('format carte invalide: "$token"');
    }
    value = _normalizeValueToken(chunks[0]);
    suit = _normalizeSuitToken(chunks[1]);
  } else {
    final regex = RegExp(r'^([A-Za-z0-9]+)([hdcsHDCS])$');
    final match = regex.firstMatch(normalized);
    if (match != null) {
      value = _normalizeValueToken(match.group(1)!);
      suit = _normalizeSuitToken(match.group(2)!);
    } else {
      value = _normalizeValueToken(normalized);
      suit = 'hearts';
    }
  }

  return PlayingCard.create(suit, value);
}

String _normalizeValueToken(String raw) {
  final t = raw.trim().toUpperCase();
  if (t == 'A') return 'A';
  if (t == 'V' || t == 'VALET' || t == 'J') return 'V';
  if (t == 'D' || t == 'DAME' || t == 'Q') return 'D';
  if (t == 'R' || t == 'ROI' || t == 'KING' || t == 'K') return 'R';
  if (t == 'JOKER' || t == 'JK') return 'JOKER';

  final n = int.tryParse(t);
  if (n != null && n >= 2 && n <= 10) {
    return '$n';
  }

  throw FormatException('valeur de carte invalide: "$raw"');
}

String _normalizeSuitToken(String raw) {
  final t = raw.trim().toLowerCase();
  switch (t) {
    case 'h':
    case 'heart':
    case 'hearts':
    case 'coeur':
      return 'hearts';
    case 'd':
    case 'diamond':
    case 'diamonds':
    case 'carreau':
      return 'diamonds';
    case 'c':
    case 'club':
    case 'clubs':
    case 'trefle':
      return 'clubs';
    case 's':
    case 'spade':
    case 'spades':
    case 'pique':
      return 'spades';
    default:
      throw FormatException('couleur de carte invalide: "$raw"');
  }
}

String? _normalizePowerValue(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = raw.trim().toUpperCase();
  if (t == '7' || t == '10' || t == 'V' || t == 'JOKER') {
    return t;
  }
  throw FormatException('pouvoir invalide: "$raw"');
}
