// Runner RL headless pour Dutch'78 (phase 2 — Reinforcement Learning, v1).
//
// Rôle : exposer une partie Dutch'78 comme un environnement RL piloté par un
// process externe (Python/PPO à venir) via un protocole NDJSON sur stdin/stdout.
// Le moteur Dart (`GameLogic` + modèles) reste la SEULE vérité de jeu : ce
// fichier ne réimplémente aucune règle, il orchestre.
//
// Principes v1 (décisions tranchées avec l'auteur) :
//  - Le siège RL (toujours `players[0]`, id `p0`) n'hérite d'AUCUNE heuristique
//    de bot. Il apprend tout de zéro et ne connaît que les règles du jeu.
//    => En mode RL, on n'appelle JAMAIS sur le siège RL :
//         BotCardStrategy.decideCardAction / BotDutchStrategy.shouldCallDutch /
//         BotPowerHandler.useBotSpecialPower / BotCardStrategy.tryReactionMatch.
//       Ces fonctions restent utilisées normalement pour les ADVERSAIRES
//       (sparring-partners).
//  - Décision D (réaction sur défausse adverse, hors-tour) : TOTALEMENT EXCLUE
//    en v1. Le siège RL ne participe jamais à la phase de réaction en mode RL —
//    ni en l'apprenant, ni via une policy gelée. Il rate donc systématiquement
//    les matchs de réaction. Choix assumé (zéro stratégie codée à la main).
//  - Granularité du step : micro-décisions A (call_dutch / continue_draw),
//    B (discard_drawn / replace), C (use power / skip_power). Tout via les
//    primitives PUBLIQUES de GameLogic — aucune méthode privée de BotPowerHandler.
//  - num_players aléatoire 2..6 par épisode (aligné sur le vrai jeu, UI 2-6).
//  - Reward terminale rang-normalisée : 1 - 2*(rank-1)/(n-1) via
//    GameState.getFinalRanksWithTies(). Steps non terminaux = 0. Aucun shaping.
//  - Anti-leakage structurel : l'observation n'expose que la croyance légitime
//    du siège RL (mentalMap / knownCards / spyMemory) — jamais sa vraie `hand`
//    pour les slots inconnus, jamais une carte adverse non espionnée.
//
// ⚠ frozenBotMode : drapeau RÉSERVÉ AUX TESTS (#5 parité avec le générateur).
//   Quand il est vrai, le siège RL est piloté par la même policy bot que les
//   adversaires (et participe à la réaction), de sorte que le runner reproduit
//   EXACTEMENT `playOneGame` du générateur. Il NE DOIT JAMAIS être activé sur le
//   chemin branché à Python/PPO. main() le laisse toujours à `false`.
//
// Pilotage depuis Python/PPO : utiliser l'EXÉCUTABLE COMPILÉ, jamais `dart run`
// (qui imprime « Running build hooks… » sur stdout et corrompt la 1re ligne
// NDJSON). Cf. documentation/RL_RUNNER.md.
//   dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner
//   ./tool/rl_env_runner [--debug] [--max-turns=N]
//
// Usage dev (tests / mise au point) : dart run tool/rl_env_runner.dart [--debug]
//   puis échanger des messages NDJSON (un objet JSON par ligne) :
//     <- {"type":"reset","seed":42,"episode_id":"ep0","options":{"max_turns":500}}
//     -> {"type":"observation", ...}
//     <- {"type":"action","kind":"continue_draw"}
//     -> {"type":"observation", ...}
//     <- {"type":"close"}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/services/game/engine_random.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/bot_personality.dart';
import 'package:dutch_game/services/game/bot/bot_threat_analyzer.dart';
import 'package:dutch_game/services/game/bot/headless_threat_signal.dart';
import 'package:dutch_game/services/logging/game_logger_service.dart';

/// Micro-phase de décision du siège RL à l'intérieur d'un tour.
enum RlMicroPhase { dutchOrDraw, postDraw, power }

const List<String> _kRanks = [
  'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R',
];

// ════════════════════════════════════════════════════════════════════════════
// Config de joueurs forcée (ÉVAL) : parsing + validation des `options` du reset.
// ════════════════════════════════════════════════════════════════════════════

/// Comportement adverse depuis une chaîne (`fast`/`aggressive`/`balanced`/`moi`).
/// Retourne `null` si inconnu (BotBehavior n'a pas de tryParse, contrairement à
/// BotSkillLevel).
BotBehavior? _parseBotBehavior(String? s) {
  final k = s?.trim().toLowerCase();
  for (final b in BotBehavior.values) {
    if (b.name == k) return b;
  }
  return null;
}

/// Config de joueurs validée, extraite des `options` du message reset.
/// Tous les champs null => chemin par défaut (tirage aléatoire dans le runner).
class EvalPlayerConfig {
  const EvalPlayerConfig({this.numPlayers, this.behavior, this.skill});
  final int? numPlayers;
  final BotBehavior? behavior;
  final BotSkillLevel? skill;
}

/// Parse + valide les `options` d'éval. Lève [FormatException] (message français)
/// si une valeur FOURNIE est invalide ; un champ absent reste null (pas d'erreur).
EvalPlayerConfig parseEvalPlayerConfig(Map<String, dynamic> options) {
  int? n;
  if (options.containsKey('num_players')) {
    final v = options['num_players'];
    if (v is! num || v != v.toInt() || v.toInt() < 2 || v.toInt() > 6) {
      throw FormatException('num_players doit être un entier entre 2 et 6, reçu: $v');
    }
    n = v.toInt();
  }
  BotBehavior? beh;
  BotSkillLevel? sk;
  final opp = options['opponents'];
  if (opp != null) {
    if (opp is! Map) {
      throw FormatException('opponents doit être un objet, reçu: $opp');
    }
    final skRaw = opp['skill'];
    if (skRaw != null) {
      sk = BotSkillLevel.tryParse(skRaw.toString());
      if (sk == null) {
        throw FormatException(
            'skill inconnu: $skRaw (attendu bronze|silver|difficile)');
      }
    }
    final behRaw = opp['behavior'];
    if (behRaw != null) {
      beh = _parseBotBehavior(behRaw.toString());
      if (beh == null) {
        throw FormatException(
            'behavior inconnu: $behRaw (attendu fast|aggressive|balanced|moi)');
      }
    }
  }
  return EvalPlayerConfig(numPlayers: n, behavior: beh, skill: sk);
}

// ════════════════════════════════════════════════════════════════════════════
// Environnement RL : un épisode = une manche Dutch'78.
// ════════════════════════════════════════════════════════════════════════════

class RlEnv {
  RlEnv({
    required this.episodeId,
    this.maxTurns = 500,
    this.frozenBotMode = false,
    this.forcedNumPlayers,
    this.forcedOpponentBehavior,
    this.forcedOpponentSkill,
  });

  final String episodeId;
  final int maxTurns;

  /// ⚠ Tests uniquement (parité générateur). Voir l'entête du fichier.
  final bool frozenBotMode;

  // ── Paramètres d'ÉVAL (réservés au script d'évaluation, hors entraînement) ──
  // Quand TOUS sont null (cas par défaut, y compris entraînement et test de
  // parité #5), `_buildPlayers` emprunte un chemin byte-à-byte identique au
  // générateur. Dès qu'au moins un est fourni, on bascule sur un chemin forcé
  // déterministe (cf. _buildPlayers) qui n'est jamais emprunté par la parité.

  /// Éval : force le nombre de joueurs (2..6) ; null => tirage aléatoire.
  final int? forcedNumPlayers;

  /// Éval : force le comportement des adversaires p1..pn ; null => aléatoire.
  final BotBehavior? forcedOpponentBehavior;

  /// Éval : force le niveau des adversaires p1..pn ; null => aléatoire.
  final BotSkillLevel? forcedOpponentSkill;

  late GameState _gs;
  late List<Player> _players;
  late Player _rlSeat;

  int _guard = 0;
  int _step = 0;
  bool _finished = false;
  RlMicroPhase _micro = RlMicroPhase.dutchOrDraw;
  Map<String, int> _ranks = const {};

  // ── Signal de déstabilisation (Piste 5), proxy STABLE inter-step ───────────
  // Le proxy = leader courant (BotThreatAnalyzer). On ne compare la menace que
  // si le proxy n'a PAS changé d'identité entre t-1 et t ; sinon reward_destab=0
  // (pas de comparaison entre deux joueurs différents) et on réamorce sur le
  // nouveau proxy. Évite toute récompense « gratuite » due au changement de leader.
  String? _prevProxyId; // identité du proxy au step précédent
  double _prevProxyThreat = 0.0; // menace du proxy au step précédent
  String? _curProxyId; // proxy du step courant (debug obs)
  double _curProxyThreat = 0.0; // menace du proxy au step courant (debug obs)
  double _curDestabReward = 0.0; // reward_destab du step courant

  // Accès lecture pour les tests de non-régression.
  GameState get gs => _gs;
  List<Player> get players => _players;
  Player get rlSeat => _rlSeat;
  RlMicroPhase get micro => _micro;
  bool get finished => _finished;
  String? get pendingPowerValue => _gs.specialCardToActivate?.value;

  // ── Cycle de vie ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> reset(int seed) async {
    EngineRandom.seed(seed);
    _buildPlayers();
    _gs = GameLogic.initializeGame(
      players: _players,
      gameMode: GameMode.quick,
      difficulty: Difficulty.medium,
    );
    _gs.phase = GamePhase.playing;
    _rlSeat = _players[0];
    _guard = 0;
    _step = 0;
    _finished = false;
    _ranks = const {};
    _prevProxyId = null;
    _prevProxyThreat = 0.0;
    _curProxyId = null;
    _curProxyThreat = 0.0;
    _curDestabReward = 0.0;
    return _advanceToRlOrTerminal();
  }

  /// Met à jour le signal de déstabilisation (Piste 5) pour l'observation que
  /// l'on s'apprête à émettre. Appelé exactement une fois par message émis
  /// (chaque `_observation()` et chaque `_finalize()`), donc séquentiellement.
  /// Pur / RNG-free (analyzeOpponents + HeadlessThreatSignal ne tirent pas
  /// d'EngineRandom) → ne perturbe ni le déterminisme ni la parité #5.
  void _updateDestabSignal() {
    final proxy = BotThreatAnalyzer.analyzeOpponents(_gs, _rlSeat).leader;
    if (proxy == null) {
      _curProxyId = null;
      _curProxyThreat = 0.0;
      _curDestabReward = 0.0;
      _prevProxyId = null;
      _prevProxyThreat = 0.0;
      return;
    }
    final threat =
        HeadlessThreatSignal.scoreFor(_gs, proxy, BotDutchStrategy.discardTracker);
    double destab;
    if (proxy.id == _prevProxyId) {
      final d = _prevProxyThreat - threat;
      destab = d > 0 ? d : 0.0;
    } else {
      // Changement d'identité du proxy : aucune comparaison entre deux joueurs.
      destab = 0.0;
    }
    _curProxyId = proxy.id;
    _curProxyThreat = threat;
    _curDestabReward = destab;
    _prevProxyId = proxy.id;
    _prevProxyThreat = threat;
  }

  Future<Map<String, dynamic>> step(Map<String, dynamic> msg) async {
    if (_finished) {
      return _error('épisode déjà terminé', code: 'BAD_PHASE', fatal: false);
    }
    final kind = msg['kind'];
    final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (kind is! String || !_legal(kind, params)) {
      return _error('action illégale en phase ${_micro.name}: $kind $params',
          code: 'ILLEGAL_ACTION', fatal: false);
    }

    switch (_micro) {
      case RlMicroPhase.dutchOrDraw:
        if (kind == 'call_dutch') {
          GameLogic.callDutch(_gs);
          return _finalize();
        }
        // continue_draw
        GameLogic.drawCard(_gs);
        if (_isTerminal()) return _finalize();
        _micro = RlMicroPhase.postDraw;
        return _observation();

      case RlMicroPhase.postDraw:
        if (kind == 'discard_drawn') {
          GameLogic.discardDrawnCard(_gs);
        } else {
          GameLogic.replaceCard(_gs, params['index'] as int);
        }
        if (_gs.phase == GamePhase.specialPower) {
          _micro = RlMicroPhase.power;
          return _observation();
        }
        return _completeRlTurnThenAdvance();

      case RlMicroPhase.power:
        _applyPower(kind, params);
        return _completeRlTurnThenAdvance();
    }
  }

  // ── Boucle moteur (miroir fidèle de playOneGame du générateur) ──────────────

  Future<Map<String, dynamic>> _advanceToRlOrTerminal() async {
    while (!_isTerminal() && _guard < maxTurns) {
      final cur = _gs.currentPlayer;
      final isRl = identical(cur, _rlSeat);

      if (isRl && !frozenBotMode) {
        // Début d'un tour du siège RL : on rend la main à Python.
        // NOTE : applyMemoryDecay n'est VOLONTAIREMENT pas appelé sur le siège
        // RL en mode RL — la décroissance mémoire est une imperfection de bot,
        // pas une règle du jeu. Le siège RL garde une mémoire fidèle de ce qu'il
        // a légitimement observé.
        _guard++;
        _micro = RlMicroPhase.dutchOrDraw;
        return _observation();
      }

      // Tour bot complet : adversaire, ou siège RL en frozenBotMode (tests).
      _guard++;
      final broke = await _playBotTurn(cur);
      if (broke) break;
      await _runReactionPhase();
      if (_gs.deck.isEmpty && _gs.discardPile.length <= 1) break;
      GameLogic.nextPlayer(_gs);
    }
    return _finalize();
  }

  /// Reproduit EXACTEMENT le corps de tour de `playOneGame`
  /// (tool/ml_dataset_generator.dart). Retourne true si la manche se termine
  /// pendant ce tour (Dutch annoncé ou plus de cartes à la pioche).
  Future<bool> _playBotTurn(Player bot) async {
    final diff = BotConfig.getDifficulty(bot, null);
    final phaseBot = BotConfig.getBotPhase(bot, _gs);
    final perso = BotPersonality.fromBot(bot);

    BotMemoryManager.applyMemoryDecay(bot, diff, personality: perso);

    if (BotDutchStrategy.shouldCallDutch(_gs, bot, diff, phaseBot,
        personality: perso)) {
      GameLogic.callDutch(_gs);
      return true;
    }

    GameLogic.drawCard(_gs);
    if (_gs.phase == GamePhase.ended || _gs.phase == GamePhase.dutchCalled) {
      return true;
    }

    await BotCardStrategy.decideCardAction(_gs, bot, diff, phaseBot,
        personality: perso);

    if (_gs.phase == GamePhase.specialPower) {
      await BotPowerHandler.useBotSpecialPower(_gs, diff, null,
          personality: perso, skipDelay: true);
      _gs.phase = GamePhase.playing;
      _gs.isWaitingForSpecialPower = false;
      _gs.specialCardToActivate = null;
    }
    return false;
  }

  /// Phase de réaction. Miroir de `_runReactionPhase` du générateur, à une
  /// exception près : en mode RL, le siège RL est EXCLU (décision D exclue).
  /// En frozenBotMode, il participe comme un bot (parité générateur).
  Future<void> _runReactionPhase() async {
    _gs.phase = GamePhase.reaction;
    for (final p in _gs.players) {
      if (p.isHuman) continue;
      // Le siège RL n'apprend ni n'hérite aucune réaction : on le saute en RL.
      if (!frozenBotMode && identical(p, _rlSeat)) continue;
      if (_gs.phase != GamePhase.reaction) break;
      final diff = BotConfig.getDifficulty(p, null);
      final phaseBot = BotConfig.getBotPhase(p, _gs);
      final perso = BotPersonality.fromBot(p);
      await BotCardStrategy.tryReactionMatch(_gs, p, diff, phaseBot,
          personality: perso, skipDelay: true);
    }
    if (_gs.phase == GamePhase.reaction) _gs.phase = GamePhase.playing;
  }

  /// Clôture le tour du siège RL (réaction adverses + passage au joueur suivant)
  /// puis rejoue les adversaires jusqu'à la prochaine décision RL ou la fin.
  Future<Map<String, dynamic>> _completeRlTurnThenAdvance() async {
    await _runReactionPhase();
    if (_gs.deck.isEmpty && _gs.discardPile.length <= 1) return _finalize();
    GameLogic.nextPlayer(_gs);
    return _advanceToRlOrTerminal();
  }

  /// ⚠ TEST-ONLY (non utilisé sur le chemin Python/PPO).
  /// Applique l'action de pouvoir du siège RL SANS dérouler la fin de tour
  /// (réaction adverse + tours suivants). Permet aux tests d'observer l'effet
  /// moteur immédiat d'un pouvoir avant que les adversaires ne rejouent.
  /// Précondition : micro-phase courante == power.
  void applyRlPowerForTest(String kind, Map<String, dynamic> params) {
    assert(_micro == RlMicroPhase.power, 'applyRlPowerForTest hors phase power');
    _applyPower(kind, params);
  }

  // ── Application des pouvoirs du siège RL (primitives publiques) ─────────────

  void _applyPower(String kind, Map<String, dynamic> params) {
    switch (kind) {
      case 'skip_power':
        break;
      case 'power7_look':
        final i = params['index'] as int;
        GameLogic.lookAtCard(_gs, _rlSeat, i);
        // Connaissance légitime de sa propre carte (cf. _usePower7).
        _rlSeat.updateMentalMap(i, _rlSeat.hand[i]);
        break;
      case 'power10_spy':
        final t = _seat(params['target_seat'] as String);
        final i = params['index'] as int;
        GameLogic.lookAtCard(_gs, t, i);
        // Mémoire d'espionnage légitime (cf. _usePower10).
        _rlSeat.rememberSpiedCard(t.id, i, t.hand[i]);
        break;
      case 'powerV_swap':
        final t = _seat(params['target_seat'] as String);
        GameLogic.swapCards(
            _gs, _rlSeat, params['own_index'] as int, t, params['target_index'] as int);
        break;
      case 'powerJoker':
        final t = _seat(params['target_seat'] as String);
        GameLogic.jokerEffect(_gs, t);
        break;
    }
    _gs.phase = GamePhase.playing;
    _gs.isWaitingForSpecialPower = false;
    _gs.specialCardToActivate = null;
  }

  // ── Légalité / masque d'action ─────────────────────────────────────────────

  bool _legal(String kind, Map<String, dynamic> params) {
    switch (_micro) {
      case RlMicroPhase.dutchOrDraw:
        if (kind == 'call_dutch') return _gs.dutchCallerId == null;
        return kind == 'continue_draw';

      case RlMicroPhase.postDraw:
        if (kind == 'discard_drawn') return true;
        if (kind == 'replace') {
          final i = params['index'];
          return i is int && i >= 0 && i < _rlSeat.hand.length;
        }
        return false;

      case RlMicroPhase.power:
        if (kind == 'skip_power') return true;
        final val = _gs.specialCardToActivate?.value;
        if (val == '7' && kind == 'power7_look') {
          final i = params['index'];
          return i is int && i >= 0 && i < _rlSeat.hand.length;
        }
        if (val == '10' && kind == 'power10_spy') {
          final t = _seatOrNull(params['target_seat']);
          final i = params['index'];
          return t != null &&
              !identical(t, _rlSeat) &&
              i is int &&
              i >= 0 &&
              i < t.hand.length;
        }
        if (val == 'V' && kind == 'powerV_swap') {
          final t = _seatOrNull(params['target_seat']);
          final oi = params['own_index'];
          final ti = params['target_index'];
          return t != null &&
              !identical(t, _rlSeat) &&
              oi is int &&
              oi >= 0 &&
              oi < _rlSeat.hand.length &&
              ti is int &&
              ti >= 0 &&
              ti < t.hand.length;
        }
        if (val == 'JOKER' && kind == 'powerJoker') {
          final t = _seatOrNull(params['target_seat']);
          // Joker-sur-soi interdit en v1.
          return t != null && !identical(t, _rlSeat) && t.hand.isNotEmpty;
        }
        return false;
    }
  }

  Map<String, dynamic> _buildMask() {
    switch (_micro) {
      case RlMicroPhase.dutchOrDraw:
        return {
          'call_dutch': _gs.dutchCallerId == null,
          'continue_draw': true,
        };
      case RlMicroPhase.postDraw:
        return {
          'discard_drawn': true,
          'replace': List<bool>.filled(_rlSeat.hand.length, true),
        };
      case RlMicroPhase.power:
        final val = _gs.specialCardToActivate?.value;
        final mask = <String, dynamic>{'skip_power': true};
        if (val == '7') {
          mask['power7_look'] = List<bool>.filled(_rlSeat.hand.length, true);
        } else if (val == '10') {
          mask['power10_spy'] = {
            for (final p in _opponents())
              p.id: List<bool>.filled(p.hand.length, true),
          };
        } else if (val == 'V') {
          mask['powerV_swap'] = {
            'own': List<bool>.filled(_rlSeat.hand.length, true),
            'targets': {
              for (final p in _opponents())
                p.id: List<bool>.filled(p.hand.length, true),
            },
          };
        } else if (val == 'JOKER') {
          mask['powerJoker'] = {
            for (final p in _opponents()) p.id: p.hand.isNotEmpty,
          };
        }
        return mask;
    }
  }

  // ── Observation (anti-leakage : croyance + public, jamais la hand réelle) ───

  Map<String, dynamic> _buildObservation() {
    final bot = _rlSeat;

    // (c) Vue par slot — uniquement mentalMap / knownCards / hints (légitime).
    final slots = <Map<String, dynamic>>[];
    for (var i = 0; i < bot.hand.length; i++) {
      final known = i < bot.knownCards.length && bot.knownCards[i];
      final believed = (known && i < bot.mentalMap.length) ? bot.mentalMap[i] : null;
      final hintAction = bot.getUnknownCardHintAction(i);
      slots.add({
        'known': known,
        'believed_value': believed?.value,
        'believed_points': believed?.points,
        'hint_quality': bot.getUnknownCardHintQuality(i),
        'hint_confidence': bot.getUnknownCardHintConfidence(i),
        'hint_age': hintAction == null ? null : _gs.actionCount - hintAction,
      });
    }

    // (d) Adversaires : public + cartes espionnées seulement.
    final opponents = <Map<String, dynamic>>[];
    for (final p in _opponents()) {
      final spied = bot.getSpiedCards(p.id);
      opponents.add({
        'seat': p.id,
        'hand_size': p.hand.length,
        'memorized_indices': List<int>.from(p.memorizedCardIndices),
        'spied': spied == null
            ? <String, dynamic>{}
            : {
                for (final e in spied.entries)
                  e.key.toString(): {'value': e.value.value, 'points': e.value.points},
              },
        'last_targeted_ago': p.lastTargetedByPowerTurn < 0
            ? null
            : _gs.turnCount - p.lastTargetedByPowerTurn,
      });
    }

    // (b) Agrégats de croyance (esprit _captureSnapshot).
    var bestMatchProb = 0.0;
    for (final r in _kRanks) {
      final pr = BotMemoryManager.getMatchProbability(_gs, bot, r);
      if (pr > bestMatchProb) bestMatchProb = pr;
    }
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    var expectedUnknownSum = 0.0;
    for (final i in unknownIndices) {
      expectedUnknownSum += BotMemoryManager.getUnknownBeliefExpectedValue(_gs, bot, i);
    }
    final doublons = BotMemoryManager.findDoublons(bot);
    final believedKnownScore = bot.getKnownScore();
    final spiedCount =
        bot.spyMemory.values.fold<int>(0, (s, m) => s + m.length);

    // (a) Public de table.
    final top = _gs.topDiscardCard;
    final oppSizes = _opponents().map((p) => p.hand.length).toList();
    final drawn = _gs.drawnCard;

    return {
      // global
      'turn_count': _gs.turnCount,
      'action_count': _gs.actionCount,
      'phase': _gs.phase.toString().split('.').last,
      'micro_phase': _micro.name,
      'num_players': _gs.players.length,
      'seat_index': bot.position,
      'deck_size': _gs.remainingDeckCards,
      'discard_size': _gs.discardPile.length,
      'top_discard_value': top?.value,
      'top_discard_points': top?.points,
      'dutch_called': _gs.dutchCallerId != null,
      'dutch_caller_is_me': _gs.dutchCallerId == bot.id,
      'expected_deck_card_value': BotMemoryManager.getExpectedDeckCardValue(_gs),
      'discarded_ranks': BotMemoryManager.countDiscardedRanks(_gs),
      // carte piochée (visible par le joueur en B/C)
      'drawn_value': drawn?.value,
      'drawn_points': drawn?.points,
      // self — agrégats + slots
      'hand_size': bot.hand.length,
      'known_count': bot.knownCardCount,
      'unknown_count': bot.unknownCardCount,
      'memory_confidence': bot.getMemoryConfidence(),
      'believed_known_score': believedKnownScore,
      'max_known_value': BotMemoryManager.getMaxKnownCardValue(bot),
      'has_doublon': doublons.isNotEmpty,
      'doublon_count': doublons.length,
      'expected_unknown_value_sum': expectedUnknownSum,
      'believed_total_score_estimate': believedKnownScore + expectedUnknownSum,
      'spied_opponent_cards_count': spiedCount,
      'best_match_probability': bestMatchProb,
      'slots': slots,
      // public adverse
      'min_opponent_hand_size': oppSizes.isEmpty ? null : oppSizes.reduce(min),
      'opponents': opponents,
      // identité bot
      'behavior': bot.botBehavior?.toString().split('.').last,
      'skill': bot.botSkillLevel?.toString().split('.').last,
    };
  }

  Map<String, dynamic> _observation() {
    _updateDestabSignal();
    return {
      'type': 'observation',
      'episode_id': episodeId,
      'step': _step++,
      'done': false,
      // `reward` (scalaire historique) = composante principale (0 hors terminal).
      'reward': 0.0,
      // Composantes MORL brutes, NON combinées (Python scalarise avec ses poids).
      'rewards': {'principal': 0.0, 'destab': _curDestabReward},
      // Debug du proxy dynamique (visible quand il change d'identité).
      'proxy_seat': _curProxyId,
      'proxy_threat': _curProxyThreat,
      'micro_phase': _micro.name,
      'obs': _buildObservation(),
      'action_mask': _buildMask(),
    };
  }

  Map<String, dynamic> _finalize() {
    if (!_finished) {
      GameLogic.endGame(_gs);
      _finished = true;
      _ranks = _gs.getFinalRanksWithTies();
    }
    _updateDestabSignal();
    final n = _players.length;
    final rank = _ranks[_rlSeat.id] ?? n;
    final principal = n <= 1 ? 0.0 : 1 - 2 * (rank - 1) / (n - 1);
    return {
      'type': 'observation',
      'episode_id': episodeId,
      'step': _step++,
      'done': true,
      'reward': principal,
      'rewards': {'principal': principal, 'destab': _curDestabReward},
      'proxy_seat': _curProxyId,
      'proxy_threat': _curProxyThreat,
      'info': {
        'final_ranks': _ranks,
        'final_scores': {
          for (final p in _players) p.id: _gs.getFinalScore(p),
        },
        'rank': rank,
        'called_dutch': _gs.dutchCallerId == _rlSeat.id,
        'won': rank == 1,
        'dutch_caller': _gs.dutchCallerId,
        'length': _guard,
      },
    };
  }

  Map<String, dynamic> _error(String message,
      {required String code, required bool fatal}) {
    return {
      'type': 'error',
      'episode_id': episodeId,
      'step': _step,
      'code': code,
      'message': message,
      'fatal': fatal,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _buildPlayers() {
    final rng = EngineRandom.instance;
    final behaviors = BotBehavior.values;
    final skills = BotSkillLevel.values;

    final bool defaultConfig = forcedNumPlayers == null &&
        forcedOpponentBehavior == null &&
        forcedOpponentSkill == null;

    if (defaultConfig) {
      // ════ CHEMIN PAR DÉFAUT — copie EXACTE de buildBots() du générateur. ════
      // NE PAS MODIFIER : même ordre de tirage RNG, condition sine qua non de la
      // parité byte-à-byte du test #5 (entraînement passe aussi par ici).
      final n = 2 + rng.nextInt(5); // {2,3,4,5,6} — aligné sur le vrai jeu (UI 2-6)
      _players = List<Player>.generate(n, (i) {
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
      return;
    }

    // ════ CHEMIN ÉVAL (forcé) — déterministe, AUCUN tirage RNG pour la compo. ════
    // Conséquence assumée : le flux RNG diffère du chemin aléatoire au même seed ;
    // ce chemin n'est JAMAIS emprunté par le test de parité #5 (qui ne fournit
    // aucun paramètre forcé). La reproductibilité éval — même (seed, options) =>
    // même résultat — reste garantie car tout est déterministe ici.
    final n = forcedNumPlayers ?? (2 + rng.nextInt(5));
    _players = List<Player>.generate(n, (i) {
      final BotBehavior behavior;
      final BotSkillLevel skill;
      if (i == 0) {
        // Siège RL : profil neutre fixe, sans effet (Python décide ; _playBotTurn
        // n'est jamais appelé sur p0 hors frozenBotMode).
        behavior = BotBehavior.balanced;
        skill = BotSkillLevel.silver;
      } else {
        // Adversaires p1..pn : profil forcé, ou aléatoire si non spécifié.
        behavior = forcedOpponentBehavior ?? behaviors[rng.nextInt(behaviors.length)];
        skill = forcedOpponentSkill ?? skills[rng.nextInt(skills.length)];
      }
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

  bool _isTerminal() =>
      _gs.phase == GamePhase.ended || _gs.phase == GamePhase.dutchCalled;

  Iterable<Player> _opponents() => _players.where((p) => !identical(p, _rlSeat));

  Player _seat(String id) => _players.firstWhere((p) => p.id == id);

  Player? _seatOrNull(Object? id) {
    if (id is! String) return null;
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Boucle NDJSON : stdin (Python -> Dart) / stdout (Dart -> Python).
// ════════════════════════════════════════════════════════════════════════════

Future<void> _emit(Map<String, dynamic> msg) async {
  // Flush explicite : stdout est bufferisé en mode pipe. Sans ce flush, un pilote
  // interactif (Python/PPO qui envoie une action et attend l'observation) se
  // bloquerait en attente d'une ligne restée dans le tampon Dart.
  stdout.writeln(jsonEncode(msg));
  await stdout.flush();
}

Future<void> main(List<String> args) async {
  // Fuite mémoire headless : sans startNewGame()/reset(), le _logBuffer du
  // GameLoggerService n'est jamais vidé et grossit indéfiniment au fil des
  // tours. On coupe le logging dès l'entrée : toutes les méthodes logXxx
  // court-circuitent sur !_isEnabled, donc plus aucune écriture dans le buffer.
  GameLoggerService.instance.setEnabled(false);

  final debug = args.contains('--debug');
  var maxTurns = 500;
  for (final a in args) {
    final m = RegExp(r'^--max-turns=(\d+)$').firstMatch(a);
    if (m != null) maxTurns = int.parse(m.group(1)!);
  }

  RlEnv? env;
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (e) {
      await _emit({'type': 'error', 'code': 'MALFORMED_JSON', 'message': '$e', 'fatal': false});
      continue;
    }

    final type = msg['type'];
    try {
      switch (type) {
        case 'reset':
          final seed = (msg['seed'] as num).toInt();
          final options = (msg['options'] as Map?)?.cast<String, dynamic>() ?? const {};
          // Options d'éval (num_players / opponents) : validées AVANT construction.
          EvalPlayerConfig cfg;
          try {
            cfg = parseEvalPlayerConfig(options);
          } on FormatException catch (e) {
            await _emit({
              'type': 'error',
              'code': 'INVALID_OPTIONS',
              'message': e.message,
              'fatal': true,
            });
            env = null; // pas d'épisode : empêche un 'action' sur un env périmé
            break;
          }
          // frozenBotMode toujours false ici : réservé aux tests.
          env = RlEnv(
            episodeId: msg['episode_id']?.toString() ?? 'ep',
            maxTurns: (options['max_turns'] as num?)?.toInt() ?? maxTurns,
            forcedNumPlayers: cfg.numPlayers,
            forcedOpponentBehavior: cfg.behavior,
            forcedOpponentSkill: cfg.skill,
          );
          await _emit(await env.reset(seed));
          break;
        case 'action':
          if (env == null) {
            await _emit({'type': 'error', 'code': 'BAD_PHASE', 'message': 'aucun épisode (reset requis)', 'fatal': false});
            break;
          }
          await _emit(await env.step(msg));
          break;
        case 'close':
          return;
        default:
          await _emit({'type': 'error', 'code': 'BAD_PHASE', 'message': 'type inconnu: $type', 'fatal': false});
      }
    } catch (e, st) {
      if (debug) stderr.writeln('INTERNAL: $e\n$st');
      await _emit({'type': 'error', 'code': 'INTERNAL', 'message': '$e', 'fatal': true});
    }
  }
}
