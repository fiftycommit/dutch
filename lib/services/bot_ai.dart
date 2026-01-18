import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_settings.dart';
import 'game_logic.dart';
import 'bot_difficulty.dart';
import '../widgets/special_power_dialogs.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

class BotAI {
  static final Random _random = Random();

  static BuildContext? get _context {
    return navigatorKey.currentContext;
  }

  static Future<void> playBotTurn(GameState gameState, {int? playerMMR}) async {
    debugPrint("🤖 [playBotTurn] DÉBUT - Bot: ${gameState.currentPlayer.name}");

    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      debugPrint("❌ [playBotTurn] Ce n'est pas un bot!");
      return;
    }

    // 🎯 Déterminer la difficulté du bot (SBMM ou manuel)
    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getDifficultyFromPersonality(bot.botPersonality);

    debugPrint("🎯 [playBotTurn] Difficulté: ${difficulty.name}");
    debugPrint("🎭 [playBotTurn] Personnalité: ${bot.botPersonality}");

    // 🧠 Appliquer le decay mémoriel (oubli)
    _applyMemoryDecay(bot, difficulty);
    debugPrint("🧠 [playBotTurn] Mémoire décayée");

    // ⏱️ Temps de réflexion selon personnalité
    int thinkingTime = _getThinkingTime(bot.botPersonality, difficulty, gameState);
    debugPrint("⏳ [playBotTurn] Temps de réflexion: ${thinkingTime}ms");
    await Future.delayed(Duration(milliseconds: thinkingTime));

    // 🎯 Décision Dutch basée sur la personnalité
    if (_shouldCallDutch(gameState, bot, difficulty)) {
      debugPrint("📢 [playBotTurn] Le bot appelle DUTCH!");
      GameLogic.callDutch(gameState);
      return;
    }

    debugPrint("🎴 [playBotTurn] Le bot pioche...");
    GameLogic.drawCard(gameState);
    debugPrint("✅ [playBotTurn] Carte piochée: ${gameState.drawnCard?.value}");

    await Future.delayed(const Duration(milliseconds: 1000));

    debugPrint("🤔 [playBotTurn] Décision de l'action...");
    await _decideCardAction(gameState, bot, difficulty);
    debugPrint("✅ [playBotTurn] Action décidée et exécutée");

    debugPrint("🏁 [playBotTurn] FIN");
  }

  static Future<void> useBotSpecialPower(GameState gameState,
      {int? playerMMR}) async {
    if (!gameState.isWaitingForSpecialPower ||
        gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    PlayingCard card = gameState.specialCardToActivate!;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getDifficultyFromPersonality(bot.botPersonality);

    await Future.delayed(const Duration(milliseconds: 1000));

    String val = card.value;

    if (val == '7') {
      // Carte 7 : Regarder UNE de ses cartes
      int idx = _chooseCardToLook(bot, difficulty);
      GameLogic.lookAtCard(gameState, bot, idx);

      bot.updateMentalMap(idx, bot.hand[idx]);
      debugPrint("👁️ Bot regarde sa carte #$idx et l'enregistre");
    } else if (val == '10') {
      // Carte 10 : Regarder carte adverse
      Player? target = _chooseSpyTarget(gameState, bot, difficulty);
      if (target != null) {
        int idx = _random.nextInt(target.hand.length);
        GameLogic.lookAtCard(gameState, target, idx);
        debugPrint("🔍 Bot regarde la carte #$idx de ${target.name}");
      }
    } else if (val == 'V') {
      // Valet : Échange stratégique
      await _executeValetStrategy(gameState, bot, difficulty);
    } else if (val == 'JOKER') {
      // Joker : Mélanger stratégiquement
      await _executeJokerStrategy(gameState, bot, difficulty);
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }

  /// 🧠 Appliquer l'oubli selon la difficulté
  static void _applyMemoryDecay(Player bot, BotDifficulty difficulty) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;

    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] &&
          _random.nextDouble() < difficulty.forgetChancePerTurn) {
        bot.forgetCard(i);
        debugPrint("💭 Bot oublie sa carte #$i");
      }
    }
  }

  /// ⏱️ Temps de réflexion adaptatif selon personnalité et contexte
  static int _getThinkingTime(BotPersonality? personality, BotDifficulty difficulty, GameState gameState) {
    if (personality == null) return 800;

    // 🧠 RÉFLÉCHI : temps variable selon contexte
    if (personality == BotPersonality.cautious) {
      bool criticalMoment = gameState.players.any((p) => p.hand.length <= 2);
      
      switch (difficulty.name) {
        case "Bronze":
          return criticalMoment ? 1000 : 800;
        case "Argent":
          return criticalMoment ? 1400 : 1000;
        case "Or":
          return criticalMoment ? 1800 : 1200; // Max 1.8s au lieu de 2.5s
        default:
          return 1000;
      }
    }

    // 🏃 FAST : rapide
    if (personality == BotPersonality.aggressive) {
      return difficulty.name == "Or" ? 700 : 600;
    }

    // ⚖️ ÉQUILIBRÉ et autres : temps moyen
    return 900;
  }

  /// 🎯 Décision Dutch adaptée à la personnalité
  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty) {
    int estimatedScore = bot.getEstimatedScore();
    BotPersonality? personality = bot.botPersonality;

    int threshold;

    switch (personality) {
      case BotPersonality.aggressive: // 🏃 FAST
        threshold = difficulty.name == "Bronze" ? 10 :
                   difficulty.name == "Argent" ? 6 : 4;
        break;

      case BotPersonality.cautious: // 🧠 RÉFLÉCHI (très prudent)
        threshold = difficulty.name == "Bronze" ? 8 :
                   difficulty.name == "Argent" ? 5 : 3;
        
        // ✅ Vérifier qu'aucun adversaire n'a un meilleur score
        if (difficulty.name != "Bronze") {
          for (var p in gs.players) {
            if (p.id != bot.id && p.getEstimatedScore() <= threshold) {
              debugPrint("🧠 Réfléchi prudent : adversaire ${p.name} a score ≤ $threshold, pas de Dutch");
              return false;
            }
          }
        }
        break;

      case BotPersonality.balanced: // ⚖️ ÉQUILIBRÉ (adaptatif)
        bool endGame = gs.players.any((p) => p.hand.length <= 2);
        
        if (endGame) {
          // Fin de partie : plus agressif
          threshold = difficulty.name == "Bronze" ? 8 :
                     difficulty.name == "Argent" ? 5 : 3;
        } else {
          // Début : plus prudent
          threshold = difficulty.name == "Bronze" ? 6 :
                     difficulty.name == "Argent" ? 4 : 2;
        }
        break;

      default: // Par défaut : seuils standards
        threshold = difficulty.dutchThreshold;
    }

    debugPrint("🎯 Score estimé: $estimatedScore, Seuil: $threshold (${personality?.toString()})");
    return estimatedScore <= threshold;
  }

  /// 🎴 Décision de l'action selon personnalité
  static Future<void> _decideCardAction(
      GameState gs, Player bot, BotDifficulty difficulty) async {
    debugPrint("🤔 [_decideCardAction] DÉBUT");

    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) {
      debugPrint("❌ [_decideCardAction] Pas de carte piochée");
      return;
    }

    debugPrint("🎴 [_decideCardAction] Carte piochée: ${drawn.value} (${drawn.points} pts)");

    int drawnVal = drawn.points;
    BotPersonality? personality = bot.botPersonality;

    // 🎯 Seuil de défausse selon personnalité et difficulté
    int discardThreshold;
    
    switch (personality) {
      case BotPersonality.aggressive: // 🏃 FAST
        discardThreshold = difficulty.name == "Bronze" ? 9 :
                          difficulty.name == "Argent" ? 7 : 5;
        break;

      case BotPersonality.cautious: // 🧠 RÉFLÉCHI (optimise)
        discardThreshold = difficulty.name == "Bronze" ? 8 :
                          difficulty.name == "Argent" ? 6 : 4;
        break;

      case BotPersonality.balanced: // ⚖️ ÉQUILIBRÉ (adaptatif)
        bool endGame = gs.players.any((p) => p.hand.length <= 2);
        discardThreshold = endGame ? 6 : 8; // Plus agressif en fin de partie
        break;

      default:
        discardThreshold = 7;
    }

    debugPrint("📊 Seuil de défausse: $discardThreshold pour ${personality?.toString()}");

    // Chercher une carte connue plus haute dans la carte mentale
    int replaceIdx = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > drawnVal) {
        replaceIdx = i;
        debugPrint("🔄 Carte mentale plus haute trouvée: index $i (${bot.mentalMap[i]!.points} pts)");
        break;
      }
    }

    // Sinon prendre une carte inconnue
    if (replaceIdx == -1) {
      replaceIdx = _chooseUnknownCard(bot);
      debugPrint("❓ Carte inconnue choisie: index $replaceIdx");
    }

    // Décision : remplacer ou défausser
    if (replaceIdx != -1 && drawnVal < discardThreshold) {
      debugPrint("✅ DÉCISION: REMPLACER (index $replaceIdx)");

      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;

      if (confused) {
        debugPrint("😵 Bot confus ! Il croit toujours avoir l'ancienne carte");
      } else {
        bot.updateMentalMap(replaceIdx, drawn);
      }

      GameLogic.replaceCard(gs, replaceIdx);
    } else {
      debugPrint("🗑️ DÉCISION: DÉFAUSSER");
      GameLogic.discardDrawnCard(gs);
    }

    debugPrint("🏁 [_decideCardAction] FIN");
  }

  /// 👁️ Choisir quelle carte regarder avec le 7
  static int _chooseCardToLook(Player bot, BotDifficulty difficulty) {
    // 🧠 RÉFLÉCHI Or : regarde les cartes inconnues en priorité
    if (bot.botPersonality == BotPersonality.cautious && difficulty.name == "Or") {
      List<int> unknown = [];
      for (int i = 0; i < bot.hand.length; i++) {
        if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
          unknown.add(i);
        }
      }
      if (unknown.isNotEmpty) {
        return unknown[_random.nextInt(unknown.length)];
      }
    }

    // Par défaut : carte inconnue aléatoire
    return _chooseUnknownCard(bot);
  }

  /// 🔍 Choisir qui espionner avec le 10
  static Player? _chooseSpyTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id).toList();
    if (opponents.isEmpty) return null;

    BotPersonality? personality = bot.botPersonality;

    // 🧠 RÉFLÉCHI : espionne celui avec le meilleur score estimé
    if (personality == BotPersonality.cautious && difficulty.name != "Bronze") {
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      return opponents.first;
    }

    // ⚔️ FAST/AGRESSIF : cible aléatoire
    return opponents[_random.nextInt(opponents.length)];
  }

  /// 🤵 Stratégie Valet selon personnalité
  static Future<void> _executeValetStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotPersonality? personality = bot.botPersonality;
    
    // ✅ FIX : Choisir la cible stratégiquement au lieu de toujours l'humain
    Player? target = _chooseValetTarget(gs, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    int myCardIdx = _chooseBadCard(bot);
    int targetIdx;

    // 🧠 RÉFLÉCHI Or : essaie de prendre la meilleure carte de l'adversaire
    if (personality == BotPersonality.cautious && difficulty.name == "Or") {
      targetIdx = _chooseBestCardIndex(target);
    } else {
      targetIdx = _random.nextInt(target.hand.length);
    }

    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;

    if (confused) {
      debugPrint("😵 Bot confus ! Il garde l'ancienne valeur en mémoire");
    } else {
      bot.forgetCard(myCardIdx);
    }

    GameLogic.swapCards(gs, bot, myCardIdx, target, targetIdx);
    debugPrint("🔄 Bot échange sa carte #$myCardIdx avec la carte #$targetIdx de ${target.name}");

    // Notification si cible = humain
    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotSwapNotification(
          _context!, bot.name, target.name, targetIdx);
      await Future.delayed(const Duration(milliseconds: 2000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  /// 🎯 Choisir la cible du Valet (FIX du bug !)
  static Player? _chooseValetTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id).toList();
    if (opponents.isEmpty) return null;

    BotPersonality? personality = bot.botPersonality;

    // ⚔️ FAST Bronze : cible aléatoire
    if (personality == BotPersonality.aggressive && difficulty.name == "Bronze") {
      return opponents[_random.nextInt(opponents.length)];
    }

    // ⚔️ FAST Argent/Or : cible celui avec le meilleur score (sabotage compétitif)
    if (personality == BotPersonality.aggressive) {
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      return opponents.first; // Celui avec le meilleur score
    }

    // 🧠 RÉFLÉCHI : cible celui qui va probablement appeler Dutch
    if (personality == BotPersonality.cautious && difficulty.name == "Or") {
      for (var p in opponents) {
        if (p.getEstimatedScore() <= 5) {
          debugPrint("🎯 Valet cible ${p.name} (score estimé faible, risque Dutch)");
          return p;
        }
      }
    }

    // ⚖️ ÉQUILIBRÉ : cible le meilleur score si fin de partie, sinon aléatoire
    if (personality == BotPersonality.balanced) {
      bool endGame = gs.players.any((p) => p.hand.length <= 2);
      if (endGame) {
        opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
        return opponents.first;
      }
    }

    // Par défaut : cible aléatoire (plus de ciblage systématique de l'humain !)
    return opponents[_random.nextInt(opponents.length)];
  }

  /// 🃏 Stratégie Joker selon personnalité
  static Future<void> _executeJokerStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotPersonality? personality = bot.botPersonality;
    
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    if (possibleTargets.isEmpty) {
      possibleTargets = [bot]; // Se mélanger soi-même en dernier recours
    }

    Player? target;

    // 🧠 RÉFLÉCHI : mélange celui avec le meilleur score estimé
    if (personality == BotPersonality.cautious && difficulty.name != "Bronze") {
      possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      target = possibleTargets.first;
      debugPrint("🧠 Joker stratégique sur ${target.name} (meilleur score)");
    } else {
      // Autres : cible aléatoire
      target = possibleTargets[_random.nextInt(possibleTargets.length)];
    }

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
      debugPrint("🌀 Bot mélange ses propres cartes et oublie tout!");
    }

    debugPrint("🃏 Bot mélange les cartes de ${target.name}");

    // Notification si cible = humain
    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotJokerNotification(
          _context!, bot.name, target.name);
      await Future.delayed(const Duration(milliseconds: 2000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  /// 🎴 Utilitaires pour choisir des cartes
  static int _chooseUnknownCard(Player bot) {
    List<int> unknownIndices = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknownIndices.add(i);
      }
    }
    if (unknownIndices.isNotEmpty) {
      return unknownIndices[_random.nextInt(unknownIndices.length)];
    }
    return 0;
  }

  static int _chooseBadCard(Player bot) {
    // Chercher la pire carte dans la carte mentale
    int worstIdx = 0;
    int worstValue = -1;

    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstValue) {
        worstValue = bot.mentalMap[i]!.points;
        worstIdx = i;
      }
    }

    // Si aucune carte connue, prendre une inconnue
    if (worstValue == -1) {
      return _chooseUnknownCard(bot);
    }

    return worstIdx;
  }

  static int _chooseBestCardIndex(Player target) {
    // Essayer de deviner la meilleure carte (aléatoire pour l'instant)
    // TODO : Améliorer avec espionnage du 10
    return _random.nextInt(target.hand.length);
  }

  /// 🎯 Conversion BotPersonality → BotDifficulty (mode manuel)
  static BotDifficulty _getDifficultyFromPersonality(BotPersonality? personality) {
    if (personality == null) return BotDifficulty.silver;

    switch (personality) {
      case BotPersonality.beginner:
      case BotPersonality.novice:
        return BotDifficulty.bronze;

      case BotPersonality.balanced:
      case BotPersonality.cautious:
        return BotDifficulty.silver;

      case BotPersonality.aggressive:
      case BotPersonality.legend:
        return BotDifficulty.gold;
    }
  }
}