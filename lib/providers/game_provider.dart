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

  // 🏆 NOUVEAU : Stockage du classement final du tournoi
  List<TournamentResult>? _tournamentFinalRanking;
  List<TournamentResult>? get tournamentFinalRanking => _tournamentFinalRanking;

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

    // 🏆 RESET du classement tournoi si nouvelle partie
    if (tournamentRound == 1) {
      _tournamentFinalRanking = null;
    }

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
        player.initializeBotMemory();
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
    debugPrint("   📍 Index carte: $cardIndex");
    debugPrint("   📍 forcedPlayer fourni: ${forcedPlayer?.name ?? 'NULL'}");

    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    debugPrint("   ✅ GameState OK");
    debugPrint("   📍 Phase actuelle: ${_gameState!.phase}");

    if (_gameState!.phase != GamePhase.reaction) {
      debugPrint("   ❌ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    debugPrint("   ✅ Phase REACTION confirmée");

    Player player =
        forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    debugPrint("   📍 Joueur sélectionné: ${player.name}");

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("   ❌ Index hors limites!");
      return;
    }

    debugPrint("   ✅ Index valide, carte: ${player.hand[cardIndex]?.value}");

    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);
    debugPrint("   🎯 Résultat match: $success");

    if (!success) {
      shakingCardIndices.add(cardIndex);
      debugPrint("   📳 Ajout index $cardIndex aux cartes qui tremblent");
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      shakingCardIndices.remove(cardIndex);
      debugPrint("   📳 Retrait index $cardIndex des cartes qui tremblent");
    }

    notifyListeners();
    debugPrint("   🔔 notifyListeners() appelé");
  }

  void takeFromDiscard() {
    debugPrint("📤 [takeFromDiscard] DÉBUT");

    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   ❌ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   ❌ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard != null) {
      debugPrint("   ❌ Carte déjà piochée");
      return;
    }

    if (_gameState!.discardPile.isEmpty) {
      debugPrint("   ❌ Défausse vide");
      return;
    }

    _gameState!.drawnCard = _gameState!.discardPile.removeLast();
    _gameState!.addToHistory(
        "${_gameState!.currentPlayer.name} prend ${_gameState!.drawnCard!.displayName} de la défausse.");
    debugPrint("   ✅ Carte prise: ${_gameState!.drawnCard?.value}");

    notifyListeners();
  }

  void callDutch() {
    debugPrint("📢 [callDutch] DÉBUT");

    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   ❌ Phase incorrecte");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   ❌ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard != null) {
      debugPrint("   ❌ Carte piochée en cours");
      return;
    }

    final human = _gameState!.currentPlayer;
    _gameState!.phase = GamePhase.dutchCalled;
    _gameState!.dutchCallerId = human.id;
    _gameState!.addToHistory("📢 ${human.name} crie DUTCH !");

    debugPrint("   ✅ Dutch appelé par ${human.name}");
    endGame();
  }

  void skipSpecialPower() {
    debugPrint("⏭️ [skipSpecialPower] Pouvoir ignoré");

    if (_gameState == null) return;

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    _gameState!.addToHistory("⏭️ Pouvoir spécial ignoré.");

    notifyListeners();

    _resumeReactionTimer(); // ✅ NOUVEAU : Reprendre si on était en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    debugPrint(
        "⚡ [useSpecialPower] Cible: Joueur $targetPlayerIndex, Carte $targetCardIndex");

    if (_gameState == null) return;

    PlayingCard? specialCard = _gameState!.specialCardToActivate;
    if (specialCard == null) {
      debugPrint("   ❌ Pas de carte spéciale");
      return;
    }

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    if (specialCard.value == '7' || specialCard.value == '8') {
      // Regarder une de SES cartes
      if (targetCardIndex < currentPlayer.hand.length) {
        currentPlayer.knownCards[targetCardIndex] = true;
        _gameState!.addToHistory(
            "👁️ ${currentPlayer.name} regarde sa carte #${targetCardIndex + 1}");
      }
    } else if (specialCard.value == '9' || specialCard.value == '10') {
      // Regarder une carte ADVERSE
      if (targetCardIndex < targetPlayer.hand.length) {
        _gameState!.lastSpiedCard = targetPlayer.hand[targetCardIndex];
        _gameState!.addToHistory(
            "🔍 ${currentPlayer.name} espionne ${targetPlayer.name} (carte #${targetCardIndex + 1})");
      }
    } else if (specialCard.value == 'J' || specialCard.value == 'Q') {
      // Échanger à l'aveugle
      _gameState!.pendingSwap = {
        'targetPlayer': targetPlayerIndex,
        'targetCard': targetCardIndex,
        'ownCard': null,
      };
      debugPrint("   📝 Swap en attente: cible définie");
      notifyListeners();
      return;
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    _resumeReactionTimer(); // ✅ NOUVEAU : Reprendre si on était en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void completeSwap(int ownCardIndex) {
    debugPrint("🔄 [completeSwap] Ma carte: $ownCardIndex");

    if (_gameState == null || _gameState!.pendingSwap == null) return;

    int targetPlayerIndex = _gameState!.pendingSwap!['targetPlayer'];
    int targetCardIndex = _gameState!.pendingSwap!['targetCard'];

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    // Effectuer l'échange
    PlayingCard? myCard = currentPlayer.hand[ownCardIndex];
    PlayingCard? theirCard = targetPlayer.hand[targetCardIndex];

    currentPlayer.hand[ownCardIndex] = theirCard;
    targetPlayer.hand[targetCardIndex] = myCard;

    // Reset des connaissances
    currentPlayer.knownCards[ownCardIndex] = false;
    targetPlayer.knownCards[targetCardIndex] = false;

    _gameState!.addToHistory(
        "🔄 ${currentPlayer.name} échange avec ${targetPlayer.name}");

    _gameState!.pendingSwap = null;
    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;

    notifyListeners();

    _resumeReactionTimer(); // ✅ NOUVEAU : Reprendre si on était en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  // 🆕 NOUVELLE MÉTHODE : Exécuter le pouvoir "regarder une carte"
  void executeLookAtCard(Player target, int cardIndex) {
    debugPrint("👁️ [executeLookAtCard] Cible: ${target.name}, Index: $cardIndex");

    if (_gameState == null) return;

    if (cardIndex >= 0 && cardIndex < target.hand.length) {
      // Si c'est le joueur humain qui regarde sa propre carte
      if (target.isHuman) {
        target.knownCards[cardIndex] = true;
      }
      // Stocker la carte espionnée pour l'affichage
      _gameState!.lastSpiedCard = target.hand[cardIndex];
      
      GameLogic.lookAtCard(_gameState!, target, cardIndex);
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  // 🆕 NOUVELLE MÉTHODE : Exécuter l'effet du Joker
  void executeJokerEffect(Player target) {
    debugPrint("🃏 [executeJokerEffect] Cible: ${target.name}");

    if (_gameState == null) return;

    GameLogic.jokerEffect(_gameState!, target);

    // Si c'est le joueur humain qui est ciblé, il oublie toutes ses cartes
    if (target.isHuman) {
      for (int i = 0; i < target.knownCards.length; i++) {
        target.knownCards[i] = false;
      }
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  // 🆕 NOUVELLE MÉTHODE : Pause du timer pour les notifications des bots
  void pauseReactionTimerForNotification() {
    _pauseReactionTimer();
  }

  // 🆕 NOUVELLE MÉTHODE : Reprise du timer après les notifications des bots
  void resumeReactionTimerAfterNotification() {
    _resumeReactionTimer();
  }

  void startReactionPhase() {
    debugPrint("⏱️ [startReactionPhase] DÉBUT");

    if (_gameState == null) {
      debugPrint("   ❌ GameState NULL");
      return;
    }

    _gameState!.phase = GamePhase.reaction;
    _gameState!.reactionTimeRemaining = _currentReactionTimeMs;
    debugPrint("   - Temps initial: $_currentReactionTimeMs ms");

    _reactionTimer?.cancel();

    _reactionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_gameState == null) {
        timer.cancel();
        return;
      }

      _gameState!.reactionTimeRemaining -= 100;

      if (_gameState!.reactionTimeRemaining <= 0) {
        debugPrint("   ⏰ Temps écoulé!");
        timer.cancel();
        _endReactionPhase();
      }

      notifyListeners();
    });

    _simulateBotReaction();
  }

  // ✅ NOUVEAU : Pause du timer de réaction
  void _pauseReactionTimer() {
    if (_reactionTimer != null && _reactionTimer!.isActive) {
      _reactionTimer!.cancel();
      _reactionPauseTime = DateTime.now();
      _remainingReactionTimeMs = _gameState?.reactionTimeRemaining;
      debugPrint(
          "   ⏸️ Timer réaction en pause (${_remainingReactionTimeMs}ms restants)");
    }
  }

  // ✅ NOUVEAU : Reprise du timer de réaction
  void _resumeReactionTimer() {
    if (_remainingReactionTimeMs != null &&
        _remainingReactionTimeMs! > 0 &&
        _gameState != null) {
      debugPrint(
          "   ▶️ Reprise timer réaction (${_remainingReactionTimeMs}ms restants)");

      _gameState!.reactionTimeRemaining = _remainingReactionTimeMs!;

      _reactionTimer?.cancel();
      _reactionTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_gameState == null) {
          timer.cancel();
          return;
        }

        _gameState!.reactionTimeRemaining -= 100;

        if (_gameState!.reactionTimeRemaining <= 0) {
          debugPrint("   ⏰ Temps écoulé (après reprise)!");
          timer.cancel();
          _endReactionPhase();
        }

        notifyListeners();
      });

      _reactionPauseTime = null;
      _remainingReactionTimeMs = null;
    }
  }

  void _endReactionPhase() {
    debugPrint("🔚 [_endReactionPhase] Fin phase réaction");

    if (_gameState == null) return;

    _reactionTimer?.cancel();
    _gameState!.phase = GamePhase.playing;
    _gameState!.lastSpiedCard = null;

    GameLogic.nextPlayer(_gameState!);
    debugPrint("   - Prochain joueur: ${_gameState!.currentPlayer.name}");

    notifyListeners();

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   🤖 C'est un bot, on lance son tour");
      _checkAndPlayBotTurn();
    }
  }

  void _simulateBotReaction() async {
    debugPrint("🤖 [_simulateBotReaction] Début simulation");

    if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
      debugPrint("   ⚠️ Phase incorrecte, annulation");
      return;
    }

    PlayingCard? topCard = _gameState!.topDiscardCard;
    if (topCard == null) {
      debugPrint("   ⚠️ Pas de carte sur la défausse");
      return;
    }

    debugPrint("   - Carte défausse: ${topCard.displayName}");

    // ✅ NOUVEAU: Utiliser BotAI.tryReactionMatch pour chaque bot
    for (var bot in _gameState!.players.where((p) => !p.isHuman)) {
      if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
        debugPrint("   ⚠️ Phase changée, arrêt");
        return;
      }

      // Délai aléatoire avant que le bot réagisse
      int delay = Random().nextInt(800) + 300; // 300-1100ms
      await Future.delayed(Duration(milliseconds: delay));

      if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
        return;
      }

      // ✅ Utiliser la nouvelle méthode tryReactionMatch de BotAI
      bool matched = await BotAI.tryReactionMatch(_gameState!, bot, playerMMR: _playerMMR);
      
      if (matched) {
        debugPrint("   ⚡ ${bot.name} a réussi un match en réaction!");
        notifyListeners();
        return; // Un seul match par phase de réaction
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

  // 🏆 NOUVEAU : Vérifier si le joueur humain est éliminé en tournoi
  bool isHumanEliminatedInTournament() {
    if (_gameState == null) return false;
    if (_gameState!.gameMode != GameMode.tournament) return false;

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    // L'humain est éliminé s'il est dernier du classement
    int humanRank = ranking.indexWhere((p) => p.id == human.id) + 1;
    return humanRank == ranking.length;
  }

  // 🏆 NOUVEAU : Simuler les manches restantes entre bots et calculer le classement final
  void finishTournamentForHuman() {
    debugPrint("🏆 [finishTournamentForHuman] L'humain est éliminé, simulation des manches restantes");

    if (_gameState == null) return;

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);
    int currentRound = _gameState!.tournamentRound;

    // Initialiser le classement final
    _tournamentFinalRanking = [];

    // L'humain est éliminé à cette manche - sa position finale dépend de quand il a été éliminé
    // Manche 1 (4 joueurs) -> éliminé = 4ème
    // Manche 2 (3 joueurs) -> éliminé = 3ème
    // Manche 3 (2 joueurs) -> éliminé = 2ème
    int humanFinalPosition = 5 - currentRound; // 4, 3, 2 selon la manche

    debugPrint("   - Manche actuelle: $currentRound");
    debugPrint("   - Position finale humain: $humanFinalPosition");

    // Récupérer les survivants (tous sauf le dernier)
    List<Player> survivors = [];
    for (int i = 0; i < ranking.length - 1; i++) {
      survivors.add(ranking[i]);
    }

    // Simuler les manches restantes entre bots
    List<Player> currentPlayers = survivors;
    int simulatedRound = currentRound + 1;

    while (currentPlayers.length > 1 && simulatedRound <= 3) {
      debugPrint("   🤖 Simulation manche $simulatedRound avec ${currentPlayers.length} bots");

      // Simuler une manche (ordre aléatoire pour déterminer l'éliminé)
      currentPlayers.shuffle();
      Player eliminated = currentPlayers.removeLast();

      int eliminatedPosition = 5 - simulatedRound;
      _tournamentFinalRanking!.add(TournamentResult(
        player: eliminated,
        finalPosition: eliminatedPosition,
        eliminatedAtRound: simulatedRound,
      ));

      debugPrint("   - ${eliminated.name} éliminé à la manche $simulatedRound (position $eliminatedPosition)");
      simulatedRound++;
    }

    // Le dernier bot restant est le gagnant
    if (currentPlayers.isNotEmpty) {
      _tournamentFinalRanking!.add(TournamentResult(
        player: currentPlayers.first,
        finalPosition: 1,
        eliminatedAtRound: null, // Gagnant
      ));
      debugPrint("   🥇 ${currentPlayers.first.name} gagne le tournoi");
    }

    // Ajouter l'humain à sa position
    _tournamentFinalRanking!.add(TournamentResult(
      player: human,
      finalPosition: humanFinalPosition,
      eliminatedAtRound: currentRound,
    ));

    // Trier par position finale
    _tournamentFinalRanking!.sort((a, b) => a.finalPosition.compareTo(b.finalPosition));

    debugPrint("   📊 Classement final du tournoi:");
    for (var result in _tournamentFinalRanking!) {
      debugPrint("      #${result.finalPosition}: ${result.player.name}");
    }

    // Marquer le tournoi comme terminé
    _gameState!.tournamentRound = 3; // Force la fin du tournoi

    notifyListeners();
  }

  // 🏆 NOUVEAU : Obtenir les RP gagnés/perdus selon la position en tournoi
  int getTournamentRP(int finalPosition) {
    switch (finalPosition) {
      case 1:
        return 150; // Gagnant du tournoi
      case 2:
        return 60;  // Finaliste
      case 3:
        return -5;  // 3ème place
      case 4:
        return -30; // 4ème place (éliminé en 1ère manche)
      default:
        return 0;
    }
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
    _tournamentFinalRanking = null; // 🏆 NOUVEAU : Reset du classement tournoi

    // ✅ NOUVEAU : Nettoyer les variables de pause
    _reactionPauseTime = null;
    _remainingReactionTimeMs = null;

    notifyListeners();
  }
}

// 🏆 NOUVEAU : Classe pour stocker les résultats du tournoi
class TournamentResult {
  final Player player;
  final int finalPosition;
  final int? eliminatedAtRound; // null si gagnant

  TournamentResult({
    required this.player,
    required this.finalPosition,
    this.eliminatedAtRound,
  });
}