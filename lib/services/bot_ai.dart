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

  /// ✅ NOUVEAU: Tenter un match pendant la phase de réaction
  static Future<bool> tryReactionMatch(GameState gameState, Player bot, {int? playerMMR}) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;
    if (gameState.discardPile.isEmpty) return false;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getDifficultyFromPersonality(bot.botPersonality);

    // Vérifier si le bot tente de matcher
    if (_random.nextDouble() > difficulty.reactionMatchChance) {
      debugPrint("🤖 [ReactionMatch] ${bot.name} ne tente pas de matcher");
      return false;
    }

    PlayingCard topDiscard = gameState.discardPile.last;
    
    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      // Le bot ne connaît que les cartes dans sa mentalMap
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;
        
        if (knownCard.matches(topDiscard)) {
          // Vérifier la précision du bot
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            debugPrint("⚡ [ReactionMatch] ${bot.name} tente un match avec carte #$i");
            
            // Petit délai avant le match
            int reactionDelay = (500 * (1 - difficulty.reactionSpeed)).round() + 200;
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, i);
            
            if (success) {
              debugPrint("✅ [ReactionMatch] ${bot.name} a réussi son match!");
              // Mettre à jour la mentalMap
              if (i < bot.mentalMap.length) {
                bot.mentalMap.removeAt(i);
              }
              return true;
            } else {
              debugPrint("❌ [ReactionMatch] ${bot.name} a raté son match!");
              return false;
            }
          } else {
            debugPrint("😵 [ReactionMatch] ${bot.name} hésite et rate l'opportunité");
          }
        }
      }
    }

    // ✅ NOUVEAU: Les bots Or/Platine peuvent tenter un match même sur carte inconnue
    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      // 30% de chance de tenter un match "à l'aveugle" sur une carte inconnue
      if (_random.nextDouble() < 0.30) {
        // Choisir une carte inconnue au hasard
        List<int> unknownIndices = [];
        for (int i = 0; i < bot.hand.length; i++) {
          if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
            unknownIndices.add(i);
          }
        }
        
        if (unknownIndices.isNotEmpty) {
          int blindIndex = unknownIndices[_random.nextInt(unknownIndices.length)];
          PlayingCard blindCard = bot.hand[blindIndex];
          
          if (blindCard.matches(topDiscard)) {
            debugPrint("🎲 [ReactionMatch] ${bot.name} tente un match aveugle!");
            
            int reactionDelay = (400 * (1 - difficulty.reactionSpeed)).round() + 150;
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, blindIndex);
            return success;
          }
        }
      }
    }

    return false;
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
      if (target != null && target.hand.isNotEmpty) {
        // ✅ AMÉLIORATION: Les bots Or/Platine choisissent stratégiquement
        int idx;
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.7) {
          // Cibler une carte que l'adversaire semble protéger (la première ou dernière)
          idx = _random.nextBool() ? 0 : target.hand.length - 1;
        } else {
          idx = _random.nextInt(target.hand.length);
        }
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
          return criticalMoment ? 1800 : 1200;
        case "Platine":
          return criticalMoment ? 2000 : 1400;
        default:
          return 1000;
      }
    }

    // 🏃 FAST : rapide
    if (personality == BotPersonality.aggressive) {
      return difficulty.name == "Or" || difficulty.name == "Platine" ? 600 : 500;
    }

    // ⚖️ ÉQUILIBRÉ et autres : temps moyen
    return 900;
  }

  /// 🎯 Décision Dutch adaptée à la personnalité - PLUS AGRESSIVE
  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty) {
    int estimatedScore = bot.getEstimatedScore();
    BotPersonality? personality = bot.botPersonality;

    int threshold;

    switch (personality) {
      case BotPersonality.aggressive:
        // ✅ Agressif: Dutch plus tôt
        threshold = difficulty.name == "Bronze" ? 8 :
                   difficulty.name == "Argent" ? 5 : 
                   difficulty.name == "Or" ? 4 : 3;
        break;

      case BotPersonality.cautious:
        // ✅ Prudent: Vérifie les adversaires avant de Dutch
        threshold = difficulty.name == "Bronze" ? 6 :
                   difficulty.name == "Argent" ? 4 : 
                   difficulty.name == "Or" ? 3 : 2;
        
        // Les bots prudents Or/Platine vérifient si un adversaire a un meilleur score
        if (difficulty.name != "Bronze") {
          for (var p in gs.players) {
            if (p.id != bot.id) {
              int opponentScore = p.getEstimatedScore();
              // Si un adversaire semble avoir un score proche ou meilleur, ne pas Dutch
              if (opponentScore <= estimatedScore + 2) {
                debugPrint("🧠 Prudent: adversaire ${p.name} a score ~$opponentScore, risqué de Dutch");
                // Mais quand même 30% de chance de tenter si très bas score
                if (estimatedScore > 3 || _random.nextDouble() > 0.30) {
                  return false;
                }
              }
            }
          }
        }
        break;

      case BotPersonality.balanced:
        bool endGame = gs.players.any((p) => p.hand.length <= 2);
        
        if (endGame) {
          threshold = difficulty.name == "Bronze" ? 7 :
                     difficulty.name == "Argent" ? 5 : 
                     difficulty.name == "Or" ? 3 : 2;
        } else {
          threshold = difficulty.name == "Bronze" ? 5 :
                     difficulty.name == "Argent" ? 4 : 
                     difficulty.name == "Or" ? 3 : 2;
        }
        break;

      default:
        threshold = difficulty.dutchThreshold;
    }

    debugPrint("🎯 Score estimé: $estimatedScore, Seuil: $threshold (${personality?.toString()})");
    return estimatedScore <= threshold;
  }

  /// 🎴 Décision de l'action selon personnalité - PLUS STRATÉGIQUE
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

    // ✅ AMÉLIORATION: Utiliser le seuil de la difficulté
    int keepThreshold = difficulty.keepCardThreshold;
    
    // Ajuster selon la personnalité
    switch (personality) {
      case BotPersonality.aggressive:
        keepThreshold += 1; // Plus permissif
        break;
      case BotPersonality.cautious:
        keepThreshold -= 1; // Plus exigeant
        break;
      default:
        break;
    }

    debugPrint("📊 Seuil pour garder: $keepThreshold pour ${personality?.toString()}");

    // ✅ AMÉLIORATION: Logique de remplacement plus intelligente
    int replaceIdx = -1;
    int worstKnownValue = -1;
    
    // Chercher la pire carte connue
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        int cardValue = bot.mentalMap[i]!.points;
        if (cardValue > worstKnownValue && cardValue > drawnVal) {
          worstKnownValue = cardValue;
          replaceIdx = i;
        }
      }
    }

    // Si aucune carte connue n'est pire, choisir une carte inconnue
    if (replaceIdx == -1 && drawnVal <= keepThreshold) {
      replaceIdx = _chooseUnknownCard(bot);
      debugPrint("❓ Aucune carte connue pire, choisit carte inconnue: index $replaceIdx");
    }

    // Décider de garder ou défausser
    if (replaceIdx != -1 && drawnVal <= keepThreshold) {
      debugPrint("✅ DÉCISION: REMPLACER (index $replaceIdx) - carte piochée ${drawnVal} pts ≤ seuil $keepThreshold");

      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;

      if (confused) {
        debugPrint("😵 Bot confus ! Il croit toujours avoir l'ancienne carte");
      } else {
        bot.updateMentalMap(replaceIdx, drawn);
      }

      GameLogic.replaceCard(gs, replaceIdx);
    } else if (replaceIdx != -1 && worstKnownValue > drawnVal + 3) {
      // ✅ NOUVEAU: Même si la carte piochée est > seuil, remplacer si on a une TRÈS mauvaise carte
      debugPrint("✅ DÉCISION: REMPLACER QUAND MÊME (pire carte connue: $worstKnownValue pts)");
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
    } else {
      debugPrint("🗑️ DÉCISION: DÉFAUSSER (carte ${drawnVal} pts > seuil $keepThreshold)");
      GameLogic.discardDrawnCard(gs);
    }

    debugPrint("🏁 [_decideCardAction] FIN");
  }

  /// 👁️ Choisir quelle carte regarder avec le 7
  static int _chooseCardToLook(Player bot, BotDifficulty difficulty) {
    // Prioriser les cartes inconnues
    List<int> unknown = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknown.add(i);
      }
    }
    
    if (unknown.isNotEmpty) {
      return unknown[_random.nextInt(unknown.length)];
    }

    // Si toutes les cartes sont connues, regarder la pire (pour confirmer)
    if (bot.botPersonality == BotPersonality.cautious && 
        (difficulty.name == "Or" || difficulty.name == "Platine")) {
      int worstIdx = 0;
      int worstVal = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstVal) {
          worstVal = bot.mentalMap[i]!.points;
          worstIdx = i;
        }
      }
      return worstIdx;
    }

    return _random.nextInt(bot.hand.length);
  }

  /// 🔍 Choisir qui espionner avec le 10
  static Player? _chooseSpyTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotPersonality? personality = bot.botPersonality;

    // ✅ AMÉLIORATION: Cibler le joueur le plus dangereux
    if ((difficulty.name == "Or" || difficulty.name == "Platine") ||
        personality == BotPersonality.cautious) {
      // Trier par score estimé (plus bas = plus dangereux)
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      
      // 80% de chance de cibler le meilleur joueur
      if (_random.nextDouble() < 0.80) {
        return opponents.first;
      }
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  /// 🤵 Stratégie Valet selon personnalité - PLUS AGRESSIVE
  static Future<void> _executeValetStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotPersonality? personality = bot.botPersonality;
    
    Player? target = _chooseValetTarget(gs, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    // Choisir sa pire carte connue à échanger
    int myCardIdx = _chooseBadCard(bot);
    int targetIdx;

    // ✅ AMÉLIORATION: Cibler stratégiquement les cartes adverses
    if ((difficulty.name == "Or" || difficulty.name == "Platine") && 
        personality == BotPersonality.cautious) {
      // Cibler la carte que l'adversaire protège le plus (souvent la première)
      targetIdx = 0;
    } else if (difficulty.name != "Bronze" && _random.nextDouble() < 0.6) {
      // Cibler une carte aléatoire mais pas la dernière (souvent mauvaise)
      if (target.hand.length > 1) {
        targetIdx = _random.nextInt(target.hand.length - 1);
      } else {
        targetIdx = 0;
      }
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

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotSwapNotification(
          _context!, bot, target.name, targetIdx);
      await Future.delayed(const Duration(milliseconds: 2000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  /// 🎯 Choisir la cible du Valet - CIBLER LE JOUEUR HUMAIN PLUS SOUVENT
  static Player? _chooseValetTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotPersonality? personality = bot.botPersonality;

    // ✅ NOUVEAU: Les bots Or/Platine ciblent plus souvent le joueur humain
    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      Player? human = opponents.where((p) => p.isHuman).firstOrNull;
      if (human != null && _random.nextDouble() < 0.65) {
        debugPrint("🎯 Bot cible le joueur humain pour l'échange");
        return human;
      }
    }

    if (difficulty.name == "Bronze") {
      return opponents[_random.nextInt(opponents.length)];
    }

    if (personality == BotPersonality.aggressive) {
      List<Player> lowCardTargets = opponents.where((p) => p.hand.length <= 3).toList();
      
      if (lowCardTargets.isNotEmpty && _random.nextDouble() < 0.75) {
        return lowCardTargets[_random.nextInt(lowCardTargets.length)];
      } else {
        return opponents[_random.nextInt(opponents.length)];
      }
    }

    if (personality == BotPersonality.cautious) {
      if (_random.nextDouble() < 0.85) {
        return _selectValetTargetWeighted(opponents, difficulty);
      } else {
        return opponents[_random.nextInt(opponents.length)];
      }
    }

    if (personality == BotPersonality.balanced) {
      bool endGame = gs.players.any((p) => p.hand.length <= 2);
      
      if (endGame && _random.nextDouble() < 0.6) {
        return _selectValetTargetWeighted(opponents, difficulty);
      } else if (!endGame && _random.nextDouble() < 0.3) {
        return _selectValetTargetWeighted(opponents, difficulty);
      }
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  /// 🎯 Sélection pondérée de la cible Valet
  static Player _selectValetTargetWeighted(List<Player> opponents, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in opponents) {
      double score = 0.0;
      
      // ✅ BONUS: Cibler le joueur humain
      if (player.isHuman) {
        score += 25.0;
      }
      
      int cardCount = player.hand.length;
      if (cardCount == 1) {
        score += 120.0;
      } else if (cardCount == 2) {
        score += 80.0;
      } else if (cardCount == 3) {
        score += 45.0;
      } else if (cardCount == 4) {
        score += 20.0;
      } else {
        score += 8.0;
      }
      
      int estimatedScore = player.getEstimatedScore();
      if (estimatedScore <= 5) {
        score += 30.0;
      } else if (estimatedScore <= 10) {
        score += 18.0;
      } else if (estimatedScore <= 15) {
        score += 10.0;
      }
      
      double randomBonus = _random.nextDouble() * 30.0;
      
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        score += randomBonus * 0.3;
      } else {
        score += randomBonus * 1.0;
      }
      
      threatScores[player] = score;
    }
    
    Player selectedTarget = opponents.first;
    double maxScore = 0.0;
    
    threatScores.forEach((player, score) {
      if (score > maxScore) {
        maxScore = score;
        selectedTarget = player;
      }
    });
    
    return selectedTarget;
  }

  /// 🃏 Stratégie Joker - CIBLER LE JOUEUR HUMAIN
  static Future<void> _executeJokerStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotPersonality? personality = bot.botPersonality;
    
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    
    if (possibleTargets.isEmpty) {
      possibleTargets = [bot];
    }

    Player? target;

    // ✅ NOUVEAU: Prioriser le joueur humain
    Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
    
    if (human != null && (difficulty.name == "Or" || difficulty.name == "Platine")) {
      // 70% de chance de cibler l'humain
      if (_random.nextDouble() < 0.70) {
        target = human;
        debugPrint("🎯 Joker cible le joueur humain!");
      }
    }

    if (target == null) {
      if (personality == BotPersonality.cautious && difficulty.name != "Bronze") {
        target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        debugPrint("🧠 Joker stratégique sur ${target.name}");
      } else if (personality == BotPersonality.aggressive) {
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.6) {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
        debugPrint("⚔️ Joker rapide sur ${target.name}");
      } else {
        if (difficulty.name != "Bronze" && _random.nextDouble() < 0.3) {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
      }
    }

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
      debugPrint("🌀 Bot mélange ses propres cartes et oublie tout!");
    }

    debugPrint("🃏 Bot mélange les cartes de ${target.name}");

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotJokerNotification(
          _context!, bot, target.name);
      await Future.delayed(const Duration(milliseconds: 3000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  /// 🎯 Sélection pondérée de la cible Joker
  static Player _selectJokerTargetWeighted(List<Player> targets, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in targets) {
      double score = 0.0;
      
      // ✅ BONUS: Cibler le joueur humain
      if (player.isHuman) {
        score += 30.0;
      }
      
      int cardCount = player.hand.length;
      if (cardCount <= 2) {
        score += 50.0;
      } else if (cardCount == 3) {
        score += 30.0;
      } else if (cardCount == 4) {
        score += 15.0;
      }
      
      int estimatedScore = player.getEstimatedScore();
      if (estimatedScore <= 5) {
        score += 20.0;
      } else if (estimatedScore <= 10) {
        score += 10.0;
      } else if (estimatedScore <= 15) {
        score += 5.0;
      }
      
      double randomFactor = _random.nextDouble() * 20.0;
      
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        score += randomFactor * 0.3;
      } else if (difficulty.name == "Argent") {
        score += randomFactor * 1.0;
      } else {
        score += randomFactor * 2.0;
      }
      
      threatScores[player] = score;
    }
    
    Player selectedTarget = targets.first;
    double maxScore = 0.0;
    
    threatScores.forEach((player, score) {
      if (score > maxScore) {
        maxScore = score;
        selectedTarget = player;
      }
    });
    
    return selectedTarget;
  }

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
    int worstIdx = 0;
    int worstValue = -1;

    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstValue) {
        worstValue = bot.mentalMap[i]!.points;
        worstIdx = i;
      }
    }

    if (worstValue == -1) {
      return _chooseUnknownCard(bot);
    }

    return worstIdx;
  }

  static int _chooseBestCardIndex(Player target) {
    return _random.nextInt(target.hand.length);
  }

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
        return BotDifficulty.gold;
        
      case BotPersonality.legend:
        return BotDifficulty.platinum;
    }
  }
}