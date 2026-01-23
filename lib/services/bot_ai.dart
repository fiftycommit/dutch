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

// 🎯 NOUVEAU : Phases de jeu du bot
enum BotGamePhase {
  exploration,  // DÃÂ©couvrir ses cartes
  optimization, // Optimiser son score
  endgame,      // Rush vers Dutch
}

// â SUPPRIMÃ : BotBehavior est déjÃ  défini dans game_settings.dart
// // 🎭 NOUVEAU : Comportements des bots (indÃÂ©pendant du niveau)
// enum BotBehavior {
//   fast,       // Ã°Å¸ÂÆ Minimise nombre de cartes rapidement
//   aggressive, // Ã¢Å¡âïÂ¸Â Attaque l'humain (pouvoirs ciblÃÂ©s)
//   balanced    // Ã¢Å¡âïÂ¸Â Adaptatif selon dÃÂ©fausses humain
// }

class BotAI {
  static final Random _random = Random();

  static BuildContext? get _context {
    return navigatorKey.currentContext;
  }

  // 🎯 NOUVEAU : DÃÂ©terminer la phase de jeu du bot
  static BotGamePhase _getBotPhase(Player bot, GameState gameState) {
    int knownCount = bot.knownCardCount;
    int totalCards = bot.hand.length;
    int estimatedScore = bot.getEstimatedScore();
    
    // Phase ENDGAME : Score trÃÂ¨s bas OU quelqu'un a peu de cartes
    bool someoneClose = gameState.players.any((p) => p.hand.length <= 2);
    if (estimatedScore <= 8 || someoneClose) {
      return BotGamePhase.endgame;
    }
    
    // Phase EXPLORATION : Ne connaÃÂ®t pas encore toutes ses cartes
    if (knownCount < totalCards) {
      return BotGamePhase.exploration;
    }
    
    // Phase OPTIMIZATION : ConnaÃÂ®t tout, optimise
    return BotGamePhase.optimization;
  }

  static Future<void> playBotTurn(GameState gameState, {int? playerMMR}) async {
    debugPrint("Ã°Å¸Â¤â [playBotTurn] DÃâ°BUT - Bot: ${gameState.currentPlayer.name}");

    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      debugPrint("Ã¢ÂÅ [playBotTurn] Ce n'est pas un bot!");
      return;
    }

    // 🎯 DÃÂ©terminer la difficultÃÂ© du bot
    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    debugPrint("🎯 [playBotTurn] DifficultÃÂ©: ${difficulty.name}");
    debugPrint("🎭 [playBotTurn] PersonnalitÃÂ©: ${bot.botBehavior}");

    // 🎯 NOUVEAU : DÃÂ©terminer la phase de jeu
    BotGamePhase phase = _getBotPhase(bot, gameState);
    debugPrint("Ã°Å¸âÅ  [playBotTurn] Phase de jeu: $phase");
    debugPrint("🧠 [playBotTurn] Cartes connues: ${bot.knownCardCount}/${bot.hand.length}");
    debugPrint("Ã°Å¸âÅ  [playBotTurn] Score estimÃÂ©: ${bot.getEstimatedScore()}");

    // 🧠 Appliquer le decay mÃÂ©moriel (oubli)
    _applyMemoryDecay(bot, difficulty);

    // ⏳ Temps de rÃÂ©flexion selon personnalitÃÂ©
    int thinkingTime = _getThinkingTime(bot.botBehavior, difficulty, gameState);
    await Future.delayed(Duration(milliseconds: thinkingTime));

    // 🎯 DÃÂ©cision Dutch basÃÂ©e sur la phase ET la personnalitÃÂ©
    if (_shouldCallDutch(gameState, bot, difficulty, phase)) {
      debugPrint("Ã°Å¸âÂ¢ [playBotTurn] Le bot appelle DUTCH!");
      GameLogic.callDutch(gameState);
      return;
    }

    debugPrint("🎴 [playBotTurn] Le bot pioche...");
    GameLogic.drawCard(gameState);
    debugPrint("Ã¢Åâ¦ [playBotTurn] Carte piochÃÂ©e: ${gameState.drawnCard?.value}");

    await Future.delayed(const Duration(milliseconds: 1000));

    debugPrint("Ã°Å¸Â¤â [playBotTurn] DÃÂ©cision de l'action...");
    await _decideCardAction(gameState, bot, difficulty, phase);
    debugPrint("Ã¢Åâ¦ [playBotTurn] Action dÃÂ©cidÃÂ©e et exÃÂ©cutÃÂ©e");

    debugPrint("🏁 [playBotTurn] FIN");
  }

  /// Ã¢Åâ¦ AMÃâ°LIORÃâ° : DÃÂ©cision Dutch avec phase de jeu, audace et apprentissage
  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    int estimatedScore = bot.getEstimatedScore();
    BotBehavior? behavior = bot.botBehavior;

    // Ã¢ÂÅ Ne jamais Dutch en phase EXPLORATION (on ne connaÃÂ®t pas tout)
    if (phase == BotGamePhase.exploration) {
      debugPrint("Ã°Å¸âÂ Phase exploration, pas de Dutch tant qu'on ne connaÃÂ®t pas tout");
      return false;
    }

    // 🎲 NOUVEAU : Facteur d'audace basÃÂ© sur la situation
    double audacityBonus = _calculateAudacity(gs, bot, difficulty);
    debugPrint("🎲 Facteur d'audace: ${audacityBonus.toStringAsFixed(2)}");

    // 🧠 NOUVEAU : Confiance basÃÂ©e sur l'historique Dutch
    double confidence = _calculateDutchConfidence(bot);
    debugPrint("🧠 Confiance Dutch: ${confidence.toStringAsFixed(2)}");

    int threshold;

    // 🎯 Seuils selon COMPORTEMENT ET phase
    if (phase == BotGamePhase.endgame) {
      // En endgame, plus agressif
      switch (behavior) {
        case BotBehavior.fast:
          // FAST: Dutch plus tÃÂ´t pour minimiser cartes
          threshold = difficulty.name == "Bronze" ? 9 :
                     difficulty.name == "Argent" ? 6 : 
                     difficulty.name == "Or" ? 5 : 4;
          break;

        case BotBehavior.aggressive:
          // AGGRESSIVE: Dutch si l'humain semble fort
          threshold = difficulty.name == "Bronze" ? 7 :
                     difficulty.name == "Argent" ? 5 : 
                     difficulty.name == "Or" ? 4 : 3;
          
          // Si l'humain a peu de cartes, ÃÂªtre plus agressif
          if (_isHumanThreatening(gs)) {
            threshold += 1;
            debugPrint("Ã¢Å¡âïÂ¸Â Humain menaÃÂ§ant, threshold +1");
          }
          break;

        case BotBehavior.balanced:
          // Ã¢Å¡âïÂ¸Â BALANCED: Mix FAST + AGGRESSIVE, ÃÂ©volue avec le niveau
          if (difficulty.name == "Bronze") {
            // Bronze : Simple (entre FAST 7 et AGGRESSIVE 7)
            threshold = 7;
          } else if (difficulty.name == "Argent") {
            // Argent : Penche FAST (entre 4 et 5 = 4.5 Ã¢â â 5)
            threshold = 5;
          } else if (difficulty.name == "Or") {
            // Or : Hybride intelligent (entre 3 et 4 = 3.5 Ã¢â â 4)
            threshold = 4;
            // 50% chance de vÃÂ©rifier adversaires (style AGGRESSIVE)
            if (_random.nextDouble() < 0.50) {
              for (var p in gs.players) {
                if (p.id != bot.id) {
                  int opponentScore = p.getEstimatedScore();
                  if (opponentScore <= estimatedScore + 1) {
                    debugPrint("Ã¢Å¡âïÂ¸Â BALANCED Or: adversaire ${p.name} proche, prudence");
                    return false;
                  }
                }
              }
            }
          } else {
            // Platine : TrÃÂ¨s intelligent (entre 2 et 3 = 2.5 Ã¢â â 3)
            threshold = 3;
            // 70% chance de vÃÂ©rifier adversaires
            if (_random.nextDouble() < 0.70) {
              for (var p in gs.players) {
                if (p.id != bot.id) {
                  int opponentScore = p.getEstimatedScore();
                  if (opponentScore <= estimatedScore + 1) {
                    debugPrint("Ã¢Å¡âïÂ¸Â BALANCED Platine: adversaire ${p.name} proche, prudence");
                    return false;
                  }
                }
              }
            }
          }
          debugPrint("Ã¢Å¡âïÂ¸Â BALANCED ENDGAME : Seuil Dutch $threshold");
          break;

        default:
          threshold = difficulty.dutchThreshold + 1;
      }
    } else {
      // En optimization, plus conservateur
      switch (behavior) {
        case BotBehavior.fast:
          // FAST: Encore assez agressif
          threshold = difficulty.name == "Bronze" ? 7 :
                     difficulty.name == "Argent" ? 4 : 
                     difficulty.name == "Or" ? 3 : 2;
          break;

        case BotBehavior.aggressive:
          // AGGRESSIVE: TrÃÂ¨s agressif
          threshold = difficulty.name == "Bronze" ? 5 :
                     difficulty.name == "Argent" ? 3 : 
                     difficulty.name == "Or" ? 2 : 1;
          break;

        case BotBehavior.balanced:
          // Ã¢Å¡âïÂ¸Â BALANCED: Entre FAST et AGGRESSIVE (moyenne)
          threshold = difficulty.name == "Bronze" ? 6 :  // Moyenne de 7 (FAST) et 5 (AGGRESSIVE)
                     difficulty.name == "Argent" ? 4 :   // Moyenne de 4 et 3 = 3.5 Ã¢â â 4
                     difficulty.name == "Or" ? 2 :       // Moyenne de 3 et 2 = 2.5 Ã¢â â 2
                                               2;        // Moyenne de 2 et 1 = 1.5 Ã¢â â 2
          debugPrint("Ã¢Å¡âïÂ¸Â BALANCED : Seuil Dutch hybride $threshold");
          break;

        default:
          threshold = difficulty.dutchThreshold;
      }
    }

    debugPrint("🎯 Score estimÃÂ©: $estimatedScore, Seuil: $threshold (${behavior?.toString()}, phase: $phase)");
    
    // 🎲 NOUVEAU : Ajuster le seuil avec l'audace et la confiance
    double adjustedThreshold = threshold + audacityBonus + (confidence * 2);
    
    debugPrint("Ã¢ÅÂ¨ Seuil ajustÃÂ©: ${adjustedThreshold.toStringAsFixed(1)} (base: $threshold + audace: ${audacityBonus.toStringAsFixed(1)} + confiance: ${(confidence * 2).toStringAsFixed(1)})");
    
    // 🎯 Dutch si score <= seuil ajustÃÂ©
    bool shouldDutch = estimatedScore <= adjustedThreshold.round();
    
    if (shouldDutch) {
      debugPrint("Ã°Å¸âÂ¢ Dutch dÃÂ©cidÃÂ© ! Score $estimatedScore <= ${adjustedThreshold.round()}");
    }
    
    return shouldDutch;
  }
  
  /// 🎲 NOUVEAU : Calculer le facteur d'audace situationnel
  static double _calculateAudacity(GameState gs, Player bot, BotDifficulty difficulty) {
    double audacity = 0.0;
    
    // 1ïÂ¸ÂÃ¢ÆÂ£ Peu de cartes en main = plus audacieux
    int cardCount = bot.hand.length;
    if (cardCount == 1) {
      audacity += 3.0; // TrÃÂ¨s audacieux
      debugPrint("   Ã°Å¸âÂª 1 carte restante: +3.0 audace");
    } else if (cardCount == 2) {
      audacity += 2.0;
      debugPrint("   Ã°Å¸âÂª 2 cartes restantes: +2.0 audace");
    } else if (cardCount == 3) {
      audacity += 1.0;
      debugPrint("   Ã°Å¸âÂª 3 cartes restantes: +1.0 audace");
    }
    
    // 2ïÂ¸ÂÃ¢ÆÂ£ Pioches malchanceuses consÃÂ©cutives
    if (bot.consecutiveBadDraws >= 3) {
      double badDrawBonus = (bot.consecutiveBadDraws - 2) * 0.5;
      audacity += badDrawBonus;
      debugPrint("   🎴 ${bot.consecutiveBadDraws} mauvaises pioches: +${badDrawBonus.toStringAsFixed(1)} audace");
    }
    
    // 3ïÂ¸ÂÃ¢ÆÂ£ Adversaires dangereux = moins audacieux
    int dangerousOpponents = 0;
    for (var p in gs.players) {
      if (p.id != bot.id && p.hand.length <= 2) {
        dangerousOpponents++;
      }
    }
    if (dangerousOpponents > 0) {
      double cautionPenalty = dangerousOpponents * 0.5;
      audacity -= cautionPenalty;
      debugPrint("   Ã¢Å¡Â ïÂ¸Â $dangerousOpponents adversaires dangereux: -${cautionPenalty.toStringAsFixed(1)} audace");
    }
    
    // 4ïÂ¸ÂÃ¢ÆÂ£ PersonnalitÃÂ© influence l'audace
    if (bot.botBehavior == BotBehavior.aggressive) {
      audacity += 1.0;
      debugPrint("   Ã¢Å¡âïÂ¸Â PersonnalitÃÂ© agressive: +1.0 audace");
    } else if (bot.botBehavior == BotBehavior.balanced) {
      audacity -= 1.0;
      debugPrint("   Ã°Å¸âºÂ¡ïÂ¸Â PersonnalitÃÂ© prudente: -1.0 audace");
    }
    
    // 5ïÂ¸ÂÃ¢ÆÂ£ DifficultÃÂ© influence l'audace (Bronze = moins audacieux)
    if (difficulty.name == "Bronze") {
      audacity *= 0.5;
      debugPrint("   Ã°Å¸Â¥â° Bronze: audace rÃÂ©duite de 50%");
    } else if (difficulty.name == "Platine") {
      audacity *= 1.2;
      debugPrint("   Ã°Å¸Ââ  Platine: audace augmentÃÂ©e de 20%");
    }
    
    return audacity.clamp(-3.0, 5.0); // Limiter entre -3 et +5
  }
  
  /// 🧠 NOUVEAU : Calculer la confiance basÃÂ©e sur l'historique Dutch
  static double _calculateDutchConfidence(Player bot) {
    if (bot.dutchHistory.isEmpty) {
      return 0.0; // Neutre si pas d'historique
    }
    
    // Prendre les 5 derniÃÂ¨res tentatives
    List<DutchAttempt> recentAttempts = bot.dutchHistory.length > 5 
        ? bot.dutchHistory.sublist(bot.dutchHistory.length - 5) 
        : bot.dutchHistory;
    
    // Calculer le taux de rÃÂ©ussite
    int wins = recentAttempts.where((a) => a.won).length;
    double winRate = wins / recentAttempts.length;
    
    // Calculer la prÃÂ©cision des estimations
    double avgAccuracy = recentAttempts.map((a) => a.accuracy).reduce((a, b) => a + b) / recentAttempts.length;
    
    // Confiance = combinaison du taux de rÃÂ©ussite et de la prÃÂ©cision
    double confidence = (winRate * 0.7 + avgAccuracy * 0.3) - 0.5; // CentrÃÂ© sur 0
    
    debugPrint("   Ã°Å¸âÅ  Historique Dutch: $wins/${recentAttempts.length} victoires, prÃÂ©cision: ${(avgAccuracy * 100).toStringAsFixed(0)}%");
    
    return confidence.clamp(-1.0, 1.0); // Entre -1 et +1
  }

  /// 🎴 NOUVELLE STRATÃâ°GIE : DÃÂ©cision basÃÂ©e sur la phase de jeu
  static Future<void> _decideCardAction(
      GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) async {
    debugPrint("Ã°Å¸Â¤â [_decideCardAction] DÃâ°BUT - Phase: $phase");

    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) {
      debugPrint("Ã¢ÂÅ [_decideCardAction] Pas de carte piochÃÂ©e");
      return;
    }

    debugPrint("🎴 [_decideCardAction] Carte piochÃÂ©e: ${drawn.value} (${drawn.points} pts)");

    int drawnVal = drawn.points;
    int replaceIdx = -1;
    
    // 🎲 NOUVEAU : Tracker si c'est une mauvaise pioche
    bool isBadDraw = false;

    // 🎯 PHASE 1 : EXPLORATION (prioritÃÂ© ÃÂ  la dÃÂ©couverte)
    if (phase == BotGamePhase.exploration) {
      debugPrint("Ã°Å¸âÂ PHASE EXPLORATION : Cherche ÃÂ  dÃÂ©couvrir une carte");
      
      // Chercher une carte inconnue ÃÂ  remplacer
      List<int> unknownIndices = [];
      for (int i = 0; i < bot.hand.length; i++) {
        if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
          unknownIndices.add(i);
        }
      }

      if (unknownIndices.isNotEmpty) {
        // Ã¢Åâ¦ STRATÃâ°GIE CLÃâ° : Remplacer une carte inconnue mÃÂªme si la piochÃÂ©e est haute !
        replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
        debugPrint("Ã¢Åâ¦ Remplace carte inconnue #$replaceIdx (dÃÂ©couverte prioritaire)");
        
        bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
        if (!confused) {
          bot.updateMentalMap(replaceIdx, drawn);
        }
        
        GameLogic.replaceCard(gs, replaceIdx);
        return;
      } else {
        debugPrint("Ã¢Å¡Â ïÂ¸Â Toutes les cartes sont connues, passage en optimization");
        // Tomber sur la logique d'optimization
      }
    }

    // 🎯 PHASE 2 & 3 : OPTIMIZATION / ENDGAME (optimiser le score)
    debugPrint("Ã°Å¸âÅ  PHASE ${phase.toString().toUpperCase()} : Optimise le score");
    
    int keepThreshold = difficulty.keepCardThreshold;
    
    // Ajuster selon le comportement
    BotBehavior? behavior = bot.botBehavior;
    switch (behavior) {
      case BotBehavior.fast:
        // Ã°Å¸ÂÆ FAST : Garde Ã¢â°Â¤ 5 points, objectif minimiser cartes
        keepThreshold = 5;
        debugPrint("Ã°Å¸ÂÆ FAST : Seuil fixe ÃÂ  5 points (minimise cartes)");
        break;
      case BotBehavior.aggressive:
        // Ã¢Å¡âïÂ¸Â AGGRESSIVE : Permissif (+1)
        keepThreshold += 1;
        debugPrint("Ã¢Å¡âïÂ¸Â AGGRESSIVE : Seuil permissif $keepThreshold");
        break;
      case BotBehavior.balanced:
        // Ã¢Å¡âïÂ¸Â BALANCED : Adaptatif selon phase et niveau
        if (phase == BotGamePhase.endgame) {
          // En endgame : penche FAST (strict)
          keepThreshold = (5 + difficulty.keepCardThreshold) ~/ 2; // Moyenne FAST + base
        } else {
          // En optimization : entre FAST et AGGRESSIVE
          keepThreshold = difficulty.keepCardThreshold; // Base
        }
        debugPrint("Ã¢Å¡âïÂ¸Â BALANCED : Seuil adaptatif $keepThreshold (phase: $phase)");
        break;
      default:
        break;
    }

    // En endgame, ÃÂªtre plus exigeant (sauf FAST et BALANCED qui gÃÂ¨rent dÃÂ©jÃÂ )
    if (phase == BotGamePhase.endgame && 
        behavior != BotBehavior.fast && 
        behavior != BotBehavior.balanced) {
      keepThreshold -= 1;
      debugPrint("🎯 ENDGAME : Seuil rÃÂ©duit ÃÂ  $keepThreshold");
    }

    // Chercher la pire carte connue
    int worstKnownValue = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        int cardValue = bot.mentalMap[i]!.points;
        if (cardValue > worstKnownValue && cardValue > drawnVal) {
          worstKnownValue = cardValue;
          replaceIdx = i;
        }
      }
    }

    // DÃÂ©cider de garder ou dÃÂ©fausser
    if (replaceIdx != -1 && drawnVal <= keepThreshold) {
      debugPrint("Ã¢Åâ¦ DÃâ°CISION: REMPLACER (index $replaceIdx) - carte piochÃÂ©e ${drawnVal} pts Ã¢â°Â¤ seuil $keepThreshold");

      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }

      GameLogic.replaceCard(gs, replaceIdx);
      
      // Ã¢Åâ¦ Bonne pioche : reset le compteur
      bot.consecutiveBadDraws = 0;
    } else if (replaceIdx != -1 && worstKnownValue > drawnVal + 3) {
      debugPrint("Ã¢Åâ¦ DÃâ°CISION: REMPLACER QUAND MÃÅ ME (pire carte connue: $worstKnownValue pts)");
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
      
      // Ã¢Åâ¦ Bonne pioche : reset le compteur
      bot.consecutiveBadDraws = 0;
    } else {
      debugPrint("Ã°Å¸ââïÂ¸Â DÃâ°CISION: DÃâ°FAUSSER (carte ${drawnVal} pts > seuil $keepThreshold)");
      GameLogic.discardDrawnCard(gs);
      
      // Ã¢ÂÅ Mauvaise pioche : incrÃÂ©menter le compteur
      isBadDraw = true;
    }
    
    // 🎲 NOUVEAU : Tracker les mauvaises pioches consÃÂ©cutives
    if (isBadDraw) {
      bot.consecutiveBadDraws++;
      debugPrint("Ã°Å¸ââ Mauvaise pioche #${bot.consecutiveBadDraws} consÃÂ©cutive");
    }

    debugPrint("🏁 [_decideCardAction] FIN");
  }

  /// Ã¢Åâ¦ NOUVEAU : Tenter un match pendant la phase de rÃÂ©action
  static Future<bool> tryReactionMatch(GameState gameState, Player bot, {int? playerMMR}) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;
    if (gameState.discardPile.isEmpty) return false;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    // Ã°Å¸ÂÆ BONUS FAST : En endgame (Ã¢â°Â¤3 cartes), tente TOUJOURS de matcher
    BotGamePhase phase = _getBotPhase(bot, gameState);
    double matchChance = difficulty.reactionMatchChance;
    
    if (bot.botBehavior == BotBehavior.fast && phase == BotGamePhase.endgame) {
      matchChance = 1.0; // 100% de chance en endgame
      debugPrint("Ã°Å¸ÂÆ FAST ENDGAME : Tente toujours de matcher pour minimiser cartes");
    }
    // Ã¢Å¡âïÂ¸Â BALANCED : Adaptatif selon phase (entre FAST et dÃÂ©faut)
    else if (bot.botBehavior == BotBehavior.balanced && phase == BotGamePhase.endgame) {
      // En endgame : boost comme FAST mais pas 100%
      matchChance = (matchChance + 1.0) / 2; // Moyenne entre base et 100%
      debugPrint("Ã¢Å¡âïÂ¸Â BALANCED ENDGAME : Chance de match boostÃÂ©e ${(matchChance * 100).toStringAsFixed(0)}%");
    }

    // VÃÂ©rifier si le bot tente de matcher
    if (_random.nextDouble() > matchChance) {
      debugPrint("Ã°Å¸Â¤â [ReactionMatch] ${bot.name} ne tente pas de matcher");
      return false;
    }

    PlayingCard topDiscard = gameState.discardPile.last;
    
    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      // Le bot ne connaÃÂ®t que les cartes dans sa mentalMap
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;
        
        if (knownCard.matches(topDiscard)) {
          // VÃÂ©rifier la prÃÂ©cision du bot
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            debugPrint("⚡ [ReactionMatch] ${bot.name} tente un match avec carte #$i");
            
            // Petit dÃÂ©lai avant le match
            int reactionDelay = (500 * (1 - difficulty.reactionSpeed)).round() + 200;
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, i);
            
            if (success) {
              debugPrint("Ã¢Åâ¦ [ReactionMatch] ${bot.name} a rÃÂ©ussi son match!");
              if (i < bot.mentalMap.length) {
                bot.mentalMap.removeAt(i);
              }
              return true;
            } else {
              debugPrint("Ã¢ÂÅ [ReactionMatch] ${bot.name} a ratÃÂ© son match!");
              return false;
            }
          } else {
            debugPrint("Ã°Å¸ËÂµ [ReactionMatch] ${bot.name} hÃÂ©site et rate l'opportunitÃÂ©");
          }
        }
      }
    }

    // Ã¢Åâ¦ Les bots Or/Platine peuvent tenter un match mÃÂªme sur carte inconnue
    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      if (_random.nextDouble() < 0.30) {
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

  // [RESTE DU CODE INCHANGÃâ° - mÃÂ©thodes helper, special powers, etc.]
  
  static Future<void> useBotSpecialPower(GameState gameState, {int? playerMMR}) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    PlayingCard card = gameState.specialCardToActivate!;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    await Future.delayed(const Duration(milliseconds: 1000));

    String val = card.value;

    if (val == '7') {
      int idx = _chooseCardToLook(bot, difficulty);
      GameLogic.lookAtCard(gameState, bot, idx);
      bot.updateMentalMap(idx, bot.hand[idx]);
      debugPrint("Ã°Å¸âÂïÂ¸Â Bot regarde sa carte #$idx et l'enregistre");
    } else if (val == '10') {
      Player? target = _chooseSpyTarget(gameState, bot, difficulty);
      if (target != null && target.hand.isNotEmpty) {
        int idx;
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.7) {
          idx = _random.nextBool() ? 0 : target.hand.length - 1;
        } else {
          idx = _random.nextInt(target.hand.length);
        }
        GameLogic.lookAtCard(gameState, target, idx);
        debugPrint("Ã°Å¸âÂ Bot regarde la carte #$idx de ${target.name}");
      }
    } else if (val == 'V') {
      await _executeValetStrategy(gameState, bot, difficulty);
    } else if (val == 'JOKER') {
      await _executeJokerStrategy(gameState, bot, difficulty);
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisÃÂ© son pouvoir.");
  }

  static void _applyMemoryDecay(Player bot, BotDifficulty difficulty) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;

    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < difficulty.forgetChancePerTurn) {
        bot.forgetCard(i);
        debugPrint("Ã°Å¸âÂ­ Bot oublie sa carte #$i");
      }
    }
  }

  static int _getThinkingTime(BotBehavior? behavior, BotDifficulty difficulty, GameState gameState) {
    if (behavior == null) return 800;

    if (behavior == BotBehavior.balanced) {
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

    if (behavior == BotBehavior.aggressive) {
      return difficulty.name == "Or" || difficulty.name == "Platine" ? 600 : 500;
    }

    return 900;
  }

  static int _chooseCardToLook(Player bot, BotDifficulty difficulty) {
    List<int> unknown = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknown.add(i);
      }
    }
    
    if (unknown.isNotEmpty) {
      return unknown[_random.nextInt(unknown.length)];
    }

    if (bot.botBehavior == BotBehavior.balanced && 
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

  static Player? _chooseSpyTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotBehavior? behavior = bot.botBehavior;

    if ((difficulty.name == "Or" || difficulty.name == "Platine") ||
        behavior == BotBehavior.balanced) {
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      
      if (_random.nextDouble() < 0.80) {
        return opponents.first;
      }
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  static Future<void> _executeValetStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotBehavior? behavior = bot.botBehavior;
    
    Player? target = _chooseValetTarget(gs, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    int myCardIdx = _chooseBadCard(bot);
    int targetIdx;

    if ((difficulty.name == "Or" || difficulty.name == "Platine") && 
        behavior == BotBehavior.balanced) {
      targetIdx = 0;
    } else if (difficulty.name != "Bronze" && _random.nextDouble() < 0.6) {
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
      debugPrint("Ã°Å¸ËÂµ Bot confus ! Il garde l'ancienne valeur en mÃÂ©moire");
    } else {
      bot.forgetCard(myCardIdx);
    }

    GameLogic.swapCards(gs, bot, myCardIdx, target, targetIdx);
    debugPrint("Ã°Å¸ââ Bot ÃÂ©change sa carte #$myCardIdx avec la carte #$targetIdx de ${target.name}");

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotSwapNotification(_context!, bot, target.name, targetIdx);
      await Future.delayed(const Duration(milliseconds: 2000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseValetTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotBehavior? behavior = bot.botBehavior;

    // Bronze : random
    if (difficulty.name == "Bronze") {
      return opponents[_random.nextInt(opponents.length)];
    }

    // Ã°Å¸ÂÆ FAST : Cible le joueur avec le PLUS de cartes
    if (behavior == BotBehavior.fast) {
      opponents.sort((a, b) => b.hand.length.compareTo(a.hand.length));
      debugPrint("Ã°Å¸ÂÆ FAST : Cible ${opponents.first.name} (${opponents.first.hand.length} cartes)");
      return opponents.first;
    }

    // Ã¢Å¡âïÂ¸Â AGGRESSIVE : Cible humain ou joueurs avec peu de cartes
    if (behavior == BotBehavior.aggressive) {
      // Or/Platine : prÃÂ©fÃÂ¨re l'humain
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        Player? human = opponents.where((p) => p.isHuman).firstOrNull;
        if (human != null && _random.nextDouble() < 0.65) {
          debugPrint("Ã¢Å¡âïÂ¸Â AGGRESSIVE : Cible l'humain pour l'ÃÂ©change");
          return human;
        }
      }
      
      // Sinon cible les joueurs avec peu de cartes (pour les gÃÂªner)
      List<Player> lowCardTargets = opponents.where((p) => p.hand.length <= 3).toList();
      if (lowCardTargets.isNotEmpty && _random.nextDouble() < 0.75) {
        return lowCardTargets[_random.nextInt(lowCardTargets.length)];
      }
      return opponents[_random.nextInt(opponents.length)];
    }

    // Ã¢Å¡âïÂ¸Â BALANCED : Hybride FAST + AGGRESSIVE (plus complexe selon niveau)
    if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (_random.nextDouble() < 0.70) {
          return _selectValetTargetWeighted(opponents, difficulty);
        }
        return opponents[_random.nextInt(opponents.length)];
      }
      
      // Or/Platine : HYBRIDE intelligent
      // 50% style FAST (cible plus de cartes), 50% style AGGRESSIVE (cible humain/peu de cartes)
      if (_random.nextDouble() < 0.50) {
        // Style FAST : cible joueur avec PLUS de cartes
        opponents.sort((a, b) => b.hand.length.compareTo(a.hand.length));
        debugPrint("Ã¢Å¡âïÂ¸Â BALANCED (style FAST) : Cible ${opponents.first.name} (${opponents.first.hand.length} cartes)");
        return opponents.first;
      } else {
        // Style AGGRESSIVE : cible humain ou peu de cartes
        Player? human = opponents.where((p) => p.isHuman).firstOrNull;
        if (human != null && _random.nextDouble() < 0.50) {
          debugPrint("Ã¢Å¡âïÂ¸Â BALANCED (style AGGRESSIVE) : Cible l'humain");
          return human;
        }
        // Ou cible weighted
        return _selectValetTargetWeighted(opponents, difficulty);
      }
    }

    // Fallback
    return opponents[_random.nextInt(opponents.length)];
  }

  static Player _selectValetTargetWeighted(List<Player> opponents, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in opponents) {
      double score = 0.0;
      
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

  static Future<void> _executeJokerStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotBehavior? behavior = bot.botBehavior;
    
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    
    if (possibleTargets.isEmpty) {
      possibleTargets = [bot];
    }

    Player? target;

    // Ã°Å¸ÂÆ FAST : Cible les joueurs avec MEILLEUR SCORE pour les ralentir
    if (behavior == BotBehavior.fast) {
      // Trier par score estimÃÂ© (plus bas = meilleur)
      possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      target = possibleTargets.first; // Le joueur avec le meilleur score
      debugPrint("Ã°Å¸ÂÆ FAST : Joker sur ${target.name} (score ~${target.getEstimatedScore()}) pour le ralentir");
    }
    // Ã¢Å¡âïÂ¸Â AGGRESSIVE : Cible l'humain
    else if (behavior == BotBehavior.aggressive) {
      Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
      
      if (human != null && (difficulty.name == "Or" || difficulty.name == "Platine")) {
        if (_random.nextDouble() < 0.70) {
          target = human;
          debugPrint("Ã¢Å¡âïÂ¸Â AGGRESSIVE : Joker sur l'humain!");
        }
      }
      
      if (target == null) {
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.6) {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
        debugPrint("Ã¢Å¡âïÂ¸Â Joker rapide sur ${target.name}");
      }
    }
    // Ã¢Å¡âïÂ¸Â BALANCED : Hybride FAST + AGGRESSIVE (plus complexe selon niveau)
    else if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (difficulty.name != "Bronze") {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
          debugPrint("Ã¢Å¡âïÂ¸Â BALANCED : Joker stratÃÂ©gique sur ${target.name}");
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
      }
      // Or/Platine : HYBRIDE intelligent
      else {
        // 50% style FAST (meilleur score), 50% style AGGRESSIVE (humain)
        if (_random.nextDouble() < 0.50) {
          // Style FAST : cible joueur avec MEILLEUR score
          possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
          target = possibleTargets.first;
          debugPrint("Ã¢Å¡âïÂ¸Â BALANCED (style FAST) : Joker sur ${target.name} (score ~${target.getEstimatedScore()})");
        } else {
          // Style AGGRESSIVE : cible humain
          Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
          if (human != null && _random.nextDouble() < 0.60) {
            target = human;
            debugPrint("Ã¢Å¡âïÂ¸Â BALANCED (style AGGRESSIVE) : Joker sur l'humain");
          } else {
            target = _selectJokerTargetWeighted(possibleTargets, difficulty);
          }
        }
      }
    }
    // Fallback
    else {
      if (difficulty.name != "Bronze" && _random.nextDouble() < 0.3) {
        target = _selectJokerTargetWeighted(possibleTargets, difficulty);
      } else {
        target = possibleTargets[_random.nextInt(possibleTargets.length)];
      }
    }

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
      debugPrint("Ã°Å¸Åâ¬ Bot mÃÂ©lange ses propres cartes et oublie tout!");
    }

    debugPrint("Ã°Å¸ÆÂ Bot mÃÂ©lange les cartes de ${target.name}");

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotJokerNotification(_context!, bot, target.name);
      await Future.delayed(const Duration(milliseconds: 3000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player _selectJokerTargetWeighted(List<Player> targets, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in targets) {
      double score = 0.0;
      
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

  /// 🎯 NOUVEAU : Obtenir BotDifficulty depuis BotSkillLevel
  static BotDifficulty _getSkillDifficulty(BotSkillLevel? level) {
    if (level == null) return BotDifficulty.silver;
    
    switch (level) {
      case BotSkillLevel.bronze:
        return BotDifficulty.bronze;
      case BotSkillLevel.silver:
        return BotDifficulty.silver;
      case BotSkillLevel.gold:
        return BotDifficulty.gold;
    }
  }

  // ========== 🎭 COMPORTEMENTS DES BOTS ==========

  /// Ã°Å¸ÂÆ FAST : Ajuster le seuil Dutch pour ÃÂªtre plus agressif
  static int _applyFastBehavior(int baseThreshold) {
    return baseThreshold + 2; // Dutch plus tÃÂ´t
  }

  /// Ã¢Å¡âïÂ¸Â AGGRESSIVE : Doit-on cibler l'humain ?
  static bool _shouldTargetHuman(BotBehavior? behavior, BotDifficulty difficulty) {
    if (behavior != BotBehavior.aggressive) return false;
    
    // Aggressive cible l'humain frÃÂ©quemment
    switch (difficulty.name) {
      case "Bronze":
        return _random.nextDouble() < 0.50; // 50%
      case "Argent":
        return _random.nextDouble() < 0.70; // 70%
      case "Or":
      case "Platine":
        return _random.nextDouble() < 0.85; // 85%
      default:
        return false;
    }
  }

  /// 🧠 BALANCED : Observer les dÃ©fausses de l'humain
  static bool _isHumanThreatening(GameState gs) {
    try {
      Player human = gs.players.firstWhere((p) => p.isHuman);
      return human.hand.length <= 3;
    } catch (e) {
      return false;
    }
  }
}