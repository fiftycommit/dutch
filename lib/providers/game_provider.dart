import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart'; 
import '../services/game_logic.dart'; 
import '../services/bot_ai.dart';     
import '../services/stats_service.dart'; 

class GameProvider with ChangeNotifier {
  GameState? _gameState;
  GameState? get gameState => _gameState;
  bool get hasActiveGame => _gameState != null;
  
  bool isProcessing = false;
  String? statusMessage;
  Set<int> shakingCardIndices = {};

  Timer? _reactionTimer;
  int _currentReactionTimeMs = 3000; 
  int _currentSlotId = 1;

  void createNewGame({
    required List<Player> players, 
    required GameMode gameMode, 
    required Difficulty difficulty, 
    required int reactionTimeMs,
    int tournamentRound = 1,
    int saveSlot = 1, 
  }) {
    debugPrint("🎮 [createNewGame] CRÉATION NOUVELLE PARTIE");
    debugPrint("   - Joueurs: ${players.map((p) => p.name).toList()}");
    debugPrint("   - Mode: $gameMode");
    debugPrint("   - Difficulté: $difficulty");
    
    _gameState = GameLogic.initializeGame(
      players: players, 
      gameMode: gameMode, 
      difficulty: difficulty, 
      tournamentRound: tournamentRound
    );
    _currentReactionTimeMs = reactionTimeMs;
    _currentSlotId = saveSlot;
    
    debugPrint("   - Phase initiale: ${_gameState!.phase}");
    debugPrint("   - Joueur initial: ${_gameState!.currentPlayer.name}");
    debugPrint("   - Est bot: ${!_gameState!.currentPlayer.isHuman}");
    
    shakingCardIndices.clear();
    isProcessing = false;
    notifyListeners();
  }

  // ✅ NOUVELLE MÉTHODE: Forcer le check du tour bot
  void checkIfBotShouldPlay() {
    debugPrint("🔍 [checkIfBotShouldPlay] Vérification...");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    if (isProcessing) {
      debugPrint("   ⏸️ Déjà en traitement");
      return;
    }
    
    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   ⏸️ Phase incorrecte: ${_gameState!.phase}");
      return;
    }
    
    if (_gameState!.currentPlayer.isHuman) {
      debugPrint("   👤 Tour humain");
      return;
    }
    
    debugPrint("   ✅ Bot doit jouer, déclenchement...");
    _checkAndPlayBotTurn();
  }

  void drawCard() {
    debugPrint("🎴 [drawCard] DÉBUT");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   ❌ Phase incorrecte: ${_gameState!.phase}");
      return;
    }
    
    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   ❌ Ce n'est pas le tour de l'humain");
      return;
    }
    
    if (_gameState!.drawnCard != null) {
      debugPrint("   ❌ Une carte a déjà été piochée");
      return;
    }
    
    shakingCardIndices.clear(); 
    GameLogic.drawCard(_gameState!);
    
    debugPrint("   ✅ Carte piochée: ${_gameState!.drawnCard?.value}");
    notifyListeners();
  }

  void replaceCard(int cardIndex) {
    debugPrint("🔄 [replaceCard] DÉBUT - Index: $cardIndex");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   ❌ Pas le tour de l'humain");
      return;
    }
    
    if (_gameState!.drawnCard == null) {
      debugPrint("   ❌ Pas de carte piochée");
      return;
    }
    
    final cardValue = _gameState!.drawnCard!.value;
    debugPrint("   - Carte à insérer: $cardValue");
    
    GameLogic.replaceCard(_gameState!, cardIndex);
    debugPrint("   ✅ Carte remplacée");
    
    notifyListeners();
    
    if (_checkInstantEnd()) {
      debugPrint("   🏁 Fin instantanée détectée");
      return;
    }

    if (_gameState!.isWaitingForSpecialPower) {
      debugPrint("   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
      Future.delayed(const Duration(milliseconds: 500)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      debugPrint("   ⏱️ Lancement phase réaction");
      startReactionPhase();
    }
  }

  void discardDrawnCard() {
    debugPrint("🗑️ [discardDrawnCard] DÉBUT");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   ❌ Pas le tour de l'humain");
      return;
    }
    
    if (_gameState!.drawnCard == null) {
      debugPrint("   ❌ Pas de carte piochée");
      return;
    }
    
    final cardValue = _gameState!.drawnCard!.value;
    debugPrint("   - Carte défaussée: $cardValue");
    
    GameLogic.discardDrawnCard(_gameState!);
    notifyListeners();

    if (_checkInstantEnd()) {
      debugPrint("   🏁 Fin instantanée détectée");
      return;
    }

    if (_gameState!.isWaitingForSpecialPower) {
      debugPrint("   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
      notifyListeners();
    } else {
      debugPrint("   ⏱️ Lancement phase réaction");
      startReactionPhase();
    }
  }

  void attemptMatch(int cardIndex, {Player? forcedPlayer}) async {
    debugPrint("🔥🔥🔥 [attemptMatch] ═══════════════════════════════════════");
    debugPrint("🎯 [attemptMatch] ENTRÉE DANS LA FONCTION");
    debugPrint("   📍 Index carte: $cardIndex");
    debugPrint("   📍 forcedPlayer fourni: ${forcedPlayer?.name ?? 'NULL'}");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL - ABANDON");
      debugPrint("🔥🔥🔥 [attemptMatch] FIN PRÉMATURÉE ════════════════════════");
      return;
    }
    
    debugPrint("   ✅ GameState OK");
    debugPrint("   📍 Phase actuelle: ${_gameState!.phase}");
    
    if (_gameState!.phase != GamePhase.reaction) {
      debugPrint("   ❌ Phase incorrecte: ${_gameState!.phase}");
      debugPrint("   ⚠️ ATTENDU: GamePhase.reaction");
      debugPrint("🔥🔥🔥 [attemptMatch] FIN - Mauvaise phase ═══════════════════");
      return;
    }

    debugPrint("   ✅ Phase REACTION confirmée");

    Player player = forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    debugPrint("   📍 Joueur sélectionné: ${player.name}");
    debugPrint("   📍 ID joueur: ${player.id}");
    debugPrint("   📍 Est humain: ${player.isHuman}");
    debugPrint("   📍 Taille main: ${player.hand.length}");
    debugPrint("   📍 Main complète: ${player.hand.map((c) => c.value).toList()}");
    
    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("   ❌ Index hors limites!");
      debugPrint("   - Index demandé: $cardIndex");
      debugPrint("   - Taille main: ${player.hand.length}");
      debugPrint("🔥🔥🔥 [attemptMatch] FIN - Index invalide ═══════════════════");
      return;
    }
    
    debugPrint("   ✅ Index valide");
    debugPrint("   📍 Carte du joueur à l'index $cardIndex: ${player.hand[cardIndex].value}");
    debugPrint("   📍 Carte du dessus de défausse: ${_gameState!.topDiscardCard?.value ?? 'NULL'}");
    
    debugPrint("   🎲 APPEL GameLogic.matchCard...");
    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);
    debugPrint("   📊 RÉSULTAT matchCard: ${success ? 'SUCCÈS ✅' : 'ÉCHEC ❌'}");
    
    if (success) {
      debugPrint("   🎉 MATCH RÉUSSI!");
      shakingCardIndices.clear();
      
      if (_gameState!.isWaitingForSpecialPower) {
        debugPrint("   ⚡ Pouvoir spécial détecté");
        notifyListeners();
        
        if (!player.isHuman) {
          await BotAI.useBotSpecialPower(_gameState!);
          notifyListeners();
          
          if (_gameState!.phase == GamePhase.reaction) {
            _extendReactionTime(1000);
          }
        }
      } else {
        debugPrint("   ⏱️ Prolongation du timer de réaction (+1000ms)");
        _extendReactionTime(1000);
        notifyListeners();
      }
    } else {
      debugPrint("   ❌ MATCH ÉCHOUÉ - Pénalité appliquée");
      
      if (player.isHuman) {
        debugPrint("   🔔 Animation shake pour joueur humain");
        shakingCardIndices.add(cardIndex);
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 500));
        shakingCardIndices.remove(cardIndex);
        notifyListeners();
      }
    }
    
    debugPrint("🔥🔥🔥 [attemptMatch] FIN ═══════════════════════════════════════");
  }

  void _extendReactionTime(int milliseconds) {
    debugPrint("⏱️ [_extendReactionTime] Extension de ${milliseconds}ms");
    
    if (_reactionTimer == null || !_reactionTimer!.isActive) {
      debugPrint("   ⚠️ Timer non actif");
      return;
    }
    
    _reactionTimer?.cancel();
    
    _reactionTimer = Timer(Duration(milliseconds: milliseconds), () {
      debugPrint("   ⏰ Timer expiré -> endReactionPhase");
      endReactionPhase();
    });
  }

  void executeLookAtCard(Player target, int cardIndex) {
    debugPrint("👁️ [executeLookAtCard] ${target.name} - Index: $cardIndex");
    
    if (_gameState == null) return;
    GameLogic.lookAtCard(_gameState!, target, cardIndex);
    notifyListeners();
    skipSpecialPower(); 
  }

  void executeSwapCard(int myCardIndex, Player target, int targetCardIndex) {
    debugPrint("🔄 [executeSwapCard] Ma carte: $myCardIndex <-> ${target.name}: $targetCardIndex");
    
    if (_gameState == null) return;
    Player me = _gameState!.players.firstWhere((p) => p.isHuman);
    GameLogic.swapCards(_gameState!, me, myCardIndex, target, targetCardIndex);
    notifyListeners();
    skipSpecialPower();
  }

  void executeJokerEffect(Player targetPlayer) {
    debugPrint("🃏 [executeJokerEffect] Cible: ${targetPlayer.name}");
    
    if (_gameState == null) return;
    GameLogic.jokerEffect(_gameState!, targetPlayer);
    notifyListeners();
    skipSpecialPower();
  }

  void skipSpecialPower() {
    debugPrint("⏭️ [skipSpecialPower] DÉBUT");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    debugPrint("   - Phase avant: ${_gameState!.phase}");
    
    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    _gameState!.addToHistory("Pouvoir terminé");
    
    notifyListeners();
    
    if (_checkInstantEnd()) {
      debugPrint("   🏁 Fin instantanée");
      return;
    }
    
    if (_gameState!.phase == GamePhase.reaction) {
       debugPrint("   ⏱️ Prolongation timer réaction");
       _extendReactionTime(1000);
    } else if (_gameState!.phase == GamePhase.playing) {
       debugPrint("   🎬 Lancement phase réaction");
       startReactionPhase();
    }
    
    debugPrint("   - Phase après: ${_gameState!.phase}");
  }

  void callDutch() {
    debugPrint("📢 [callDutch] DUTCH APPELÉ");
    
    if (_gameState == null) return;
    GameLogic.callDutch(_gameState!);
    notifyListeners();
    endGame(); 
  }

  void startReactionPhase({int bonusTime = 0}) {
    debugPrint("⏱️ [startReactionPhase] DÉBUT (bonus: ${bonusTime}ms)");
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    _gameState!.phase = GamePhase.reaction;
    _gameState!.reactionStartTime = DateTime.now();
    
    debugPrint("   ✅ Phase réaction activée");
    notifyListeners();

    _simulateBotReaction();

    _reactionTimer?.cancel();
    final totalTime = _currentReactionTimeMs + bonusTime;
    debugPrint("   ⏰ Timer: ${totalTime}ms");
    
    _reactionTimer = Timer(Duration(milliseconds: totalTime), () {
      debugPrint("   ⏰ Timer expiré -> endReactionPhase");
      endReactionPhase();
    });
  }

  void endReactionPhase() {
    debugPrint("🏁 [endReactionPhase] DÉBUT");
    
    _reactionTimer?.cancel();
    
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    debugPrint("   - Phase avant: ${_gameState!.phase}");
    debugPrint("   - Joueur avant: ${_gameState!.currentPlayer.name}");

    // Nettoyer l'état des pouvoirs
    _gameState!.isWaitingForSpecialPower = false; 
    _gameState!.specialCardToActivate = null;
    shakingCardIndices.clear();

    // Vérifier si Dutch a été crié
    if (_gameState!.dutchCallerId != null) {
       debugPrint("   📢 Dutch détecté -> Fin de partie");
       _gameState!.phase = GamePhase.dutchCalled;
       notifyListeners();
       return;
    }

    // Passer au tour suivant
    _gameState!.phase = GamePhase.playing;
    _gameState!.nextTurn();
    _gameState!.reactionStartTime = null;
    
    debugPrint("   - Phase après: ${_gameState!.phase}");
    debugPrint("   - Joueur après: ${_gameState!.currentPlayer.name}");
    
    notifyListeners();

    // Vérifier si c'est le tour d'un bot
    _checkAndPlayBotTurn();
  }

  void _simulateBotReaction() async {
    debugPrint("🤖 [_simulateBotReaction] Simulation réaction bots");
    
    if (_gameState == null) return;
    await Future.delayed(Duration(milliseconds: Random().nextInt(1000) + 500));
    
    if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
      debugPrint("   ⚠️ Phase changée, annulation");
      return;
    }

    PlayingCard? topCard = _gameState!.topDiscardCard;
    if (topCard == null) {
      debugPrint("   ⚠️ Pas de carte sur la défausse");
      return;
    }

    debugPrint("   - Carte défausse: ${topCard.value}");

    for (var bot in _gameState!.players.where((p) => !p.isHuman)) {
       if (Random().nextDouble() > 0.3) { 
         for (int i = 0; i < bot.hand.length; i++) {
           if (bot.hand[i].value == topCard.value) {
             debugPrint("   ✅ ${bot.name} tente un match");
             attemptMatch(i, forcedPlayer: bot);
             return; 
           }
         }
       }
    }
    
    debugPrint("   - Aucun bot n'a réagi");
  }

  bool _checkInstantEnd() {
    if (_gameState == null) return false;
    if (_gameState!.deck.isEmpty) {
      debugPrint("🏁 [_checkInstantEnd] Deck vide -> Fin de partie");
      endGame();
      return true;
    }
    return false;
  }

  Future<void> _checkAndPlayBotTurn() async {
    debugPrint("🎮 [_checkAndPlayBotTurn] DÉBUT");
  
    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }
    
    if (_gameState!.phase == GamePhase.ended) {
      debugPrint("   ❌ Partie terminée");
      return;
    }
  
    if (_checkInstantEnd()) {
      debugPrint("   ❌ Fin instantanée");
      return;
    }

    debugPrint("   - Joueur actuel: ${_gameState!.currentPlayer.name} (isHuman: ${_gameState!.currentPlayer.isHuman})");
    debugPrint("   - Phase actuelle: ${_gameState!.phase}");

    // Si c'est le tour d'un humain → rien à faire
    if (_gameState!.currentPlayer.isHuman) {
      debugPrint("   ✅ Tour humain, on s'arrête");
      isProcessing = false;
      notifyListeners();
      return;
    }

    // Boucle bot
    int loopCount = 0;
    while (_gameState != null &&
          !_gameState!.currentPlayer.isHuman && 
          _gameState!.phase == GamePhase.playing) {
    
      loopCount++;
      debugPrint("   🔄 BOUCLE $loopCount - Joueur: ${_gameState!.currentPlayer.name}");
    
      if (loopCount > 10) {
        debugPrint("   🚨 BOUCLE INFINIE DÉTECTÉE - ARRÊT FORCÉ");
        break;
      }
    
      if (_checkInstantEnd()) {
        debugPrint("   ❌ Fin instantanée (dans boucle)");
        return;
      }

      isProcessing = true;
      notifyListeners();

      debugPrint("   ⏳ Attente 800ms...");
      await Future.delayed(const Duration(milliseconds: 800));
    
      if (_gameState == null) {
        debugPrint("   ❌ GameState devenu NULL");
        break;
      }

      try {
        debugPrint("   🤖 Le bot ${_gameState!.currentPlayer.name} joue...");
        
        // Le bot joue son tour
        await BotAI.playBotTurn(_gameState!);
        debugPrint("   ✅ Tour du bot terminé");
        
        notifyListeners(); 

        // Vérifier si Dutch a été crié
        if (_gameState!.phase == GamePhase.dutchCalled) {
          debugPrint("   📢 DUTCH crié ! Fin de partie");
          endGame();
          return;
        }

        // Gérer le pouvoir spécial si nécessaire
        if (_gameState!.isWaitingForSpecialPower) {
          debugPrint("   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
          await Future.delayed(const Duration(milliseconds: 800));
          
          await BotAI.useBotSpecialPower(_gameState!);
          debugPrint("   ✅ Pouvoir spécial utilisé");
          
          notifyListeners();
          
          // Nettoyer l'état du pouvoir
          _gameState!.isWaitingForSpecialPower = false;
          _gameState!.specialCardToActivate = null;
          debugPrint("   🧹 État du pouvoir nettoyé");
        }
        
      } catch (e, stackTrace) {
        debugPrint("   🚨 ERREUR Bot: $e");
        debugPrint("   Stack trace: $stackTrace");
        
        // En cas d'erreur, défausser la carte piochée
        if (_gameState != null && _gameState!.drawnCard != null) {
          _gameState!.discardPile.add(_gameState!.drawnCard!);
          _gameState!.drawnCard = null;
          debugPrint("   🗑️ Carte piochée défaussée (erreur)");
        }
      }

      debugPrint("   📊 Phase après actions: ${_gameState!.phase}");

      // TOUJOURS lancer la phase de réaction après une action
      if (_gameState != null && _gameState!.phase == GamePhase.playing) {
        debugPrint("   ⏱️ Lancement phase réaction...");
        startReactionPhase();
        debugPrint("   ✅ Phase réaction lancée, sortie de boucle");
        break;
      } else {
        debugPrint("   ⚠️ Phase n'est plus 'playing' (${_gameState!.phase}), sortie boucle");
        break;
      }
    }

    debugPrint("   🏁 FIN - isProcessing = false");
    isProcessing = false;
    notifyListeners();
  }

  void endGame() {
    debugPrint("🏁 [endGame] FIN DE PARTIE");
    
    if (_gameState == null) return;
    GameLogic.endGame(_gameState!);
    
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);
    bool isWin = _gameState!.getFinalRanking().first.id == human.id;
    bool calledDutch = _gameState!.dutchCallerId == human.id;
    bool wonDutch = calledDutch && isWin;

    debugPrint("   - Victoire: $isWin");
    debugPrint("   - Dutch appelé: $calledDutch");
    debugPrint("   - Dutch gagné: $wonDutch");

    StatsService.saveGameResult(
      isWin: isWin,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      slotId: _currentSlotId, 
    );
    
    notifyListeners();
  }

  void startNextTournamentRound() {
    debugPrint("🏆 [startNextTournamentRound] Manche suivante");
    
    if (_gameState == null) return;
    List<Player> ranking = _gameState!.getFinalRanking();
    List<Player> survivors = [];
    int playersToKeep = min(3, ranking.length - 1);
    
    for (int i = 0; i < playersToKeep; i++) {
      Player p = ranking[i];
      survivors.add(Player(
        id: p.id, 
        name: p.name, 
        isHuman: p.isHuman, 
        botPersonality: p.botPersonality,
        position: i
      ));
    }
    
    if (survivors.length < 2) return;

    debugPrint("   - Survivants: ${survivors.map((p) => p.name).toList()}");

    createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId
    );
  }
}