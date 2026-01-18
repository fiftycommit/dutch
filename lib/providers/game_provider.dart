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

  DateTime? _reactionPauseTime;
  int? _remainingReactionTimeMs;

  // 🎯 NOUVEAU : MMR du joueur pour le SBMM
  int? _playerMMR;
  int? get playerMMR => _playerMMR; // ✅ GETTER PUBLIC

  void createNewGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    required int reactionTimeMs,
    int tournamentRound = 1,
    int saveSlot = 1,
    bool useSBMM = false, // 🆕 PARAMÈTRE SBMM
  }) async {
    debugPrint("🎮 [createNewGame] CRÉATION NOUVELLE PARTIE");
    debugPrint("   - Joueurs: ${players.map((p) => p.name).toList()}");
    debugPrint("   - Mode: $gameMode");
    debugPrint("   - Difficulté: $difficulty");
    debugPrint("   - SBMM: $useSBMM");

    _gameState = GameLogic.initializeGame(
        players: players,
        gameMode: gameMode,
        difficulty: difficulty,
        tournamentRound: tournamentRound);
    _currentReactionTimeMs = reactionTimeMs;
    _currentSlotId = saveSlot;

    // 🎯 NOUVEAU : Charger le MMR UNIQUEMENT si SBMM activé
    if (useSBMM) {
      final stats = await StatsService.getStats(slotId: saveSlot);
      _playerMMR = stats['mmr'] ?? 0;
      debugPrint("   - MMR du joueur: $_playerMMR (SBMM activé)");
    } else {
      _playerMMR = null; // ✅ Pas de MMR en mode manuel
      debugPrint("   - Mode manuel (pas de MMR)");
    }

    // 🧠 NOUVEAU : Initialiser les cartes mentales des bots
    for (var player in _gameState!.players) {
      if (!player.isHuman) {
        player.mentalMap = List.filled(player.hand.length, null);
      }
    }

    debugPrint("   - Phase initiale: ${_gameState!.phase}");
    debugPrint("   - Joueur initial: ${_gameState!.currentPlayer.name}");
    debugPrint("   - Est bot: ${!_gameState!.currentPlayer.isHuman}");

    shakingCardIndices.clear();
    isProcessing = false;
    notifyListeners();
  }

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
      debugPrint(
          "   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
      _pauseReactionTimer(); // ✅ NOUVEAU : Pause si on était en réaction
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
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
      debugPrint(
          "   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
      _pauseReactionTimer(); // ✅ NOUVEAU : Pause si on était en réaction
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      debugPrint("   ⏱️ Lancement phase réaction");
      startReactionPhase();
    }
  }

  void attemptMatch(int cardIndex, {Player? forcedPlayer}) async {
    debugPrint("🔥 [attemptMatch] ENTRÉE");
    debugPrint("   🔍 Index carte: $cardIndex");
    debugPrint("   🔍 forcedPlayer fourni: ${forcedPlayer?.name ?? 'NULL'}");

    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    debugPrint("   ✅ GameState OK");
    debugPrint("   🔍 Phase actuelle: ${_gameState!.phase}");

    if (_gameState!.phase != GamePhase.reaction) {
      debugPrint("   ❌ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    debugPrint("   ✅ Phase REACTION confirmée");

    Player player =
        forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    debugPrint("   🔍 Joueur sélectionné: ${player.name}");

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("   ❌ Index hors limites!");
      return;
    }

    debugPrint("   🎲 APPEL GameLogic.matchCard...");
    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);
    debugPrint("   📊 RÉSULTAT matchCard: ${success ? 'SUCCÈS ✅' : 'ÉCHEC ❌'}");

    if (success) {
      debugPrint("   🎉 MATCH RÉUSSI!");
      shakingCardIndices.clear();

      if (_gameState!.isWaitingForSpecialPower) {
        debugPrint("   ⚡ Pouvoir spécial détecté");
        _pauseReactionTimer();
        notifyListeners();

        if (!player.isHuman) {
          await BotAI.useBotSpecialPower(_gameState!, playerMMR: _playerMMR);
          notifyListeners();

          if (_gameState!.phase == GamePhase.reaction) {
            _resumeReactionTimer();
            _extendReactionTime(1000);
          }
        } else {
          debugPrint(
              "   ⏸️ Attente de l'utilisation du pouvoir par l'humain...");

          while (_gameState != null && _gameState!.isWaitingForSpecialPower) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

          debugPrint("   ✅ Pouvoir utilisé, reprise du timer");

          if (_gameState != null && _gameState!.phase == GamePhase.reaction) {
            _resumeReactionTimer();
          }
        }
      } else {
        debugPrint("   ⏱️ Prolongation du timer de réaction (+2000ms)");
        _extendReactionTime(2000);
        notifyListeners();
      }
    } else {
      debugPrint("   ❌ MATCH ÉCHOUÉ - Pénalité appliquée par GameLogic");

      int penaltyCardIndex =
          player.hand.length - 1; // Dernière carte = pénalité

      debugPrint("   📍 Shake rouge sur carte de pénalité #$penaltyCardIndex");

      // ✅ ANIMATION SHAKE SUR LA NOUVELLE CARTE (si c'est le joueur humain)
      if (player.isHuman) {
        shakingCardIndices.clear();
        shakingCardIndices.add(penaltyCardIndex);
        notifyListeners();

        await Future.delayed(const Duration(milliseconds: 500));

        shakingCardIndices.remove(penaltyCardIndex);
        notifyListeners();
      }
    }
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
    debugPrint(
        "🔄 [executeSwapCard] Ma carte: $myCardIndex <-> ${target.name}: $targetCardIndex");

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
      debugPrint("   ⏱️ Reprise timer réaction");
      _resumeReactionTimer(); // ✅ NOUVEAU : au lieu de _extendReactionTime
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

  void _pauseReactionTimer() {
    if (_reactionTimer == null || !_reactionTimer!.isActive) {
      debugPrint("⏸️ [_pauseReactionTimer] Aucun timer actif");
      return;
    }

    if (_gameState == null || _gameState!.reactionStartTime == null) {
      debugPrint("⏸️ [_pauseReactionTimer] Pas de temps de départ");
      return;
    }

    // Calculer le temps écoulé
    final elapsed = DateTime.now().difference(_gameState!.reactionStartTime!);
    _remainingReactionTimeMs = _currentReactionTimeMs - elapsed.inMilliseconds;

    if (_remainingReactionTimeMs! < 0) {
      _remainingReactionTimeMs = 0;
    }

    debugPrint(
        "⏸️ [_pauseReactionTimer] Timer en pause - Temps restant: ${_remainingReactionTimeMs}ms");

    // Annuler le timer
    _reactionTimer?.cancel();
    _reactionPauseTime = DateTime.now();
  }

  void _resumeReactionTimer() {
    if (_remainingReactionTimeMs == null) {
      debugPrint("▶️ [_resumeReactionTimer] Pas de temps restant sauvegardé");
      return;
    }

    if (_gameState == null) {
      debugPrint("▶️ [_resumeReactionTimer] GameState NULL");
      return;
    }

    debugPrint(
        "▶️ [_resumeReactionTimer] Reprise avec ${_remainingReactionTimeMs}ms restants");

    // Recréer le timer avec le temps restant
    _reactionTimer =
        Timer(Duration(milliseconds: _remainingReactionTimeMs!), () {
      debugPrint("   ⏰ Timer expiré -> endReactionPhase");
      endReactionPhase();
    });

    // Réinitialiser le temps de pause
    _reactionPauseTime = null;
    _remainingReactionTimeMs = null;
  }

  void pauseReactionTimerForNotification() {
    debugPrint(
        "⏸️ [pauseReactionTimerForNotification] Pause pour notification");
    _pauseReactionTimer();
  }

  void resumeReactionTimerAfterNotification() {
    debugPrint(
        "▶️ [resumeReactionTimerAfterNotification] Reprise après notification");
    _resumeReactionTimer();
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

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    shakingCardIndices.clear();

    if (_gameState!.dutchCallerId != null) {
      debugPrint("   📢 Dutch détecté -> Fin de partie");
      _gameState!.phase = GamePhase.dutchCalled;
      notifyListeners();
      return;
    }

    _gameState!.phase = GamePhase.playing;
    _gameState!.nextTurn();
    _gameState!.reactionStartTime = null;

    debugPrint("   - Phase après: ${_gameState!.phase}");
    debugPrint("   - Joueur après: ${_gameState!.currentPlayer.name}");

    notifyListeners();

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

    debugPrint("   - Carte défausse: ${topCard.displayName}");

    for (var bot in _gameState!.players.where((p) => !p.isHuman)) {
      if (Random().nextDouble() > 0.3) {
        // 🧠 MODIFIÉ : Le bot vérifie sa carte mentale, pas la réalité
        for (int i = 0; i < bot.mentalMap.length; i++) {
          if (bot.mentalMap[i] != null && bot.mentalMap[i]!.matches(topCard)) {
            debugPrint(
                "   ✅ ${bot.name} pense avoir un match avec ${bot.mentalMap[i]!.displayName}");
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

    debugPrint(
        "   - Joueur actuel: ${_gameState!.currentPlayer.name} (isHuman: ${_gameState!.currentPlayer.isHuman})");
    debugPrint("   - Phase actuelle: ${_gameState!.phase}");

    if (_gameState!.currentPlayer.isHuman) {
      debugPrint("   ✅ Tour humain, on s'arrête");
      isProcessing = false;
      notifyListeners();
      return;
    }

    int loopCount = 0;
    while (_gameState != null &&
        !_gameState!.currentPlayer.isHuman &&
        _gameState!.phase == GamePhase.playing) {
      loopCount++;
      debugPrint(
          "   🔄 BOUCLE $loopCount - Joueur: ${_gameState!.currentPlayer.name}");

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

        // 🎯 MODIFIÉ : Passer le MMR au bot
        await BotAI.playBotTurn(_gameState!, playerMMR: _playerMMR);
        debugPrint("   ✅ Tour du bot terminé");

        notifyListeners();

        if (_gameState!.phase == GamePhase.dutchCalled) {
          debugPrint("   📢 DUTCH crié ! Fin de partie");
          endGame();
          return;
        }

        if (_gameState!.isWaitingForSpecialPower) {
          debugPrint(
              "   ⚡ Pouvoir spécial en attente: ${_gameState!.specialCardToActivate?.value}");
          await Future.delayed(const Duration(milliseconds: 800));

          // 🎯 MODIFIÉ : Passer le MMR au bot
          await BotAI.useBotSpecialPower(_gameState!, playerMMR: _playerMMR);
          debugPrint("   ✅ Pouvoir spécial utilisé");

          notifyListeners();

          _gameState!.isWaitingForSpecialPower = false;
          _gameState!.specialCardToActivate = null;
          debugPrint("   🧹 État du pouvoir nettoyé");
        }
      } catch (e, stackTrace) {
        debugPrint("   🚨 ERREUR Bot: $e");
        debugPrint("   Stack trace: $stackTrace");

        if (_gameState != null && _gameState!.drawnCard != null) {
          _gameState!.discardPile.add(_gameState!.drawnCard!);
          _gameState!.drawnCard = null;
          debugPrint("   🗑️ Carte piochée défaussée (erreur)");
        }
      }

      debugPrint("   📊 Phase après actions: ${_gameState!.phase}");

      if (_gameState != null && _gameState!.phase == GamePhase.playing) {
        debugPrint("   ⏱️ Lancement phase réaction...");
        startReactionPhase();
        debugPrint("   ✅ Phase réaction lancée, sortie de boucle");
        break;
      } else {
        debugPrint(
            "   ⚠️ Phase n'est plus 'playing' (${_gameState!.phase}), sortie boucle");
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
    _gameState!.phase = GamePhase.ended;

    for (var p in _gameState!.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }

    // 🆕 Récupérer le classement complet
    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    // 🆕 Trouver la position du joueur humain (1, 2, 3, 4)
    int playerRank = ranking.indexWhere((p) => p.id == human.id) + 1;

    bool calledDutch = _gameState!.dutchCallerId == human.id;
    bool wonDutch = calledDutch && playerRank == 1;
    bool isSBMM = _playerMMR != null;

    debugPrint("   - Classement: #$playerRank");
    debugPrint("   - Dutch appelé: $calledDutch");
    debugPrint("   - Dutch gagné: $wonDutch");
    debugPrint("   - Mode SBMM: $isSBMM");

    // ✅ TOUJOURS sauvegarder, mais indiquer si SBMM ou non
    StatsService.saveGameResult(
      playerRank: playerRank,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      slotId: _currentSlotId,
      isSBMM: isSBMM, // ✅ NOUVEAU : flag pour RP
    );

    notifyListeners();
  }

  void startNextTournamentRound() {
    debugPrint("🏆 [startNextTournamentRound] Manche suivante");

    if (_gameState == null) return;
    List<Player> ranking = _gameState!.getFinalRanking();
    List<Player> survivors = [];
    int playersToKeep = min(3, ranking.length - 1);

    bool humanSurvives = false;

    for (int i = 0; i < playersToKeep; i++) {
      Player p = ranking[i];
      survivors.add(Player(
          id: p.id,
          name: p.name,
          isHuman: p.isHuman,
          botPersonality: p.botPersonality,
          position: i));

      if (p.isHuman) {
        humanSurvives = true;
      }
    }

    if (survivors.length < 2) return;

    debugPrint("   - Survivants: ${survivors.map((p) => p.name).toList()}");
    debugPrint("   - Joueur humain survit: $humanSurvives");

    if (survivors.length < 2) return;

    debugPrint("   - Survivants: ${survivors.map((p) => p.name).toList()}");

    // ✅ CORRECTION : Conserver le mode SBMM
    bool wasSBMM = _playerMMR != null;
    debugPrint("   - SBMM: $wasSBMM");

    createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId,
      useSBMM: wasSBMM, // ✅ CONSERVER LE MODE SBMM
    );
  }

  void quitGame() {
    debugPrint("🚪 [quitGame] Nettoyage du gameState");
    _gameState = null;
    isProcessing = false;
    shakingCardIndices.clear();
    _reactionTimer?.cancel();
    _playerMMR = null;

    // ✅ NOUVEAU : Nettoyer les variables de pause
    _reactionPauseTime = null;
    _remainingReactionTimeMs = null;

    notifyListeners();
  }
}
