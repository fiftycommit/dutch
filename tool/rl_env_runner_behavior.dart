// Runner comportemental eval-only pour Dutch'78 RL.
//
// Copie isolée temporaire de `tool/rl_env_runner.dart`, utilisée uniquement pour
// l'audit comportemental V2. Ne pas compiler vers `tool/rl_env_runner` et ne pas
// utiliser pour l'entraînement. Les règles, actions, rewards et observations
// restent identiques au runner principal ; seul un champ `diagnostics` optionnel
// est ajouté aux messages quand `eval_diagnostics: true` est passé au reset.
//
// Compilation prévue :
//   dart compile exe tool/rl_env_runner_behavior.dart -o /tmp/rl_env_runner_behavior
//
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
import 'package:dutch_game/models/playing_card.dart';
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
// Reward terminale — bonus de victoire (« pari sportif »).
// ════════════════════════════════════════════════════════════════════════════
// Le bonus n'est versé QUE si le siège RL finit 1er (rank==1) et récompense
// l'ampleur de la victoire (écart de score avec le 2e). Il reste strictement
// borné pour ne JAMAIS dominer le signal rang : `principal` saute d'au moins
// 2/(n-1) = 0.4 (cas le plus serré, n=6) entre gagner et finir 2e, donc avec
// BONUS_MAX=0.30 < 0.40, gagner domine toujours, quel que soit l'écart.
//   gap     = scores_triés_asc[1] - scores_triés_asc[0]  (>= 0 ; =0 si ex-aequo 1er)
//   bonus   = kBonusMax * min(1.0, gap / kGapSat)
// Calibrage kGapSat=20 : entre la moyenne (~11) et le p90 (~29) des écarts
// observés (mesure réelle 360 parties). Une victoire écrasante sature à 0.30.
const double kBonusMax = 0.30;
const double kGapSat = 20.0;

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
  const EvalPlayerConfig({
    this.numPlayers,
    this.behavior,
    this.skill,
    this.evalDiagnostics = false,
  });
  final int? numPlayers;
  final BotBehavior? behavior;
  final BotSkillLevel? skill;
  final bool evalDiagnostics;
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
  var evalDiagnostics = false;
  if (options.containsKey('eval_diagnostics')) {
    final v = options['eval_diagnostics'];
    if (v is! bool) {
      throw FormatException(
          'eval_diagnostics doit être un booléen, reçu: $v');
    }
    evalDiagnostics = v;
  }

  return EvalPlayerConfig(
    numPlayers: n,
    behavior: beh,
    skill: sk,
    evalDiagnostics: evalDiagnostics,
  );
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
    this.evalDiagnostics = false,
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

  /// Éval comportementale uniquement : expose des diagnostics privilégiés dans
  /// le message NDJSON, jamais dans l'observation vectorisée.
  final bool evalDiagnostics;

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

  // Diagnostics eval-only V3. Les signatures de cartes sont `value|suit|points` :
  // elles aident à auditer les décisions sans prétendre identifier parfaitement
  // une carte physique entre deux cartes identiques.
  final Map<int, String> _p0SeenSlotSig = <int, String>{};
  final Set<String> _p0EverSeenCardSig = <String>{};
  final Set<String> _agentTargetedOpponents = <String>{};
  Map<String, dynamic>? _lastActionDiagnostics;
  int _p0CardsChangedByOpponents = 0;
  int _p0KnownCardInvalidatedByOpponent = 0;
  int _p0MemoryDisruptionCount = 0;
  int _opponentActionsHurtingP0ScoreCount = 0;
  int _opponentActionsHelpingP0ScoreCount = 0;
  int _agentPowerUses = 0;
  int _agentOffensiveActions = 0;
  int _agentDecisionCount = 0;

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
    _resetEvalDiagnostics();
    _initEvalMemory();
    return _advanceToRlOrTerminal();
  }

  void _resetEvalDiagnostics() {
    _p0SeenSlotSig.clear();
    _p0EverSeenCardSig.clear();
    _agentTargetedOpponents.clear();
    _lastActionDiagnostics = null;
    _p0CardsChangedByOpponents = 0;
    _p0KnownCardInvalidatedByOpponent = 0;
    _p0MemoryDisruptionCount = 0;
    _opponentActionsHurtingP0ScoreCount = 0;
    _opponentActionsHelpingP0ScoreCount = 0;
    _agentPowerUses = 0;
    _agentOffensiveActions = 0;
    _agentDecisionCount = 0;
  }

  void _initEvalMemory() {
    for (var i = 0; i < _rlSeat.hand.length; i++) {
      final known = i < _rlSeat.knownCards.length && _rlSeat.knownCards[i];
      if (known) {
        _markP0SlotSeen(i, _rlSeat.hand[i]);
      }
    }
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

  String _cardSig(PlayingCard c) => '${c.value}|${c.suit}|${c.points}';

  Map<String, dynamic> _cardDiag(PlayingCard? c) {
    if (c == null) return <String, dynamic>{};
    return {
      'value': c.value,
      'suit': c.suit,
      'points': c.points,
      'is_special': c.isSpecial,
      'sig': _cardSig(c),
    };
  }

  void _markP0SlotSeen(int index, PlayingCard card) {
    final sig = _cardSig(card);
    _p0SeenSlotSig[index] = sig;
    _p0EverSeenCardSig.add(sig);
  }

  Map<String, int> _scoreMap() => {
        for (final p in _players.where((p) => !p.isSpectator))
          p.id: _gs.getFinalScore(p),
      };

  List<String> _p0HandSigs() => [for (final c in _rlSeat.hand) _cardSig(c)];

  int _p0ValidKnownSlotCount() {
    var count = 0;
    for (final e in _p0SeenSlotSig.entries) {
      final i = e.key;
      if (i >= 0 && i < _rlSeat.hand.length && _cardSig(_rlSeat.hand[i]) == e.value) {
        count++;
      }
    }
    return count;
  }

  int? _bestSwapTargetIndex(PlayingCard? drawn) {
    if (drawn == null || _rlSeat.hand.isEmpty) return null;
    var bestIndex = 0;
    var bestDelta = drawn.points - _rlSeat.hand[0].points;
    for (var i = 1; i < _rlSeat.hand.length; i++) {
      final delta = drawn.points - _rlSeat.hand[i].points;
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int _p0StaleKnownSlotCount() {
    var count = 0;
    for (final e in _p0SeenSlotSig.entries) {
      final i = e.key;
      if (i >= 0 && i < _rlSeat.hand.length && _cardSig(_rlSeat.hand[i]) != e.value) {
        count++;
      }
    }
    return count;
  }

  int _p0EverSeenCurrentHandCount() {
    return _rlSeat.hand.where((c) => _p0EverSeenCardSig.contains(_cardSig(c))).length;
  }

  int _p0KnownRealScoreSum() {
    var sum = 0;
    for (final e in _p0SeenSlotSig.entries) {
      final i = e.key;
      if (i >= 0 && i < _rlSeat.hand.length && _cardSig(_rlSeat.hand[i]) == e.value) {
        sum += _rlSeat.hand[i].points;
      }
    }
    return sum;
  }

  int _p0KnownBelievedScoreSum() {
    var sum = 0;
    for (var i = 0; i < _rlSeat.mentalMap.length && i < _rlSeat.hand.length; i++) {
      final card = _rlSeat.mentalMap[i];
      if (card != null) sum += card.points;
    }
    return sum;
  }

  int _bestPossibleSwapDelta(PlayingCard drawn) {
    if (_rlSeat.hand.isEmpty) return 0;
    return _rlSeat.hand.map<int>((c) => drawn.points - c.points).reduce(min);
  }

  Map<String, dynamic> _p0Snapshot() => {
        'score': _gs.getFinalScore(_rlSeat),
        'hand': _p0HandSigs(),
        'valid_known': _p0ValidKnownSlotCount(),
      };

  void _recordOpponentP0Delta(
    Map<String, dynamic> before,
    String actor,
    String kind,
  ) {
    final beforeHand = (before['hand'] as List).cast<String>();
    final afterHand = _p0HandSigs();
    final beforeScore = before['score'] as int;
    final afterScore = _gs.getFinalScore(_rlSeat);
    var changed = beforeHand.length != afterHand.length;
    final len = min(beforeHand.length, afterHand.length);
    for (var i = 0; i < len; i++) {
      if (beforeHand[i] != afterHand[i]) {
        changed = true;
        if (_p0SeenSlotSig[i] == beforeHand[i]) {
          _p0KnownCardInvalidatedByOpponent++;
          _p0SeenSlotSig.remove(i);
        }
      }
    }
    if (!changed) return;
    _p0CardsChangedByOpponents++;
    _p0MemoryDisruptionCount++;
    final delta = afterScore - beforeScore;
    if (delta > 0) _opponentActionsHurtingP0ScoreCount++;
    if (delta < 0) _opponentActionsHelpingP0ScoreCount++;
    _lastActionDiagnostics = {
      'actor': actor,
      'kind': kind,
      'self_score_before': beforeScore,
      'self_score_after': afterScore,
      'self_score_delta': delta,
      'opponent_score_deltas': <String, dynamic>{},
      'p0_hand_changed_by_opponent': true,
      'p0_known_invalidated_by_opponent': true,
      'p0_memory_disrupted': true,
    };
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
        if (_gs.drawnCard != null) {
          _p0EverSeenCardSig.add(_cardSig(_gs.drawnCard!));
          _lastActionDiagnostics = {
            'actor': _rlSeat.id,
            'kind': 'continue_draw',
            'drawn_card': _cardDiag(_gs.drawnCard),
            'self_score_before': _gs.getFinalScore(_rlSeat),
            'self_score_after': _gs.getFinalScore(_rlSeat),
            'self_score_delta': 0,
            'opponent_score_deltas': <String, dynamic>{},
            'p0_hand_changed_by_opponent': false,
            'p0_known_invalidated_by_opponent': false,
            'p0_memory_disrupted': false,
          };
        }
        if (_isTerminal()) return _finalize();
        _micro = RlMicroPhase.postDraw;
        return _observation();

      case RlMicroPhase.postDraw:
        if (kind == 'discard_drawn') {
          final beforeScore = _gs.getFinalScore(_rlSeat);
          final drawn = _gs.drawnCard;
          final validKnownBefore = _p0ValidKnownSlotCount();
          final unknownBefore = _rlSeat.hand.length - validKnownBefore;
          final bestTarget = _bestSwapTargetIndex(drawn);
          final bestTargetKnown = bestTarget != null &&
              _p0SeenSlotSig[bestTarget] == _cardSig(_rlSeat.hand[bestTarget]);
          final bestDelta = drawn == null ? null : _bestPossibleSwapDelta(drawn);
          final bestInfoDelta = unknownBefore > 0 ? 1 : 0;
          GameLogic.discardDrawnCard(_gs);
          _lastActionDiagnostics = {
            'actor': _rlSeat.id,
            'kind': 'discard_drawn',
            'drawn_card': _cardDiag(drawn),
            'self_score_before': beforeScore,
            'self_score_after': _gs.getFinalScore(_rlSeat),
            'self_score_delta': _gs.getFinalScore(_rlSeat) - beforeScore,
            'opponent_score_deltas': <String, dynamic>{},
            'best_possible_swap_delta': bestDelta,
            'discarded_drawn_improvement_if_swapped': bestDelta,
            'unknown_slots_available_before': unknownBefore > 0,
            'discard_drawn_would_reduce_uncertainty': bestInfoDelta > 0,
            'discard_drawn_best_target_slot_known_status': bestTargetKnown,
            'discard_drawn_best_target_delta_score': bestDelta,
            'discard_drawn_best_target_info_delta': bestInfoDelta,
            'discard_drawn_good_score_or_info_opportunity':
                (bestDelta != null && bestDelta < 0) || bestInfoDelta > 0,
            'p0_hand_changed_by_opponent': false,
            'p0_known_invalidated_by_opponent': false,
            'p0_memory_disrupted': false,
          };
        } else {
          final index = params['index'] as int;
          final beforeScore = _gs.getFinalScore(_rlSeat);
          final drawn = _gs.drawnCard;
          final validKnownBefore = _p0ValidKnownSlotCount();
          final knownBefore = validKnownBefore;
          final unknownBefore = _rlSeat.hand.length - validKnownBefore;
          final replaced = index >= 0 && index < _rlSeat.hand.length
              ? _rlSeat.hand[index]
              : null;
          final bestDeltaBefore = drawn == null ? null : _bestPossibleSwapDelta(drawn);
          final replaceKnownNow = index >= 0 &&
              index < _rlSeat.knownCards.length &&
              _rlSeat.knownCards[index];
          final replaceCurrentSeen = replaced != null &&
              _p0SeenSlotSig[index] == _cardSig(replaced);
          final replaceEverSeen = replaced != null &&
              _p0EverSeenCardSig.contains(_cardSig(replaced));
          GameLogic.replaceCard(_gs, index);
          if (drawn != null && index >= 0 && index < _rlSeat.hand.length) {
            _markP0SlotSeen(index, drawn);
          }
          final afterScore = _gs.getFinalScore(_rlSeat);
          final validKnownAfter = _p0ValidKnownSlotCount();
          final knownAfter = validKnownAfter;
          final unknownAfter = _rlSeat.hand.length - validKnownAfter;
          final infoDelta = validKnownAfter - validKnownBefore;
          final infoClass = replaceCurrentSeen && infoDelta == 0
              ? 'known_to_known'
              : replaceCurrentSeen && infoDelta < 0
                  ? 'known_to_unknown'
                  : !replaceCurrentSeen && infoDelta > 0
                      ? 'unknown_to_known'
                      : 'unknown_to_unknown';
          _lastActionDiagnostics = {
            'actor': _rlSeat.id,
            'kind': 'replace',
            'drawn_card': _cardDiag(drawn),
            'replaced_card': _cardDiag(replaced),
            'replaced_index': index,
            'replace_known_now': replaceKnownNow,
            'replaced_slot_known_now': replaceKnownNow,
            'replace_current_card_seen_by_agent': replaceCurrentSeen,
            'replaced_slot_current_card_seen_by_agent': replaceCurrentSeen,
            'replace_ever_seen_by_agent': replaceEverSeen,
            'replaced_slot_ever_seen_by_agent': replaceEverSeen,
            'self_score_before': beforeScore,
            'self_score_after': afterScore,
            'self_score_delta': afterScore - beforeScore,
            'opponent_score_deltas': <String, dynamic>{},
            'best_possible_swap_delta': bestDeltaBefore,
            'known_slot_count_before': knownBefore,
            'known_slot_count_after': knownAfter,
            'valid_known_slot_count_before': validKnownBefore,
            'valid_known_slot_count_after': validKnownAfter,
            'unknown_slot_count_before': unknownBefore,
            'unknown_slot_count_after': unknownAfter,
            'drawn_card_known_by_agent': drawn != null,
            'swap_information_delta': infoDelta,
            'swap_reduced_uncertainty': infoDelta > 0,
            'swap_increased_uncertainty': infoDelta < 0,
            'swap_kept_uncertainty_same': infoDelta == 0,
            'swap_information_class': infoClass,
            'p0_hand_changed_by_opponent': false,
            'p0_known_invalidated_by_opponent': false,
            'p0_memory_disrupted': false,
          };
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
        _agentDecisionCount++;
        _micro = RlMicroPhase.dutchOrDraw;
        return _observation();
      }

      // Tour bot complet : adversaire, ou siège RL en frozenBotMode (tests).
      _guard++;
      final beforeBot = identical(cur, _rlSeat) ? null : _p0Snapshot();
      final broke = await _playBotTurn(cur);
      if (beforeBot != null) {
        _recordOpponentP0Delta(beforeBot, cur.id, 'bot_turn');
      }
      if (broke) break;
      final beforeReaction = _p0Snapshot();
      await _runReactionPhase();
      _recordOpponentP0Delta(beforeReaction, 'opponents', 'reaction_phase');
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
    final beforeReaction = _p0Snapshot();
    await _runReactionPhase();
    _recordOpponentP0Delta(beforeReaction, 'opponents', 'reaction_phase');
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
    final beforeSelfScore = _gs.getFinalScore(_rlSeat);
    final beforeScores = _scoreMap();
    String? targetSeat;
    switch (kind) {
      case 'skip_power':
        break;
      case 'power7_look':
        final i = params['index'] as int;
        GameLogic.lookAtCard(_gs, _rlSeat, i);
        // Connaissance légitime de sa propre carte (cf. _usePower7).
        _rlSeat.updateMentalMap(i, _rlSeat.hand[i]);
        _markP0SlotSeen(i, _rlSeat.hand[i]);
        break;
      case 'power10_spy':
        final t = _seat(params['target_seat'] as String);
        final i = params['index'] as int;
        targetSeat = t.id;
        GameLogic.lookAtCard(_gs, t, i);
        // Mémoire d'espionnage légitime (cf. _usePower10).
        _rlSeat.rememberSpiedCard(t.id, i, t.hand[i]);
        _p0EverSeenCardSig.add(_cardSig(t.hand[i]));
        break;
      case 'powerV_swap':
        final t = _seat(params['target_seat'] as String);
        targetSeat = t.id;
        final ownIndex = params['own_index'] as int;
        final targetIndex = params['target_index'] as int;
        final targetKnown = _rlSeat.getSpiedCards(t.id)?[targetIndex];
        GameLogic.swapCards(
            _gs, _rlSeat, ownIndex, t, targetIndex);
        if (targetKnown != null) {
          _markP0SlotSeen(ownIndex, targetKnown);
        } else {
          _p0SeenSlotSig.remove(ownIndex);
        }
        break;
      case 'powerJoker':
        final t = _seat(params['target_seat'] as String);
        targetSeat = t.id;
        GameLogic.jokerEffect(_gs, t);
        break;
    }
    if (kind != 'skip_power') {
      _agentPowerUses++;
      if (targetSeat != null && targetSeat != _rlSeat.id) {
        _agentOffensiveActions++;
        _agentTargetedOpponents.add(targetSeat);
      }
    }
    final afterScores = _scoreMap();
    final opponentDeltas = <String, int>{};
    for (final e in afterScores.entries) {
      if (e.key == _rlSeat.id) continue;
      opponentDeltas[e.key] = e.value - (beforeScores[e.key] ?? e.value);
    }
    final afterSelfScore = _gs.getFinalScore(_rlSeat);
    _lastActionDiagnostics = {
      'actor': _rlSeat.id,
      'kind': kind,
      'target_seat': targetSeat,
      'self_score_before': beforeSelfScore,
      'self_score_after': afterSelfScore,
      'self_score_delta': afterSelfScore - beforeSelfScore,
      'opponent_score_deltas': opponentDeltas,
      'p0_hand_changed_by_opponent': false,
      'p0_known_invalidated_by_opponent': false,
      'p0_memory_disrupted': false,
    };
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

  Map<String, dynamic> _buildDiagnostics() {
    final active = _players.where((p) => !p.isSpectator).toList();
    final scores = {
      for (final p in active) p.id: _gs.getFinalScore(p),
    };
    final handSizes = {
      for (final p in active) p.id: p.hand.length,
    };
    final selfScore = scores[_rlSeat.id] ?? _gs.getFinalScore(_rlSeat);
    final opponentScores = {
      for (final p in active)
        if (!identical(p, _rlSeat)) p.id: scores[p.id]!,
    };
    final bestOpponentScore = opponentScores.values.isEmpty
        ? null
        : opponentScores.values.reduce(min);
    final sortedScores = scores.values.toList()..sort();
    final numPlayersActive = active.length;
    final topHalfCutoff = (numPlayersActive / 2).ceil();

    // Rang naturel compétitif : 1 + nombre de scores strictement inférieurs.
    // Les égalités partagent donc le même rang naturel.
    final naturalRank =
        1 + scores.values.where((score) => score < selfScore).length;
    final topHalfNow = naturalRank <= topHalfCutoff;
    final wouldBeFirst = naturalRank == 1;
    final strictlyBetterOpponents =
        opponentScores.values.where((score) => score < selfScore).length;
    final tiedBestWithAgent = wouldBeFirst &&
        opponentScores.values.any((score) => score == selfScore);

    final dutchLegal = _gs.dutchCallerId == null;
    final dutchMargin = bestOpponentScore == null
        ? null
        : bestOpponentScore - selfScore;
    final dutchWouldWin = dutchMargin == null ? false : dutchMargin >= 0;
    final dutchRankIfCalled = dutchWouldWin ? 1 : numPlayersActive;
    final dutchTopHalfIfCalled = dutchRankIfCalled <= topHalfCutoff;
    final validKnown = _p0ValidKnownSlotCount();
    final staleKnown = _p0StaleKnownSlotCount();
    final everSeenCurrent = _p0EverSeenCurrentHandCount();
    final knownRealScore = _p0KnownRealScoreSum();
    final knownBelievedScore = _p0KnownBelievedScoreSum();
    final knownTotal = validKnown + staleKnown;
    final memoryAccuracy = knownTotal == 0 ? null : validKnown / knownTotal;
    final fullTableRoundsCompleted = numPlayersActive == 0
        ? 0
        : _gs.actionCount ~/ numPlayersActive;
    final playersActedAtLeastOnce = min(_gs.actionCount, numPlayersActive);
    final actionsSinceRoundStart = numPlayersActive == 0
        ? 0
        : _gs.actionCount % numPlayersActive;
    final maturityBucket = fullTableRoundsCompleted < 1
        ? 'early'
        : fullTableRoundsCompleted < 2
            ? 'mid'
            : 'late';
    final handSizeP0 = _rlSeat.hand.length;
    final unknownSlotCountP0 = handSizeP0 - validKnown;
    final knownHandFraction =
        handSizeP0 == 0 ? 0.0 : validKnown / handSizeP0;
    final fullHandKnown = handSizeP0 > 0 && validKnown == handSizeP0;
    final partialHandKnown = knownHandFraction >= 0.5 && !fullHandKnown;
    final lowHandKnown = knownHandFraction < 0.5;

    return {
      'self_score_real': selfScore,
      'opponent_scores_real': opponentScores,
      'all_scores_real': scores,
      'scores_sorted_real': sortedScores,
      'best_opponent_score_real': bestOpponentScore,
      'num_players_active': numPlayersActive,
      'hand_sizes': handSizes,
      'natural_rank_now': naturalRank,
      'top_half_cutoff': topHalfCutoff,
      'top_half_now': topHalfNow,
      'would_be_top_half_if_round_ended_now': topHalfNow,
      'would_be_first_if_round_ended_now': wouldBeFirst,
      'dutch_legal_now': dutchLegal,
      'dutch_margin_now': dutchMargin,
      'dutch_would_win_now': dutchWouldWin,
      'dutch_rank_if_called_now': dutchRankIfCalled,
      'dutch_top_half_if_called_now': dutchTopHalfIfCalled,
      'strictly_better_opponents_count': strictlyBetterOpponents,
      'tied_best_with_agent': tiedBestWithAgent,
      'agent_decision_count': _agentDecisionCount,
      'table_round_index': fullTableRoundsCompleted,
      'full_table_rounds_completed': fullTableRoundsCompleted,
      'players_acted_at_least_once_count': playersActedAtLeastOnce,
      'actions_since_round_start': actionsSinceRoundStart,
      'maturity_bucket': maturityBucket,
      'hand_size_p0': handSizeP0,
      'unknown_slot_count_p0': unknownSlotCountP0,
      'known_hand_fraction_p0': knownHandFraction,
      'p0_full_hand_known': fullHandKnown,
      'p0_partial_hand_known': partialHandKnown,
      'p0_low_hand_known': lowHandKnown,
      'memory_valid_known_slot_count': validKnown,
      'memory_stale_known_slot_count': staleKnown,
      'memory_current_card_seen_count': validKnown,
      'memory_ever_seen_current_hand_count': everSeenCurrent,
      'memory_truth_accuracy': memoryAccuracy,
      'known_real_score_sum': knownRealScore,
      'known_believed_score_sum': knownBelievedScore,
      'score_estimate_error_valid_known_only':
          (knownBelievedScore - knownRealScore).abs(),
      'score_estimate_error_all_hand':
          (_rlSeat.getKnownScore() - selfScore).abs(),
      'last_action_diagnostics': _lastActionDiagnostics,
      'episode_diagnostics': {
        'p0_cards_changed_by_opponents': _p0CardsChangedByOpponents,
        'p0_known_card_invalidated_by_opponent':
            _p0KnownCardInvalidatedByOpponent,
        'p0_memory_disruption_count': _p0MemoryDisruptionCount,
        'opponent_actions_hurting_p0_score_count':
            _opponentActionsHurtingP0ScoreCount,
        'opponent_actions_helping_p0_score_count':
            _opponentActionsHelpingP0ScoreCount,
        'agent_power_uses': _agentPowerUses,
        'agent_offensive_actions': _agentOffensiveActions,
        'agent_targets_unique_opponents': _agentTargetedOpponents.length,
      },
    };
  }

  Map<String, dynamic> _observation() {
    _updateDestabSignal();
    final msg = {
      'type': 'observation',
      'episode_id': episodeId,
      'step': _step++,
      'done': false,
      // `reward` (scalaire historique) = composante principale (0 hors terminal).
      'reward': 0.0,
      // Composantes brutes, NON combinées (Python compose la reward finale).
      // `win_bonus` n'existe qu'au terminal (cf. _finalize) ; 0 ici.
      'rewards': {'principal': 0.0, 'destab': _curDestabReward, 'win_bonus': 0.0},
      // Debug du proxy dynamique (visible quand il change d'identité).
      'proxy_seat': _curProxyId,
      'proxy_threat': _curProxyThreat,
      'micro_phase': _micro.name,
      'obs': _buildObservation(),
      'action_mask': _buildMask(),
    };
    if (evalDiagnostics) {
      msg['diagnostics'] = _buildDiagnostics();
    }
    return msg;
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

    // Bonus de victoire : seulement si 1er, proportionnel à l'écart de score
    // avec le 2e (saturé). Sur un ex-aequo au rang 1, les deux meilleurs scores
    // sont égaux => gap=0 => bonus=0 (pas de cas spécial à gérer).
    double winBonus = 0.0;
    if (rank == 1) {
      final scores = [for (final p in _players) _gs.getFinalScore(p)]..sort();
      final gap = scores.length >= 2 ? (scores[1] - scores[0]).toDouble() : 0.0;
      winBonus = kBonusMax * min(1.0, gap / kGapSat);
    }
    final msg = {
      'type': 'observation',
      'episode_id': episodeId,
      'step': _step++,
      'done': true,
      'reward': principal,
      'rewards': {
        'principal': principal,
        'destab': _curDestabReward,
        'win_bonus': winBonus,
      },
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
    if (evalDiagnostics) {
      msg['diagnostics'] = _buildDiagnostics();
    }
    return msg;
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
            evalDiagnostics: cfg.evalDiagnostics,
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
