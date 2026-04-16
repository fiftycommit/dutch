import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import 'bot_dutch_strategy.dart';

/// Événement de parole / coordination émis par un bot.
/// La couche UI s'abonne au stream [BotGossipService.speeches] pour afficher
/// une bulle au-dessus du bot le temps du [ttl].
enum BotSpeechTone {
  /// Avertissement neutre sur un adversaire (leader, dutch imminent…).
  warning,

  /// Taquinerie ou trash-talk (bot aggressive).
  taunt,

  /// Proposition ou ralliement d'alliance.
  ally,

  /// Gag auto-valorisant (bot fast / bravado).
  bravado,

  /// Bot qui appelle Dutch avec commentaire.
  dutch,
}

/// Une prise de parole d'un bot. Expire via [expiresAt].
class BotSpeech {
  final String speakerId;
  final String speakerName;
  final String text;
  final BotSpeechTone tone;
  final DateTime createdAt;
  final Duration ttl;

  BotSpeech({
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.tone,
    required this.createdAt,
    required this.ttl,
  });

  DateTime get expiresAt => createdAt.add(ttl);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Alliance de bots contre un joueur cible.
/// Tant qu'elle est active, chaque membre boost son threatScore sur la cible
/// ([threatBoost]) lors du choix de cible pour Valet / Joker.
class BotAlliance {
  final Set<String> memberIds;
  final List<String> memberNames;
  final String targetId;
  final String targetName;
  final int declaredAtTurn;
  final int expiresAtTurn;

  const BotAlliance({
    required this.memberIds,
    required this.memberNames,
    required this.targetId,
    required this.targetName,
    required this.declaredAtTurn,
    required this.expiresAtTurn,
  });

  static const double threatBoost = 1.5;

  bool contains(String botId) => memberIds.contains(botId);
  bool isActive(int currentTurn) => currentTurn <= expiresAtTurn;
}

/// Service de méta-communication entre bots.
/// Singleton. Les bots émettent des observations + speeches via [onBotTurn],
/// l'UI s'abonne à [speeches] / [alliance].
class BotGossipService {
  BotGossipService._();
  static final BotGossipService instance = BotGossipService._();

  final ValueNotifier<List<BotSpeech>> speeches =
      ValueNotifier<List<BotSpeech>>(const []);
  final ValueNotifier<BotAlliance?> alliance =
      ValueNotifier<BotAlliance?>(null);

  static const int _cooldownTurnsGlobal = 2;
  static const int _maxSpeechesPerBotPerRound = 3;
  static const Duration _defaultTtl = Duration(milliseconds: 3200);
  static const int _allianceDurationTurns = 5;
  static const int _pendingAllianceExpiryTurns = 2;
  static const double _leaderScoreThreshold = 18.0;
  static const double _dutchWarnScoreThreshold = 8.0;

  int _lastSpeechTurn = -999;
  final Map<String, int> _speechCountByBot = {};
  final Random _rng = Random();

  /// Proposition d'alliance en attente d'accepteur.
  String? _pendingAllianceProposerId;
  String? _pendingAllianceTargetId;
  String? _pendingAllianceTargetName;
  String? _pendingAllianceProposerName;
  int _pendingAllianceExpiresTurn = -1;

  void reset() {
    speeches.value = const [];
    alliance.value = null;
    _lastSpeechTurn = -999;
    _speechCountByBot.clear();
    _pendingAllianceProposerId = null;
    _pendingAllianceTargetId = null;
    _pendingAllianceTargetName = null;
    _pendingAllianceProposerName = null;
    _pendingAllianceExpiresTurn = -1;
  }

  /// Renvoie l'id de la cible d'alliance pour ce bot, ou null si pas concerné.
  String? allianceTargetFor(String botId, int currentTurn) {
    final a = alliance.value;
    if (a == null || !a.isActive(currentTurn)) return null;
    if (!a.contains(botId)) return null;
    return a.targetId;
  }

  /// Hook appelé au début du tour de chaque bot.
  /// - Nettoie l'alliance expirée
  /// - Évalue les observations (leader, dutch imminent)
  /// - Peut émettre une speech et/ou une action d'alliance
  void onBotTurn(Player bot, GameState gs) {
    final currentTurn = gs.turnCount;
    _cleanupActiveSpeeches();
    _maybeExpireAlliance(currentTurn);

    if (bot.botSkillLevel == BotSkillLevel.bronze) {
      // Bronze reste muet — cohérent avec son comportement général.
      return;
    }

    final humans = gs.players.where((p) => p.isHuman).toList();
    final opponents = gs.players.where((p) => p.id != bot.id).toList();
    if (opponents.isEmpty) return;

    final leader = _findLeader(gs, opponents);
    final dutchSuspect = _findDutchSuspect(gs, opponents);

    // 1) Priorité : accepter une alliance en attente dirigée contre un leader crédible
    if (_tryAcceptPendingAlliance(bot, gs, currentTurn)) return;

    // 2) Alerte Dutch si quelqu'un est sous [_dutchWarnScoreThreshold]
    if (dutchSuspect != null) {
      if (_emitSpeech(bot, currentTurn,
          text: _pickDutchWarn(bot, dutchSuspect.name),
          tone: BotSpeechTone.warning)) {
        return;
      }
    }

    // 3) Proposition d'alliance si leader humain dangereux et pas d'alliance active
    if (alliance.value == null &&
        _pendingAllianceProposerId == null &&
        leader != null &&
        leader.isHuman &&
        humans.isNotEmpty) {
      final otherBots = gs.players
          .where((p) => !p.isHuman && p.id != bot.id)
          .toList();
      if (otherBots.isNotEmpty && _rng.nextDouble() < 0.55) {
        _proposeAlliance(bot, leader, currentTurn);
        return;
      }
    }

    // 4) Simple leader callout
    if (leader != null) {
      if (_emitSpeech(bot, currentTurn,
          text: _pickLeaderAlert(bot, leader.name),
          tone: BotSpeechTone.warning)) {
        return;
      }
    }

    // 5) Bravado si bot lui-même est bas
    final ownScore = _ownEstimate(bot, gs);
    if (ownScore < 10 && _rng.nextDouble() < 0.25) {
      _emitSpeech(bot, currentTurn,
          text: _pickBravado(bot), tone: BotSpeechTone.bravado);
    }
  }

  /// Déclaration volontaire de dutch par un bot, avec speech associé.
  void onBotCallsDutch(Player bot, int currentTurn) {
    _emitSpeech(bot, currentTurn,
        text: _pickDutchCall(bot),
        tone: BotSpeechTone.dutch,
        ignoreCooldown: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALLIANCE
  // ═══════════════════════════════════════════════════════════════════════════

  void _proposeAlliance(Player proposer, Player target, int currentTurn) {
    _pendingAllianceProposerId = proposer.id;
    _pendingAllianceProposerName = proposer.name;
    _pendingAllianceTargetId = target.id;
    _pendingAllianceTargetName = target.name;
    _pendingAllianceExpiresTurn = currentTurn + _pendingAllianceExpiryTurns;
    _emitSpeech(proposer, currentTurn,
        text: _pickAllianceProposal(proposer, target.name),
        tone: BotSpeechTone.ally,
        ignoreCooldown: true);
  }

  bool _tryAcceptPendingAlliance(
      Player bot, GameState gs, int currentTurn) {
    if (_pendingAllianceProposerId == null) return false;
    if (_pendingAllianceProposerId == bot.id) return false;
    if (currentTurn > _pendingAllianceExpiresTurn) {
      _clearPendingAlliance();
      return false;
    }
    // Décision simple : 70% de chances d'accepter.
    if (_rng.nextDouble() > 0.7) {
      _clearPendingAlliance();
      _emitSpeech(bot, currentTurn,
          text: _pickAllianceDecline(bot),
          tone: BotSpeechTone.taunt,
          ignoreCooldown: true);
      return true;
    }
    final targetName = _pendingAllianceTargetName!;
    final members = {_pendingAllianceProposerId!, bot.id};
    final memberNames = [
      _pendingAllianceProposerName ?? 'Bot',
      bot.name,
    ];
    alliance.value = BotAlliance(
      memberIds: members,
      memberNames: memberNames,
      targetId: _pendingAllianceTargetId!,
      targetName: targetName,
      declaredAtTurn: currentTurn,
      expiresAtTurn: currentTurn + _allianceDurationTurns,
    );
    _emitSpeech(bot, currentTurn,
        text: _pickAllianceAccept(bot, targetName),
        tone: BotSpeechTone.ally,
        ignoreCooldown: true);
    _clearPendingAlliance();
    if (kDebugMode) {
      debugPrint(
          '🤝 Alliance: ${memberNames.join(" + ")} vs $targetName '
          '(expires turn ${currentTurn + _allianceDurationTurns})');
    }
    return true;
  }

  void _clearPendingAlliance() {
    _pendingAllianceProposerId = null;
    _pendingAllianceProposerName = null;
    _pendingAllianceTargetId = null;
    _pendingAllianceTargetName = null;
    _pendingAllianceExpiresTurn = -1;
  }

  void _maybeExpireAlliance(int currentTurn) {
    final a = alliance.value;
    if (a == null) return;
    if (!a.isActive(currentTurn)) {
      alliance.value = null;
      if (kDebugMode) debugPrint('🤝 Alliance expirée');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OBSERVATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Player? _findLeader(GameState gs, List<Player> candidates) {
    Player? best;
    int bestScore = _leaderScoreThreshold.toInt();
    for (final p in candidates) {
      final score = p.getEstimatedScoreForOpponent(
        discardCount: BotDutchStrategy.discardTracker.getDiscardCount(p.id),
      );
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return best;
  }

  Player? _findDutchSuspect(GameState gs, List<Player> candidates) {
    for (final p in candidates) {
      final score = p.getEstimatedScoreForOpponent(
        discardCount: BotDutchStrategy.discardTracker.getDiscardCount(p.id),
      );
      if (score < _dutchWarnScoreThreshold && p.hand.length <= 3) return p;
    }
    return null;
  }

  int _ownEstimate(Player bot, GameState gs) {
    return bot.getEstimatedScoreForOpponent(
      discardCount: BotDutchStrategy.discardTracker.getDiscardCount(bot.id),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEECH QUEUE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _emitSpeech(
    Player bot,
    int currentTurn, {
    required String text,
    required BotSpeechTone tone,
    bool ignoreCooldown = false,
  }) {
    if (!ignoreCooldown &&
        currentTurn - _lastSpeechTurn < _cooldownTurnsGlobal) {
      return false;
    }
    final count = _speechCountByBot[bot.id] ?? 0;
    if (count >= _maxSpeechesPerBotPerRound) return false;

    final speech = BotSpeech(
      speakerId: bot.id,
      speakerName: bot.name,
      text: text,
      tone: tone,
      createdAt: DateTime.now(),
      ttl: _defaultTtl,
    );
    final next = [...speeches.value.where((s) => !s.isExpired), speech];
    speeches.value = next;
    _lastSpeechTurn = currentTurn;
    _speechCountByBot[bot.id] = count + 1;
    return true;
  }

  void _cleanupActiveSpeeches() {
    final next = speeches.value.where((s) => !s.isExpired).toList();
    if (next.length != speeches.value.length) {
      speeches.value = next;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATES — flaveurs par personnalité
  // ═══════════════════════════════════════════════════════════════════════════

  String _pick(List<String> options) => options[_rng.nextInt(options.length)];

  // ─── Leader alert ───
  // Quand la cible est l'humain : menace sans révéler sa position.
  // Quand la cible est un bot : analyse entre bots.
  String _pickLeaderAlert(Player bot, String target) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    final isHuman = target == 'Vous';
    return _pick(_leaderAlertLines[b]![isHuman]!).replaceAll('\$', target);
  }

  static final _leaderAlertLines =
      <BotBehavior, Map<bool, List<String>>>{
    BotBehavior.aggressive: {
      true: [
        'Toi, te crois pas sorti d\'affaire.',
        'Te planque pas, on sait que t\'es là.',
        'On va te faire regretter tes cartes.',
      ],
      false: [
        '\$ est en tête. On le descend.',
        '\$ joue petit, mais il mène. Plus longtemps.',
        'Arrêtez de rigoler, \$ est devant.',
      ],
    },
    BotBehavior.fast: {
      true: [
        'Faut accélérer les gars, il s\'installe.',
        'Il joue serré, on le lâche pas.',
        'On le laisse pas filer.',
      ],
      false: [
        '\$ mène. Faut accélérer.',
        '\$ s\'échappe, grouillons.',
        'Plus vite, \$ file.',
      ],
    },
    BotBehavior.moi: {
      true: [
        'Je vois ton jeu. Tu vas pas aimer la suite.',
        'Je te connais, ça va pas durer.',
      ],
      false: [
        '\$ joue comme moi. Je sais où il va.',
        '\$ mène, mais je connais le style.',
      ],
    },
    BotBehavior.balanced: {
      true: [
        'Attention les gars, faut serrer le jeu.',
        'On reste concentrés, c\'est pas fini.',
        'On le surveille de près.',
      ],
      false: [
        'Attention à \$, il est bas.',
        '\$ est devant, restez concentrés.',
        '\$ mène la danse.',
      ],
    },
  };

  // ─── Dutch warning ───
  // Humain : menace dissuasive sans confirmer qu'il est bien placé.
  // Bot : coordination entre bots.
  String _pickDutchWarn(Player bot, String target) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    final isHuman = target == 'Vous';
    return _pick(_dutchWarnLines[b]![isHuman]!).replaceAll('\$', target);
  }

  static final _dutchWarnLines =
      <BotBehavior, Map<bool, List<String>>>{
    BotBehavior.aggressive: {
      true: [
        'Ose Dutch, tu le regretteras.',
        'Dutch et c\'est la fin pour toi.',
      ],
      false: [
        '\$ va Dutch, tapez-le !',
        '\$ sent le Dutch, faut réagir.',
      ],
    },
    BotBehavior.fast: {
      true: [
        'J\'te vois venir. Même pas en rêve.',
        'Dutch ? Essaie, on verra.',
      ],
      false: [
        '\$ va Dutch, vite !',
        'Dutch imminent sur \$.',
      ],
    },
    BotBehavior.moi: {
      true: [
        'Je sais ce que tu prépares.',
      ],
      false: [
        '\$ va Dutch. Je le sens.',
      ],
    },
    BotBehavior.balanced: {
      true: [
        'Attention à ce qu\'il prépare.',
        'Il couve quelque chose.',
      ],
      false: [
        '\$ est proche du Dutch.',
        'Attention, \$ peut déclarer.',
      ],
    },
  };

  String _pickAllianceProposal(Player bot, String target) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    return _pick(_allianceProposalLines[b]!).replaceAll('\$', target);
  }

  static final _allianceProposalLines = <BotBehavior, List<String>>{
    BotBehavior.aggressive: [
      'On s\'occupe de \$ ensemble ?',
      'Alliance contre \$, qui me suit ?',
      'On lui règle son compte ?',
    ],
    BotBehavior.fast: [
      'Duo contre \$ ? Go.',
      'On team contre \$.',
    ],
    BotBehavior.moi: [
      'J\'ai un plan. On cible \$.',
    ],
    BotBehavior.balanced: [
      'On se coordonne contre \$ ?',
      'On se concentre sur \$ ?',
    ],
  };

  String _pickAllianceAccept(Player bot, String target) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    return _pick(_allianceAcceptLines[b]!).replaceAll('\$', target);
  }

  static final _allianceAcceptLines = <BotBehavior, List<String>>{
    BotBehavior.aggressive: [
      'Cap. On le défonce.',
      'Avec plaisir.',
      'OK, \$ est mort.',
    ],
    BotBehavior.fast: [
      'Deal. Vite fait.',
      'Validé, on l\'enterre.',
    ],
    BotBehavior.moi: [
      'OK, je m\'aligne.',
    ],
    BotBehavior.balanced: [
      'D\'accord, on le cible.',
      'OK, focus \$.',
    ],
  };

  String _pickAllianceDecline(Player bot) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    return _pick(_allianceDeclineLines[b]!);
  }

  static final _allianceDeclineLines = <BotBehavior, List<String>>{
    BotBehavior.aggressive: [
      'Non. Chacun pour soi.',
      'Tchatche pas, joue.',
    ],
    BotBehavior.fast: ['Non merci.', 'Je solo.'],
    BotBehavior.moi: ['Je préfère observer.'],
    BotBehavior.balanced: ['Pas cette fois.', 'Je gère seul.'],
  };

  String _pickBravado(Player bot) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    return _pick(_bravadoLines[b]!);
  }

  static final _bravadoLines = <BotBehavior, List<String>>{
    BotBehavior.aggressive: [
      'J\'suis bas. Approchez pour voir.',
      'Essayez de me prendre des points.',
    ],
    BotBehavior.fast: [
      'Trop rapide pour vous.',
      'Easy.',
    ],
    BotBehavior.moi: ['Ça sent la victoire.'],
    BotBehavior.balanced: ['Position confortable.', 'Je tiens la corde.'],
  };

  String _pickDutchCall(Player bot) {
    final b = bot.botBehavior ?? BotBehavior.balanced;
    return _pick(_dutchCallLines[b]!);
  }

  static final _dutchCallLines = <BotBehavior, List<String>>{
    BotBehavior.aggressive: ['DUTCH. Bonne chance.', 'Dutch. Démerdez-vous.'],
    BotBehavior.fast: ['Dutch. Next.', 'Dutch.'],
    BotBehavior.moi: ['Dutch. Calcul terminé.'],
    BotBehavior.balanced: ['Je déclare Dutch.', 'Dutch. J\'assume.'],
  };
}
