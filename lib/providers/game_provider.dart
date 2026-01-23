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

  // Ã°Å¸Å½Â¯ NOUVEAU : MMR du joueur pour le SBMM
  int? _playerMMR;
  int? get playerMMR => _playerMMR; // Ã¢Åâ¦ GETTER PUBLIC

  // Ã°Å¸Ââ  NOUVEAU : Stockage du classement final du tournoi
  List<TournamentResult>? _tournamentFinalRanking;
  List<TournamentResult>? get tournamentFinalRanking => _tournamentFinalRanking;

  void createNewGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    required int reactionTimeMs,
    int tournamentRound = 1,
    int saveSlot = 1,
    bool useSBMM = false, // Ã°Å¸â â¢ PARAMÃËTRE SBMM
  }) async {
    debugPrint("Ã°Å¸Å½Â® [createNewGame] CRÃâ°ATION NOUVELLE PARTIE");
    debugPrint("   - Joueurs: ${players.map((p) => p.name).toList()}");
    debugPrint("   - Mode: $gameMode");
    debugPrint("   - DifficultÃÂ©: $difficulty");
    debugPrint("   - SBMM: $useSBMM");

    // Ã°Å¸Ââ  RESET du classement tournoi si nouvelle partie
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

    // Ã°Å¸Å½Â¯ NOUVEAU : Charger le MMR UNIQUEMENT si SBMM activÃÂ©
    if (useSBMM) {
      final stats = await StatsService.getStats(slotId: saveSlot);
      _playerMMR = stats['mmr'] ?? 0;
      debugPrint("   - MMR du joueur: $_playerMMR (SBMM activÃÂ©)");
    } else {
      _playerMMR = null; // Ã¢Åâ¦ Pas de MMR en mode manuel
      debugPrint("   - Mode manuel (pas de MMR)");
    }

    // Ã°Å¸Â§  NOUVEAU : Initialiser les cartes mentales des bots
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
    debugPrint("Ã°Å¸âÂ [checkIfBotShouldPlay] VÃÂ©rification...");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (isProcessing) {
      debugPrint("   Ã¢ÂÂ¸Ã¯Â¸Â DÃÂ©jÃ  en traitement");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   Ã¢ÂÂ¸Ã¯Â¸Â Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    if (_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã°Å¸âÂ¤ Tour humain");
      return;
    }

    debugPrint("   Ã¢Åâ¦ Bot doit jouer, dÃÂ©clenchement...");
    _checkAndPlayBotTurn();
  }

  void drawCard() {
    debugPrint("Ã°Å¸Å½Â´ [drawCard] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   Ã¢ÂÅ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢ÂÅ Ce n'est pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard != null) {
      debugPrint("   Ã¢ÂÅ Une carte a dÃÂ©jÃ  ÃÂ©tÃÂ© piochÃÂ©e");
      return;
    }

    shakingCardIndices.clear();
    GameLogic.drawCard(_gameState!);

    debugPrint("   Ã¢Åâ¦ Carte piochÃÂ©e: ${_gameState!.drawnCard?.value}");
    notifyListeners();
  }

  void replaceCard(int cardIndex) {
    debugPrint("Ã°Å¸ââ [replaceCard] DÃâ°BUT - Index: $cardIndex");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢ÂÅ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard == null) {
      debugPrint("   Ã¢ÂÅ Pas de carte piochÃÂ©e");
      return;
    }

    final cardValue = _gameState!.drawnCard!.value;
    debugPrint("   - Carte Ã  insÃÂ©rer: $cardValue");

    GameLogic.replaceCard(_gameState!, cardIndex);
    debugPrint("   Ã¢Åâ¦ Carte remplacÃÂ©e");

    notifyListeners();

    if (_checkInstantEnd()) {
      debugPrint("   Ã°Å¸ÂÂ Fin instantanÃÂ©e dÃÂ©tectÃÂ©e");
      return;
    }

    if (_gameState!.isWaitingForSpecialPower) {
      debugPrint(
          "   Ã¢Å¡Â¡ Pouvoir spÃÂ©cial en attente: ${_gameState!.specialCardToActivate?.value}");
      _pauseReactionTimer(); // Ã¢Åâ¦ NOUVEAU : Pause si on ÃÂ©tait en rÃÂ©action
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      debugPrint("   Ã¢ÂÂ±Ã¯Â¸Â Lancement phase rÃÂ©action");
      startReactionPhase();
    }
  }

  void discardDrawnCard() {
    debugPrint("Ã°Å¸ââÃ¯Â¸Â [discardDrawnCard] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢ÂÅ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard == null) {
      debugPrint("   Ã¢ÂÅ Pas de carte piochÃÂ©e");
      return;
    }

    final cardValue = _gameState!.drawnCard!.value;
    debugPrint("   - Carte dÃÂ©faussÃÂ©e: $cardValue");

    GameLogic.discardDrawnCard(_gameState!);
    notifyListeners();

    if (_checkInstantEnd()) {
      debugPrint("   Ã°Å¸ÂÂ Fin instantanÃÂ©e dÃÂ©tectÃÂ©e");
      return;
    }

    if (_gameState!.isWaitingForSpecialPower) {
      debugPrint(
          "   Ã¢Å¡Â¡ Pouvoir spÃÂ©cial en attente: ${_gameState!.specialCardToActivate?.value}");
      _pauseReactionTimer(); // Ã¢Åâ¦ NOUVEAU : Pause si on ÃÂ©tait en rÃÂ©action
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      debugPrint("   Ã¢ÂÂ±Ã¯Â¸Â Lancement phase rÃÂ©action");
      startReactionPhase();
    }
  }

  void attemptMatch(int cardIndex, {Player? forcedPlayer}) async {
    debugPrint("Ã°Å¸âÂ¥ [attemptMatch] ENTRÃâ°E");
    debugPrint("   Ã°Å¸âÂ Index carte: $cardIndex");
    debugPrint("   Ã°Å¸âÂ forcedPlayer fourni: ${forcedPlayer?.name ?? 'NULL'}");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    debugPrint("   Ã¢Åâ¦ GameState OK");
    debugPrint("   Ã°Å¸âÂ Phase actuelle: ${_gameState!.phase}");

    if (_gameState!.phase != GamePhase.reaction) {
      debugPrint("   Ã¢ÂÅ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    debugPrint("   Ã¢Åâ¦ Phase REACTION confirmÃÂ©e");

    Player player =
        forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    debugPrint("   Ã°Å¸âÂ Joueur sÃÂ©lectionnÃÂ©: ${player.name}");

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("   Ã¢ÂÅ Index hors limites!");
      return;
    }

    debugPrint("   Ã¢Åâ¦ Index valide, carte: ${player.hand[cardIndex]?.value}");

    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);
    debugPrint("   Ã°Å¸Å½Â¯ RÃÂ©sultat match: $success");

    if (!success) {
      shakingCardIndices.add(cardIndex);
      debugPrint("   Ã°Å¸âÂ³ Ajout index $cardIndex aux cartes qui tremblent");
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      shakingCardIndices.remove(cardIndex);
      debugPrint("   Ã°Å¸âÂ³ Retrait index $cardIndex des cartes qui tremblent");
    }

    notifyListeners();
    debugPrint("   Ã°Å¸ââ notifyListeners() appelÃÂ©");
  }

  void takeFromDiscard() {
    debugPrint("Ã°Å¸âÂ¤ [takeFromDiscard] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   Ã¢ÂÅ Phase incorrecte: ${_gameState!.phase}");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢ÂÅ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard != null) {
      debugPrint("   Ã¢ÂÅ Carte dÃÂ©jÃ  piochÃÂ©e");
      return;
    }

    if (_gameState!.discardPile.isEmpty) {
      debugPrint("   Ã¢ÂÅ DÃÂ©fausse vide");
      return;
    }

    _gameState!.drawnCard = _gameState!.discardPile.removeLast();
    _gameState!.addToHistory(
        "${_gameState!.currentPlayer.name} prend ${_gameState!.drawnCard!.displayName} de la dÃÂ©fausse.");
    debugPrint("   Ã¢Åâ¦ Carte prise: ${_gameState!.drawnCard?.value}");

    notifyListeners();
  }

  void callDutch() {
    debugPrint("Ã°Å¸âÂ¢ [callDutch] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (_gameState!.phase != GamePhase.playing) {
      debugPrint("   Ã¢ÂÅ Phase incorrecte");
      return;
    }

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢ÂÅ Pas le tour de l'humain");
      return;
    }

    if (_gameState!.drawnCard != null) {
      debugPrint("   Ã¢ÂÅ Carte piochÃÂ©e en cours");
      return;
    }

    final human = _gameState!.currentPlayer;
    _gameState!.phase = GamePhase.dutchCalled;
    _gameState!.dutchCallerId = human.id;
    _gameState!.addToHistory("Ã°Å¸âÂ¢ ${human.name} crie DUTCH !");

    debugPrint("   Ã¢Åâ¦ Dutch appelÃÂ© par ${human.name}");
    endGame();
  }

  void skipSpecialPower() {
    debugPrint("Ã¢ÂÂ­Ã¯Â¸Â [skipSpecialPower] Pouvoir ignorÃÂ©");

    if (_gameState == null) return;

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    _gameState!.addToHistory("Ã¢ÂÂ­Ã¯Â¸Â Pouvoir spÃÂ©cial ignorÃÂ©.");

    notifyListeners();

    _resumeReactionTimer(); // Ã¢Åâ¦ NOUVEAU : Reprendre si on ÃÂ©tait en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    debugPrint(
        "Ã¢Å¡Â¡ [useSpecialPower] Cible: Joueur $targetPlayerIndex, Carte $targetCardIndex");

    if (_gameState == null) return;

    PlayingCard? specialCard = _gameState!.specialCardToActivate;
    if (specialCard == null) {
      debugPrint("   Ã¢ÂÅ Pas de carte spÃÂ©ciale");
      return;
    }

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    if (specialCard.value == '7' || specialCard.value == '8') {
      // Regarder une de SES cartes
      if (targetCardIndex < currentPlayer.hand.length) {
        currentPlayer.knownCards[targetCardIndex] = true;
        _gameState!.addToHistory(
            "Ã°Å¸âÂÃ¯Â¸Â ${currentPlayer.name} regarde sa carte #${targetCardIndex + 1}");
      }
    } else if (specialCard.value == '9' || specialCard.value == '10') {
      // Regarder une carte ADVERSE
      if (targetCardIndex < targetPlayer.hand.length) {
        _gameState!.lastSpiedCard = targetPlayer.hand[targetCardIndex];
        _gameState!.addToHistory(
            "Ã°Å¸âÂ ${currentPlayer.name} espionne ${targetPlayer.name} (carte #${targetCardIndex + 1})");
      }
    } else if (specialCard.value == 'J' || specialCard.value == 'Q') {
      // Ãâ°changer Ã  l'aveugle
      _gameState!.pendingSwap = {
        'targetPlayer': targetPlayerIndex,
        'targetCard': targetCardIndex,
        'ownCard': null,
      };
      debugPrint("   Ã°Å¸âÂ Swap en attente: cible dÃÂ©finie");
      notifyListeners();
      return;
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    _resumeReactionTimer(); // Ã¢Åâ¦ NOUVEAU : Reprendre si on ÃÂ©tait en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void completeSwap(int ownCardIndex) {
    debugPrint("Ã°Å¸ââ [completeSwap] Ma carte: $ownCardIndex");

    if (_gameState == null || _gameState!.pendingSwap == null) return;

    int targetPlayerIndex = _gameState!.pendingSwap!['targetPlayer'];
    int targetCardIndex = _gameState!.pendingSwap!['targetCard'];

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    // Effectuer l'ÃÂ©change
    PlayingCard? myCard = currentPlayer.hand[ownCardIndex];
    PlayingCard? theirCard = targetPlayer.hand[targetCardIndex];

    currentPlayer.hand[ownCardIndex] = theirCard;
    targetPlayer.hand[targetCardIndex] = myCard;

    // Reset des connaissances
    currentPlayer.knownCards[ownCardIndex] = false;
    targetPlayer.knownCards[targetCardIndex] = false;

    _gameState!.addToHistory(
        "Ã°Å¸ââ ${currentPlayer.name} ÃÂ©change avec ${targetPlayer.name}");

    _gameState!.pendingSwap = null;
    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;

    notifyListeners();

    _resumeReactionTimer(); // Ã¢Åâ¦ NOUVEAU : Reprendre si on ÃÂ©tait en pause

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  // Ã°Å¸â â¢ NOUVELLE MÃâ°THODE : ExÃÂ©cuter le pouvoir "regarder une carte"
  void executeLookAtCard(Player target, int cardIndex) {
    debugPrint("Ã°Å¸âÂÃ¯Â¸Â [executeLookAtCard] Cible: ${target.name}, Index: $cardIndex");

    if (_gameState == null) return;

    if (cardIndex >= 0 && cardIndex < target.hand.length) {
      // Si c'est le joueur humain qui regarde sa propre carte
      if (target.isHuman) {
        target.knownCards[cardIndex] = true;
      }
      // Stocker la carte espionnÃÂ©e pour l'affichage
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

  // Ã°Å¸â â¢ NOUVELLE MÃâ°THODE : ExÃÂ©cuter l'effet du Joker
  void executeJokerEffect(Player target) {
    debugPrint("Ã°Å¸ÆÂ [executeJokerEffect] Cible: ${target.name}");

    if (_gameState == null) return;

    GameLogic.jokerEffect(_gameState!, target);

    // Si c'est le joueur humain qui est ciblÃÂ©, il oublie toutes ses cartes
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

  // Ã°Å¸â â¢ NOUVELLE MÃâ°THODE : Pause du timer pour les notifications des bots
  void pauseReactionTimerForNotification() {
    _pauseReactionTimer();
  }

  // Ã°Å¸â â¢ NOUVELLE MÃâ°THODE : Reprise du timer aprÃÂ¨s les notifications des bots
  void resumeReactionTimerAfterNotification() {
    _resumeReactionTimer();
  }

  void startReactionPhase() {
    debugPrint("Ã¢ÂÂ±Ã¯Â¸Â [startReactionPhase] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
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
        debugPrint("   Ã¢ÂÂ° Temps ÃÂ©coulÃÂ©!");
        timer.cancel();
        _endReactionPhase();
      }

      notifyListeners();
    });

    _simulateBotReaction();
  }

  // Ã¢Åâ¦ NOUVEAU : Pause du timer de rÃÂ©action
  void _pauseReactionTimer() {
    if (_reactionTimer != null && _reactionTimer!.isActive) {
      _reactionTimer!.cancel();
      _reactionPauseTime = DateTime.now();
      _remainingReactionTimeMs = _gameState?.reactionTimeRemaining;
      debugPrint(
          "   Ã¢ÂÂ¸Ã¯Â¸Â Timer rÃÂ©action en pause (${_remainingReactionTimeMs}ms restants)");
    }
  }

  // Ã¢Åâ¦ NOUVEAU : Reprise du timer de rÃÂ©action
  void _resumeReactionTimer() {
    if (_remainingReactionTimeMs != null &&
        _remainingReactionTimeMs! > 0 &&
        _gameState != null) {
      debugPrint(
          "   Ã¢âÂ¶Ã¯Â¸Â Reprise timer rÃÂ©action (${_remainingReactionTimeMs}ms restants)");

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
          debugPrint("   Ã¢ÂÂ° Temps ÃÂ©coulÃÂ© (aprÃÂ¨s reprise)!");
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
    debugPrint("Ã°Å¸âÅ¡ [_endReactionPhase] Fin phase rÃÂ©action");

    if (_gameState == null) return;

    _reactionTimer?.cancel();
    _gameState!.phase = GamePhase.playing;
    _gameState!.lastSpiedCard = null;

    GameLogic.nextPlayer(_gameState!);
    debugPrint("   - Prochain joueur: ${_gameState!.currentPlayer.name}");

    notifyListeners();

    if (!_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã°Å¸Â¤â C'est un bot, on lance son tour");
      _checkAndPlayBotTurn();
    }
  }

  void _simulateBotReaction() async {
    debugPrint("Ã°Å¸Â¤â [_simulateBotReaction] DÃÂ©but simulation");

    if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
      debugPrint("   Ã¢Å¡ Ã¯Â¸Â Phase incorrecte, annulation");
      return;
    }

    PlayingCard? topCard = _gameState!.topDiscardCard;
    if (topCard == null) {
      debugPrint("   Ã¢Å¡ Ã¯Â¸Â Pas de carte sur la dÃÂ©fausse");
      return;
    }

    debugPrint("   - Carte dÃÂ©fausse: ${topCard.displayName}");

    // Ã¢Åâ¦ NOUVEAU: Utiliser BotAI.tryReactionMatch pour chaque bot
    for (var bot in _gameState!.players.where((p) => !p.isHuman)) {
      if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
        debugPrint("   Ã¢Å¡ Ã¯Â¸Â Phase changÃÂ©e, arrÃÂªt");
        return;
      }

      // DÃÂ©lai alÃÂ©atoire avant que le bot rÃÂ©agisse
      int delay = Random().nextInt(800) + 300; // 300-1100ms
      await Future.delayed(Duration(milliseconds: delay));

      if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
        return;
      }

      // Ã¢Åâ¦ Utiliser la nouvelle mÃÂ©thode tryReactionMatch de BotAI
      bool matched = await BotAI.tryReactionMatch(_gameState!, bot, playerMMR: _playerMMR);
      
      if (matched) {
        debugPrint("   Ã¢Å¡Â¡ ${bot.name} a rÃÂ©ussi un match en rÃÂ©action!");
        notifyListeners();
        return; // Un seul match par phase de rÃÂ©action
      }
    }

    debugPrint("   - Aucun bot n'a rÃÂ©agi");
  }

  bool _checkInstantEnd() {
    if (_gameState == null) return false;
    if (_gameState!.deck.isEmpty) {
      debugPrint("Ã°Å¸ÂÂ [_checkInstantEnd] Deck vide -> Fin de partie");
      endGame();
      return true;
    }
    return false;
  }

  Future<void> _checkAndPlayBotTurn() async {
    debugPrint("Ã°Å¸Å½Â® [_checkAndPlayBotTurn] DÃâ°BUT");

    if (_gameState == null) {
      debugPrint("   Ã¢ÂÅ GameState NULL");
      return;
    }

    if (_gameState!.phase == GamePhase.ended) {
      debugPrint("   Ã¢ÂÅ Partie terminÃÂ©e");
      return;
    }

    if (_checkInstantEnd()) {
      debugPrint("   Ã¢ÂÅ Fin instantanÃÂ©e");
      return;
    }

    debugPrint(
        "   - Joueur actuel: ${_gameState!.currentPlayer.name} (isHuman: ${_gameState!.currentPlayer.isHuman})");
    debugPrint("   - Phase actuelle: ${_gameState!.phase}");

    if (_gameState!.currentPlayer.isHuman) {
      debugPrint("   Ã¢Åâ¦ Tour humain, on s'arrÃÂªte");
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
          "   Ã°Å¸ââ BOUCLE $loopCount - Joueur: ${_gameState!.currentPlayer.name}");

      if (loopCount > 10) {
        debugPrint("   Ã°Å¸Å¡Â¨ BOUCLE INFINIE DÃâ°TECTÃâ°E - ARRÃÅ T FORCÃâ°");
        break;
      }

      if (_checkInstantEnd()) {
        debugPrint("   Ã¢ÂÅ Fin instantanÃÂ©e (dans boucle)");
        return;
      }

      isProcessing = true;
      notifyListeners();

      debugPrint("   Ã¢ÂÂ³ Attente 800ms...");
      await Future.delayed(const Duration(milliseconds: 800));

      if (_gameState == null) {
        debugPrint("   Ã¢ÂÅ GameState devenu NULL");
        break;
      }

      try {
        debugPrint("   Ã°Å¸Â¤â Le bot ${_gameState!.currentPlayer.name} joue...");

        // Ã°Å¸Å½Â¯ MODIFIÃâ° : Passer le MMR au bot
        await BotAI.playBotTurn(_gameState!, playerMMR: _playerMMR);
        debugPrint("   Ã¢Åâ¦ Tour du bot terminÃÂ©");

        notifyListeners();

        if (_gameState!.phase == GamePhase.dutchCalled) {
          debugPrint("   Ã°Å¸âÂ¢ DUTCH criÃÂ© ! Fin de partie");
          endGame();
          return;
        }

        if (_gameState!.isWaitingForSpecialPower) {
          debugPrint(
              "   Ã¢Å¡Â¡ Pouvoir spÃÂ©cial en attente: ${_gameState!.specialCardToActivate?.value}");
          await Future.delayed(const Duration(milliseconds: 800));

          // Ã°Å¸Å½Â¯ MODIFIÃâ° : Passer le MMR au bot
          await BotAI.useBotSpecialPower(_gameState!, playerMMR: _playerMMR);
          debugPrint("   Ã¢Åâ¦ Pouvoir spÃÂ©cial utilisÃÂ©");

          notifyListeners();

          _gameState!.isWaitingForSpecialPower = false;
          _gameState!.specialCardToActivate = null;
          debugPrint("   Ã°Å¸Â§Â¹ Ãâ°tat du pouvoir nettoyÃÂ©");
        }
      } catch (e, stackTrace) {
        debugPrint("   Ã°Å¸Å¡Â¨ ERREUR Bot: $e");
        debugPrint("   Stack trace: $stackTrace");

        if (_gameState != null && _gameState!.drawnCard != null) {
          _gameState!.discardPile.add(_gameState!.drawnCard!);
          _gameState!.drawnCard = null;
          debugPrint("   Ã°Å¸ââÃ¯Â¸Â Carte piochÃÂ©e dÃÂ©faussÃÂ©e (erreur)");
        }
      }

      debugPrint("   Ã°Å¸âÅ  Phase aprÃÂ¨s actions: ${_gameState!.phase}");

      if (_gameState != null && _gameState!.phase == GamePhase.playing) {
        debugPrint("   Ã¢ÂÂ±Ã¯Â¸Â Lancement phase rÃÂ©action...");
        startReactionPhase();
        debugPrint("   Ã¢Åâ¦ Phase rÃÂ©action lancÃÂ©e, sortie de boucle");
        break;
      } else {
        debugPrint(
            "   Ã¢Å¡ Ã¯Â¸Â Phase n'est plus 'playing' (${_gameState!.phase}), sortie boucle");
        break;
      }
    }

    debugPrint("   Ã°Å¸ÂÂ FIN - isProcessing = false");
    isProcessing = false;
    notifyListeners();
  }

  void endGame() {
    debugPrint("Ã°Å¸ÂÂ [endGame] FIN DE PARTIE");

    if (_gameState == null) return;
    _gameState!.phase = GamePhase.ended;

    for (var p in _gameState!.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }

    // Ã°Å¸â â¢ RÃÂ©cupÃÂ©rer le classement complet
    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    // Ã°Å¸â â¢ Trouver la position du joueur humain (1, 2, 3, 4)
    int playerRank = ranking.indexWhere((p) => p.id == human.id) + 1;

    bool calledDutch = _gameState!.dutchCallerId == human.id;
    bool wonDutch = calledDutch && playerRank == 1;
    bool isSBMM = _playerMMR != null;

    debugPrint("   - Classement: #$playerRank");
    debugPrint("   - Dutch appelÃ©: $calledDutch");
    debugPrint("   - Dutch gagnÃ©: $wonDutch");
    debugPrint("   - Mode SBMM: $isSBMM");
    
    // ð§  NOUVEAU : Enregistrer l'historique Dutch pour tous les bots
    if (_gameState!.dutchCallerId != null) {
      Player dutchCaller = _gameState!.players.firstWhere((p) => p.id == _gameState!.dutchCallerId);
      int dutchCallerRank = ranking.indexWhere((p) => p.id == dutchCaller.id) + 1;
      
      if (!dutchCaller.isHuman) {
        // Enregistrer la tentative Dutch du bot
        dutchCaller.dutchHistory.add(DutchAttempt(
          estimatedScore: dutchCaller.getEstimatedScore(),
          actualScore: _gameState!.getFinalScore(dutchCaller),
          won: dutchCallerRank == 1,
          opponentsCount: _gameState!.players.length - 1,
        ));
        
        // Garder seulement les 10 derniÃ¨res tentatives
        if (dutchCaller.dutchHistory.length > 10) {
          dutchCaller.dutchHistory.removeAt(0);
        }
        
        debugPrint("ð§  [endGame] Dutch history enregistrÃ© pour ${dutchCaller.name}: ${dutchCaller.dutchHistory.length} tentatives");
      }
    }

    // â TOUJOURS sauvegarder, mais indiquer si SBMM ou non
    StatsService.saveGameResult(
      playerRank: playerRank,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      slotId: _currentSlotId,
      isSBMM: isSBMM, // Ã¢Åâ¦ NOUVEAU : flag pour RP
    );

    notifyListeners();
  }

  // Ã°Å¸Ââ  NOUVEAU : VÃÂ©rifier si le joueur humain est ÃÂ©liminÃÂ© en tournoi
  bool isHumanEliminatedInTournament() {
    if (_gameState == null) return false;
    if (_gameState!.gameMode != GameMode.tournament) return false;

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    // L'humain est ÃÂ©liminÃÂ© s'il est dernier du classement
    int humanRank = ranking.indexWhere((p) => p.id == human.id) + 1;
    return humanRank == ranking.length;
  }

  // Ã°Å¸Ââ  NOUVEAU : Simuler les manches restantes entre bots et calculer le classement final
  void finishTournamentForHuman() {
    debugPrint("Ã°Å¸Ââ  [finishTournamentForHuman] L'humain est ÃÂ©liminÃÂ©, simulation des manches restantes");

    if (_gameState == null) return;

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);
    int currentRound = _gameState!.tournamentRound;

    // Initialiser le classement final
    _tournamentFinalRanking = [];

    // L'humain est ÃÂ©liminÃÂ© Ã  cette manche - sa position finale dÃÂ©pend de quand il a ÃÂ©tÃÂ© ÃÂ©liminÃÂ©
    // Manche 1 (4 joueurs) -> ÃÂ©liminÃÂ© = 4ÃÂ¨me
    // Manche 2 (3 joueurs) -> ÃÂ©liminÃÂ© = 3ÃÂ¨me
    // Manche 3 (2 joueurs) -> ÃÂ©liminÃÂ© = 2ÃÂ¨me
    int humanFinalPosition = 5 - currentRound; // 4, 3, 2 selon la manche

    debugPrint("   - Manche actuelle: $currentRound");
    debugPrint("   - Position finale humain: $humanFinalPosition");

    // RÃÂ©cupÃÂ©rer les survivants (tous sauf le dernier)
    List<Player> survivors = [];
    for (int i = 0; i < ranking.length - 1; i++) {
      survivors.add(ranking[i]);
    }

    // Simuler les manches restantes entre bots
    List<Player> currentPlayers = survivors;
    int simulatedRound = currentRound + 1;

    while (currentPlayers.length > 1 && simulatedRound <= 3) {
      debugPrint("   Ã°Å¸Â¤â Simulation manche $simulatedRound avec ${currentPlayers.length} bots");

      // Simuler une manche (ordre alÃÂ©atoire pour dÃÂ©terminer l'ÃÂ©liminÃÂ©)
      currentPlayers.shuffle();
      Player eliminated = currentPlayers.removeLast();

      int eliminatedPosition = 5 - simulatedRound;
      _tournamentFinalRanking!.add(TournamentResult(
        player: eliminated,
        finalPosition: eliminatedPosition,
        eliminatedAtRound: simulatedRound,
      ));

      debugPrint("   - ${eliminated.name} ÃÂ©liminÃÂ© Ã  la manche $simulatedRound (position $eliminatedPosition)");
      simulatedRound++;
    }

    // Le dernier bot restant est le gagnant
    if (currentPlayers.isNotEmpty) {
      _tournamentFinalRanking!.add(TournamentResult(
        player: currentPlayers.first,
        finalPosition: 1,
        eliminatedAtRound: null, // Gagnant
      ));
      debugPrint("   Ã°Å¸Â¥â¡ ${currentPlayers.first.name} gagne le tournoi");
    }

    // Ajouter l'humain Ã  sa position
    _tournamentFinalRanking!.add(TournamentResult(
      player: human,
      finalPosition: humanFinalPosition,
      eliminatedAtRound: currentRound,
    ));

    // Trier par position finale
    _tournamentFinalRanking!.sort((a, b) => a.finalPosition.compareTo(b.finalPosition));

    debugPrint("   Ã°Å¸âÅ  Classement final du tournoi:");
    for (var result in _tournamentFinalRanking!) {
      debugPrint("      #${result.finalPosition}: ${result.player.name}");
    }

    // Marquer le tournoi comme terminÃÂ©
    _gameState!.tournamentRound = 3; // Force la fin du tournoi

    notifyListeners();
  }

  // Ã°Å¸Ââ  NOUVEAU : Obtenir les RP gagnÃÂ©s/perdus selon la position en tournoi
  int getTournamentRP(int finalPosition) {
    switch (finalPosition) {
      case 1:
        return 150; // Gagnant du tournoi
      case 2:
        return 60;  // Finaliste
      case 3:
        return -5;  // 3ÃÂ¨me place
      case 4:
        return -30; // 4ÃÂ¨me place (ÃÂ©liminÃÂ© en 1ÃÂ¨re manche)
      default:
        return 0;
    }
  }

  void startNextTournamentRound() {
    debugPrint("Ã°Å¸Ââ  [startNextTournamentRound] Manche suivante");

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
          botBehavior: p.botBehavior,
          botSkillLevel: p.botSkillLevel,
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

    // Ã¢Åâ¦ CORRECTION : Conserver le mode SBMM
    bool wasSBMM = _playerMMR != null;
    debugPrint("   - SBMM: $wasSBMM");

    createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId,
      useSBMM: wasSBMM, // Ã¢Åâ¦ CONSERVER LE MODE SBMM
    );
  }

  void quitGame() {
    debugPrint("Ã°Å¸Å¡Âª [quitGame] Nettoyage du gameState");
    _gameState = null;
    isProcessing = false;
    shakingCardIndices.clear();
    _reactionTimer?.cancel();
    _playerMMR = null;
    _tournamentFinalRanking = null; // Ã°Å¸Ââ  NOUVEAU : Reset du classement tournoi

    // Ã¢Åâ¦ NOUVEAU : Nettoyer les variables de pause
    _reactionPauseTime = null;
    _remainingReactionTimeMs = null;

    notifyListeners();
  }
}

// Ã°Å¸Ââ  NOUVEAU : Classe pour stocker les rÃÂ©sultats du tournoi
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