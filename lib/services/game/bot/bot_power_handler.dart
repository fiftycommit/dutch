import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../learning/ai_telemetry_service.dart';
import '../../logging/game_logger_service.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import '../../../widgets/dialogs/shared/unified_power_dialogs.dart';
import '../../../providers/game_provider.dart';
import 'bot_memory_manager.dart';
import 'bot_threat_analyzer.dart';
import 'bot_personality.dart';
import 'human_threat_tracker.dart';

/// Gestion des pouvoirs spéciaux des bots
/// Principe GRASP: Controller - Orchestre l'utilisation des pouvoirs
class BotPowerHandler {
  static final Random _random = Random();
  
  // ═══════════════════════════════════════════════════════════════════════════
  // TÉLÉMÉTRIE : Mesure d'impact des pouvoirs
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Calcule l'avantage de table actuel du bot
  /// Positif = bot devant, Négatif = bot derrière
  static double _calculateTableAdvantage(GameState gs, Player bot) {
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot);
    return report.bestOpponentScore - report.botExpectedScore;
  }

  /// Utilise le pouvoir spécial du bot
  static Future<void> useBotSpecialPower(
    GameState gameState,
    BotDifficulty difficulty,
    BuildContext? context, {
    BotPersonality? personality,
  }) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    String val = gameState.specialCardToActivate!.value;

    final baseDelay = personality != null
        ? (personality.decisionSpeedMs * 0.35).round().clamp(150, 700)
        : 400;
    await Future.delayed(Duration(milliseconds: baseDelay));

    // ═══════════════════════════════════════════════════════════════════════
    // LOGIQUE DÉTERMINISTE : plus de "skip random" !
    // V et JOKER = toujours utilisés (mort subite)
    // 7 et 10 = utilisés si ça apporte de l'info utile
    // ═══════════════════════════════════════════════════════════════════════

    final report = BotThreatAnalyzer.analyzeOpponents(gameState, bot);

    // Détection de menace immédiate
    final hasImmediateThreat =
        report.hasOpponentWithOneCard ||
        report.minOpponentCards <= 2 ||
        (gameState.dutchCallerId != null && gameState.dutchCallerId != bot.id);

    // Pouvoirs offensifs = JAMAIS skip (peuvent retourner la partie)
    final isOffensive = (val == 'V' || val == 'JOKER');

    // ═══════════════════════════════════════════════════════════════════════
    // POUVOIR 10 INTELLIGENT
    // Skip si toutes nos cartes connues sont < 10 (on n'a pas besoin d'info)
    // SAUF si urgence (quelqu'un a 1 carte) → on veut savoir si Dutch est viable
    // ═══════════════════════════════════════════════════════════════════════
    bool shouldUsePower10 = true;
    if (val == '10') {
      final allCardsLow = BotMemoryManager.allKnownCardsBelow(bot, 10);
      final hasUnknownCards = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;

      if (allCardsLow && !hasUnknownCards && !hasImmediateThreat) {
        // Nos cartes sont bonnes, on connaît tout, pas d'urgence → skip
        shouldUsePower10 = false;
      }
    }

    // Pouvoirs d'info = utilisés si ça apporte quelque chose
    final hasUnknown = BotMemoryManager.getUnknownIndices(bot).isNotEmpty;
    final shouldUseInfo = (val == '7' && hasUnknown) || (val == '10' && shouldUsePower10);

    final shouldUsePower = isOffensive || shouldUseInfo || hasImmediateThreat;

    if (!shouldUsePower) {
      _skipPower(gameState, bot);
      return;
    }

    // TÉLÉMÉTRIE : snapshot avantage AVANT le pouvoir
    final advantageBefore = _calculateTableAdvantage(gameState, bot);

    if (val == '7') {
      _usePower7(gameState, bot, difficulty);
    } else if (val == '10') {
      await _usePower10(gameState, bot, difficulty, context, personality: personality);
    } else if (val == 'V') {
      await _usePowerValet(gameState, bot, difficulty, context, personality: personality);
    } else if (val == 'JOKER') {
      await _usePowerJoker(gameState, bot, difficulty, context, personality: personality);
    }

    // TÉLÉMÉTRIE : snapshot avantage APRÈS le pouvoir
    final advantageAfter = _calculateTableAdvantage(gameState, bot);
    final impactDelta = advantageAfter - advantageBefore;
    
    // Enregistrer l'impact du pouvoir
    final powerName = val == '7' ? 'look_own' : 
                      val == '10' ? 'spy' : 
                      val == 'V' ? 'swap' : 'shuffle';
    AiTelemetryService().onPowerUsed(bot.id, powerName, impactDelta);

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 7 : Regarder sa propre carte
  // ═══════════════════════════════════════════════════════════════════════════

  static void _usePower7(GameState gameState, Player bot, BotDifficulty difficulty) {
    int idx = BotMemoryManager.chooseCardToLook(bot, difficulty);
    GameLogic.lookAtCard(gameState, bot, idx);
    bot.updateMentalMap(idx, bot.hand[idx]);

    // Log
    GameLoggerService.instance.logPowerUse(
      player: bot,
      powerValue: 7,
      powerName: 'Regarder',
      description: 'Regarde sa carte position $idx (${bot.hand[idx].displayName})',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 10 : Espionner une carte adverse
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePower10(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    BuildContext? context, {
    BotPersonality? personality,
  }) async {
    Player? target = _chooseSpyTarget(gameState, bot, difficulty, personality: personality);
    if (target == null || target.hand.isEmpty) return;

    // HARDCORE FIX: Les niveaux hardcore ciblent intelligemment
    final isHardcore = difficulty.name == "Or" || 
                       difficulty.name == "Platine" ||
                       difficulty.name == "Hard" ||
                       difficulty.name == "Insane" ||
                       difficulty.name == "Nightmare" ||
                       difficulty.name == "Impossible";
    
    int idx;
    if (isHardcore && _random.nextDouble() < 0.7) {
      idx = _random.nextBool() ? 0 : target.hand.length - 1;
    } else {
      idx = _random.nextInt(target.hand.length);
    }
    GameLogic.lookAtCard(gameState, target, idx);

    // AMÉLIORATION : Le bot mémorise la carte espionnée
    // Cela lui permet de mieux estimer le score adverse pour Dutch
    final spiedCard = target.hand[idx];
    bot.rememberSpiedCard(target.id, idx, spiedCard);

    // Log
    GameLoggerService.instance.logPowerUse(
      player: bot,
      powerValue: 10,
      powerName: 'Espionner',
      description: 'Espionne ${target.name} position $idx (${spiedCard.displayName})',
    );

    if (target.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotSpyNotification(context, bot, target.name, idx);
      await Future.delayed(const Duration(milliseconds: 1400));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseSpyTarget(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    // 🔥 HARDCORE : En mode impitoyable, cibler l'humain prioritairement
    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    
    if (isHardcore) {
      // Utiliser denyHumanPodium pour cibler l'humain sur le podium
      final humanTarget = BotThreatAnalyzer.pickBestTarget(
        gs, bot, TargetMode.denyHumanPodium, 
        difficulty: difficulty,
        isHardcoreMode: true,
      );
      if (humanTarget != null) return humanTarget;
    }

    // Utiliser le nouveau système de ciblage unifié
    final target = BotThreatAnalyzer.pickBestTarget(
      gs, bot, TargetMode.gatherInfo, 
      difficulty: difficulty,
      isHardcoreMode: isHardcore,
    );
    if (target != null) return target;

    return opponents[_random.nextInt(opponents.length)];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR VALET : Échange de cartes
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerValet(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BuildContext? context, {
    BotPersonality? personality,
  }) async {
    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE VALET : Échanger entre DEUX AUTRES joueurs (pas soi-même)
    // Cela permet de déstabiliser les adversaires sans perdre sa propre mémoire
    // ═══════════════════════════════════════════════════════════════════════

    // Trouver deux cibles différentes (pas le bot lui-même)
    final targets = _chooseValetTargets(gs, bot, difficulty, personality: personality);
    if (targets == null) return;

    final (target1, target2) = targets;
    if (target1.hand.isEmpty || target2.hand.isEmpty) return;

    // Choisir les indices des cartes à échanger
    int idx1 = _chooseValetTargetCardIndex(target1, difficulty, bot.botBehavior);
    int idx2 = _chooseValetTargetCardIndex(target2, difficulty, bot.botBehavior);

    // Effectuer l'échange entre les deux AUTRES joueurs
    GameLogic.swapCards(gs, target1, idx1, target2, idx2);

    // Notifier si l'humain est impliqué
    if (target1.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotSwapNotification(context, bot, target1.name, idx1);
      await Future.delayed(const Duration(milliseconds: 1400));
      gameProvider.resumeReactionTimerAfterNotification();
    } else if (target2.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotSwapNotification(context, bot, target2.name, idx2);
      await Future.delayed(const Duration(milliseconds: 1400));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  /// Choisit DEUX cibles pour le pouvoir Valet (pas le bot lui-même)
  static (Player, Player)? _chooseValetTargets(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.length < 2) return null; // Besoin de 2 adversaires minimum

    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot, isHardcoreMode: isHardcore);

    // PRIORITÉ : L'humain doit TOUJOURS être impliqué si possible
    // Cela déstabilise sa mémoire
    Player? humanPlayer = report.humanPlayer;
    Player? otherTarget;

    if (humanPlayer != null && humanPlayer.hand.isNotEmpty) {
      // Trouver un autre joueur (pas l'humain, pas le bot)
      final otherOpponents = opponents.where((p) => p.id != humanPlayer.id).toList();
      if (otherOpponents.isNotEmpty) {
        // Choisir celui avec le moins de cartes (plus impactant)
        otherOpponents.sort((a, b) => a.hand.length.compareTo(b.hand.length));
        otherTarget = otherOpponents.first;
        return (humanPlayer, otherTarget);
      }
    }

    // Pas d'humain ou un seul adversaire : échanger entre les deux bots
    if (opponents.length >= 2) {
      // Trier par nombre de cartes croissant (cibler ceux avec peu de cartes)
      opponents.sort((a, b) => a.hand.length.compareTo(b.hand.length));
      return (opponents[0], opponents[1]);
    }

    return null;
  }

  static int _chooseValetTargetCardIndex(Player target, BotDifficulty difficulty, BotBehavior? behavior) {
    if (target.hand.isEmpty) return 0;
    if (target.hand.length == 1) return 0;

    final indices = List<int>.generate(target.hand.length, (i) => i);
    indices.sort((a, b) => target.hand[a].points.compareTo(target.hand[b].points));

    int bestIdx = indices.first;
    int secondIdx = indices.length > 1 ? indices[1] : bestIdx;

    double smartChance = difficulty.name == "Bronze" ? 0.25 :
                        difficulty.name == "Argent" ? 0.50 :
                        difficulty.name == "Or" ? 0.80 : 1.0;

    if (behavior == BotBehavior.aggressive) {
      smartChance += 0.10;
    } else if (behavior == BotBehavior.fast) {
      smartChance -= 0.10;
    }
    if (target.isHuman) {
      smartChance += 0.10;
    }

    smartChance = smartChance.clamp(0.0, 1.0);

    if (_random.nextDouble() < smartChance) return bestIdx;

    double secondChance = difficulty.name == "Bronze" ? 0.35 : 0.55;
    if (_random.nextDouble() < secondChance) return secondIdx;

    return _random.nextInt(target.hand.length);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR JOKER : Mélanger la main d'un joueur
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerJoker(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BuildContext? context, {
    BotPersonality? personality,
  }) async {
    Player? target = _chooseJokerTarget(gs, bot, difficulty, personality: personality);
    target ??= bot;

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
    }

    if (target.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotJokerNotification(context, bot, target.name);
      await Future.delayed(const Duration(milliseconds: 1700));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseJokerTarget(
    GameState gs,
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    if (possibleTargets.isEmpty) return null;

    final isHardcore = BotThreatAnalyzer.isHardcoreMode(difficulty);
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot, isHardcoreMode: isHardcore);
    
    // 🎯 ANALYSE DE LA MENACE HUMAINE
    final threatTracker = HumanThreatTracker();
    final humanThreatLevel = threatTracker.calculateThreatLevel(gs);

    // ═══════════════════════════════════════════════════════════════════════
    // PHILOSOPHIE : Le but est que l'HUMAIN perde !
    // Le Joker mélange = ruine sa mémoire et sa stratégie
    // Même si un bot est plus proche de Dutch, on préfère ruiner l'humain
    // ═══════════════════════════════════════════════════════════════════════

    // 🎯 RÈGLE #0 (NOUVELLE) : Humain CRITICAL = cible ABSOLUE
    // Peu importe ce que font les autres, on doit arrêter l'humain
    if (humanThreatLevel == HumanThreatLevel.critical && report.humanPlayer != null) {
      // Log dans l'historique du jeu
      gs.addToHistory('🎯 ${bot.name} cible l\'humain (menace critique)');
      return report.humanPlayer;
    }

    // RÈGLE #1 (PRIORITÉ ABSOLUE) : L'humain avec peu de cartes = cible #1
    // Il est probablement prêt à Dutch → on ruine tout
    if (report.humanPlayer != null && report.humanPlayer!.hand.length <= 2) {
      return report.humanPlayer;
    }
    
    // 🎯 RÈGLE #1.5 : Humain HIGH = cible prioritaire même avec plus de cartes
    if (humanThreatLevel == HumanThreatLevel.high && report.humanPlayer != null) {
      // L'humain progresse bien, on le mélange pour le ralentir
      if (report.humanPlayer!.hand.length <= 3) {
        return report.humanPlayer;
      }
    }

    // RÈGLE #2 : L'humain sur le podium = on le mélange pour le déstabiliser
    if (report.humanOnPodium && report.humanPlayer != null) {
      return report.humanPlayer;
    }

    // RÈGLE #3 : Si un bot a 1 carte et peut Dutch avant nous, le cibler
    if (report.hasOpponentWithOneCard) {
      final oneCardBots = possibleTargets.where((p) => p.hand.length == 1 && !p.isHuman).toList();
      if (oneCardBots.isNotEmpty) {
        oneCardBots.sort((a, b) => a.getKnownScore().compareTo(b.getKnownScore()));
        return oneCardBots.first;
      }
    }

    // RÈGLE #4 : Par défaut, cibler l'humain (chaos total)
    if (report.humanPlayer != null) {
      return report.humanPlayer;
    }

    // Fallback : celui avec le meilleur score parmi les bots
    possibleTargets.sort((a, b) => a.getKnownScore().compareTo(b.getKnownScore()));
    return possibleTargets.first;
  }

  static void _skipPower(GameState gameState, Player bot) {
    final powerVal = gameState.specialCardToActivate?.value ?? '?';

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("⏭️ ${bot.name} ignore son pouvoir.");

    // Log
    GameLoggerService.instance.logPowerSkip(
      player: bot,
      powerValue: int.tryParse(powerVal) ?? 0,
      reason: 'Pas d\'avantage à utiliser ce pouvoir',
    );
  }
}
