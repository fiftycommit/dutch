import 'dart:async';
import 'dart:math';
import '../models/card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/game_logic.dart';
import '../services/bot_ai.dart';
import '../services/stats_service.dart';
import '../services/haptic_service.dart';
import '../services/bot_learning_service.dart';
import '../services/player_learning_service.dart';
import 'package:flutter/widgets.dart';

class GameProvider with ChangeNotifier {
  GameState? _gameState;
  GameState? get gameState => _gameState;
  bool get hasActiveGame => _gameState != null;
  
  BuildContext? _currentContext;

  bool isProcessing = false;
  String? statusMessage;
  Set<int> shakingCardIndices = {};
  
  // Service d'apprentissage des bots
  final BotLearningService _botLearningService = BotLearningService();
  final PlayerLearningService _playerLearningService = PlayerLearningService();
  String? _currentGameId;

  int _humanActionCounter = 0;
  
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  Timer? _reactionTimer;
  int _currentReactionTimeMs = 3000;
  int get currentReactionTimeMs => _currentReactionTimeMs;
  int _currentSlotId = 1;

  int? _remainingReactionTimeMs;
  final ValueNotifier<int> reactionTimeRemaining = ValueNotifier<int>(0);

  int? _playerMMR;
  int? get playerMMR => _playerMMR;
  int _playerWinStreak = 0;
  int get playerWinStreak => _playerWinStreak;

  List<TournamentResult>? _tournamentFinalRanking;
  List<TournamentResult>? get tournamentFinalRanking => _tournamentFinalRanking;
  
  /// Scores cumulés du tournoi (persiste entre les manches)
  Map<String, int> _tournamentCumulativeScores = {};
  String? _activeTournamentId;

  void createNewGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    required int reactionTimeMs,
    int tournamentRound = 1,
    int saveSlot = 1,
    bool useSBMM = false,
  }) async {
    if (tournamentRound == 1) {
      _tournamentFinalRanking = null;
      _tournamentCumulativeScores = {}; // Réinitialiser les scores au début du tournoi
    }
    if (gameMode == GameMode.tournament) {
      if (_activeTournamentId == null || tournamentRound == 1) {
        _activeTournamentId = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } else {
      _activeTournamentId = null;
    }

    _gameState = GameLogic.initializeGame(
        players: players,
        gameMode: gameMode,
        difficulty: difficulty,
        tournamentRound: tournamentRound);
    
    // Propager les scores cumulés au GameState
    _gameState!.tournamentCumulativeScores = Map.from(_tournamentCumulativeScores);
    
    _currentReactionTimeMs = reactionTimeMs;
    _currentSlotId = saveSlot;

    if (useSBMM) {
      final stats = await StatsService.getStats(slotId: saveSlot);
      _playerMMR = stats['mmr'] ?? 0;
      _playerWinStreak = stats['winStreak'] ?? 0;
    } else {
      _playerMMR = null;
      _playerWinStreak = 0;
    }

    for (var player in _gameState!.players) {
      if (!player.isHuman) {
        player.initializeBotMemory();
      }
    }

    // Initialiser l'enregistrement pour les bots
    _currentGameId = DateTime.now().millisecondsSinceEpoch.toString();
    _humanActionCounter = 0;
    _playerLearningService.startGame(gameId: _currentGameId!);
    for (var player in _gameState!.players) {
      if (!player.isHuman) {
        _botLearningService.startGameRecording(
          gameId: _currentGameId!,
          bot: player,
          gameState: _gameState!,
          usedSBMM: useSBMM,
        );
        // Initialiser le premier round
        _botLearningService.startNewRound(player.id);
      }
    }

    shakingCardIndices.clear();
    isProcessing = false;
    notifyListeners();
  }

  void setContext(BuildContext context) {
    _currentContext = context;
  }

  void checkIfBotShouldPlay() {
    if (_gameState == null) return;
    if (isProcessing) return;
    if (_gameState!.phase != GamePhase.playing) return;
    if (_gameState!.currentPlayer.isHuman) return;

    _checkAndPlayBotTurn();
  }

  void drawCard() {
    if (_gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman) return;
    if (_gameState!.drawnCard != null) return;

    shakingCardIndices.clear();
    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    GameLogic.drawCard(_gameState!);
    final afterScore = human.getEstimatedScore();

    if (_currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'draw',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'source': 'deck',
          'drawnCard': _gameState!.drawnCard?.toJson(),
        },
      );
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
    notifyListeners();
  }

  void replaceCard(int cardIndex) {
    if (_gameState == null) return;
    if (!_gameState!.currentPlayer.isHuman) return;
    if (_gameState!.drawnCard == null) return;

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    final drawnCard = _gameState!.drawnCard;
    GameLogic.replaceCard(_gameState!, cardIndex);
    final afterScore = human.getEstimatedScore();
    
    // Tracker: enregistrer défausse pour tous les bots
    for (var player in _gameState!.players.where((p) => !p.isHuman)) {
      _botLearningService.recordDiscard(player.id);
    }

    if (_currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'replace',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'cardIndex': cardIndex,
          'drawnCard': drawnCard?.toJson(),
        },
      );
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
    HapticService.cardTap();
    notifyListeners();

    if (_checkInstantEnd()) return;

    if (_gameState!.isWaitingForSpecialPower) {
      _pauseReactionTimer();
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      startReactionPhase();
    }
  }

  void discardDrawnCard() {
    if (_gameState == null) return;
    if (!_gameState!.currentPlayer.isHuman) return;
    if (_gameState!.drawnCard == null) return;

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    final drawnCard = _gameState!.drawnCard;
    GameLogic.discardDrawnCard(_gameState!);
    final afterScore = human.getEstimatedScore();
    
    // Tracker: enregistrer défausse pour tous les bots
    for (var player in _gameState!.players.where((p) => !p.isHuman)) {
      _botLearningService.recordDiscard(player.id);
    }

    if (_currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'discard',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'source': 'drawn',
          'card': drawnCard?.toJson(),
        },
      );
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
    HapticService.cardTap();
    notifyListeners();

    if (_checkInstantEnd()) return;

    if (_gameState!.isWaitingForSpecialPower) {
      _pauseReactionTimer();
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState != null && _gameState!.isWaitingForSpecialPower) {
          notifyListeners();
        }
      });
    } else {
      startReactionPhase();
    }
  }

  void attemptMatch(int cardIndex, {Player? forcedPlayer}) async {
    if (_gameState == null) return;
    if (_gameState!.phase != GamePhase.reaction) return;

    Player player =
        forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);

    if (cardIndex < 0 || cardIndex >= player.hand.length) return;

    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);

    if (player.isHuman && _currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'match',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: player,
        actionDetails: {
          'cardIndex': cardIndex,
        },
      );
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'success': success,
        },
      );
    }

    if (player.isHuman) {
      if (success) {
        HapticService.cardTap();
      } else {
        HapticService.error();
      }
    }

    if (!success) {
      shakingCardIndices.add(cardIndex);
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      shakingCardIndices.remove(cardIndex);
    }

    notifyListeners();
  }

  void takeFromDiscard() {
    if (_gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman) return;
    if (_gameState!.drawnCard != null) return;
    if (_gameState!.discardPile.isEmpty) return;

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    _gameState!.drawnCard = _gameState!.discardPile.removeLast();
    _gameState!.addToHistory(
        "${_gameState!.currentPlayer.name} prend ${_gameState!.drawnCard!.displayName} de la défausse.");

    final afterScore = human.getEstimatedScore();
    if (_currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'draw',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'source': 'discard',
          'drawnCard': _gameState!.drawnCard?.toJson(),
        },
      );
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
    notifyListeners();
  }

  void callDutch() {
    if (_gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman) return;
    if (_gameState!.drawnCard != null) return;

    final human = _gameState!.currentPlayer;
    if (_currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'dutch',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {},
      );
    }
    _gameState!.phase = GamePhase.dutchCalled;
    _gameState!.dutchCallerId = human.id;
    _gameState!.addToHistory("📢 ${human.name} crie DUTCH !");
    endGame();
  }

  void skipSpecialPower() {
    if (_gameState == null) return;

    final human = _gameState!.currentPlayer;
    final specialCard = _gameState!.specialCardToActivate;
    if (human.isHuman && _currentGameId != null && specialCard != null) {
      final powerType = _getPowerType(specialCard);
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'power_skip',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'powerType': powerType,
        },
        powerType: powerType,
      );
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    _gameState!.addToHistory("⏭️ Pouvoir spécial ignoré.");
    notifyListeners();

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null) return;

    PlayingCard? specialCard = _gameState!.specialCardToActivate;
    if (specialCard == null) return;

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    final beforeScore = currentPlayer.isHuman ? currentPlayer.getEstimatedScore() : null;
    if (currentPlayer.isHuman && _currentGameId != null) {
      final powerType = _getPowerType(specialCard);
      final targetStrategy = _getTargetStrategy(targetPlayer);
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'power',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: currentPlayer,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerIndex': targetPlayerIndex,
          'targetCardIndex': targetCardIndex,
          'powerType': powerType,
          'targetPlayerId': targetPlayer.id,
        },
        powerType: powerType,
        targetStrategy: targetStrategy,
      );
    }

    if (specialCard.value == '7' || specialCard.value == '8') {
      if (targetCardIndex < currentPlayer.hand.length) {
        currentPlayer.knownCards[targetCardIndex] = true;
        _gameState!.addToHistory(
            "👁️ ${currentPlayer.name} regarde sa carte #${targetCardIndex + 1}");
      }
    } else if (specialCard.value == '9' || specialCard.value == '10') {
      if (targetCardIndex < targetPlayer.hand.length) {
        _gameState!.lastSpiedCard = targetPlayer.hand[targetCardIndex];
        _gameState!.addToHistory(
            "👁 ${currentPlayer.name} espionne ${targetPlayer.name} (carte #${targetCardIndex + 1})");
      }
    } else if (specialCard.value == 'V') {
      _gameState!.pendingSwap = {
        'targetPlayer': targetPlayerIndex,
        'targetCard': targetCardIndex,
        'ownCard': null,
      };
      notifyListeners();
      return;
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    if (currentPlayer.isHuman && _currentGameId != null && beforeScore != null) {
      final afterScore = currentPlayer.getEstimatedScore();
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
          'isBadDecision': PlayerLearningService.isBadPowerDecision(
            specialCard: specialCard,
            target: targetPlayer,
          ),
        },
      );
    }

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void completeSwap(int ownCardIndex) {
    if (_gameState == null || _gameState!.pendingSwap == null) return;

    int targetPlayerIndex = _gameState!.pendingSwap!['targetPlayer'];
    int targetCardIndex = _gameState!.pendingSwap!['targetCard'];

    Player currentPlayer = _gameState!.currentPlayer;
    Player targetPlayer = _gameState!.players[targetPlayerIndex];

    final beforeScore =
        currentPlayer.isHuman ? currentPlayer.getEstimatedScore() : null;
    if (currentPlayer.isHuman && _currentGameId != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'power',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: currentPlayer,
        actionDetails: {
          'specialCard': {'value': 'V'},
          'targetPlayerIndex': targetPlayerIndex,
          'targetCardIndex': targetCardIndex,
          'ownCardIndex': ownCardIndex,
        },
      );
    }

    PlayingCard? myCard = currentPlayer.hand[ownCardIndex];
    PlayingCard? theirCard = targetPlayer.hand[targetCardIndex];

    currentPlayer.hand[ownCardIndex] = theirCard;
    targetPlayer.hand[targetCardIndex] = myCard;

    currentPlayer.knownCards[ownCardIndex] = false;
    targetPlayer.knownCards[targetCardIndex] = false;

    _gameState!.addToHistory(
        "🔄 ${currentPlayer.name} échange avec ${targetPlayer.name}");

    _gameState!.pendingSwap = null;
    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;

    notifyListeners();

    if (currentPlayer.isHuman && _currentGameId != null && beforeScore != null) {
      final afterScore = currentPlayer.getEstimatedScore();
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void executeLookAtCard(Player target, int cardIndex) {
    if (_gameState == null) return;

    final human = _gameState!.currentPlayer;
    final specialCard = _gameState!.specialCardToActivate;
    final beforeScore = human.isHuman ? human.getEstimatedScore() : null;
    if (human.isHuman && _currentGameId != null && specialCard != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'power',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerId': target.id,
          'targetCardIndex': cardIndex,
        },
      );
    }

    if (cardIndex >= 0 && cardIndex < target.hand.length) {
      if (target.isHuman) {
        target.knownCards[cardIndex] = true;
      }
      _gameState!.lastSpiedCard = target.hand[cardIndex];
      GameLogic.lookAtCard(_gameState!, target, cardIndex);
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    if (human.isHuman &&
        _currentGameId != null &&
        beforeScore != null &&
        specialCard != null) {
      final afterScore = human.getEstimatedScore();
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
          'isBadDecision': PlayerLearningService.isBadPowerDecision(
            specialCard: specialCard,
            target: target,
          ),
        },
      );
    }

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void executeJokerEffect(Player target) {
    if (_gameState == null) return;

    final human = _gameState!.currentPlayer;
    final specialCard = _gameState!.specialCardToActivate;
    final beforeScore = human.isHuman ? human.getEstimatedScore() : null;
    if (human.isHuman && _currentGameId != null && specialCard != null) {
      _playerLearningService.recordAction(
        gameId: _currentGameId!,
        actionType: 'power',
        turnNumber: ++_humanActionCounter,
        gameState: _gameState!,
        human: human,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerId': target.id,
        },
      );
    }

    GameLogic.jokerEffect(_gameState!, target);

    if (target.isHuman) {
      for (int i = 0; i < target.knownCards.length; i++) {
        target.knownCards[i] = false;
      }
    }

    _gameState!.isWaitingForSpecialPower = false;
    _gameState!.specialCardToActivate = null;
    notifyListeners();

    if (human.isHuman &&
        _currentGameId != null &&
        beforeScore != null &&
        specialCard != null) {
      final afterScore = human.getEstimatedScore();
      _playerLearningService.updateLastActionResult(
        gameId: _currentGameId!,
        result: {
          'scoreChange': afterScore - beforeScore,
          'isBadDecision': PlayerLearningService.isBadPowerDecision(
            specialCard: specialCard,
            target: target,
          ),
        },
      );
    }

    _resumeReactionTimer();

    if (_gameState!.phase == GamePhase.playing) {
      startReactionPhase();
    }
  }

  void pauseReactionTimerForNotification() {
    _pauseReactionTimer();
  }

  void resumeReactionTimerAfterNotification() {
    _resumeReactionTimer();
  }

  void startReactionPhase() {
    if (_gameState == null) return;
    if (_isPaused) return; // Ne pas démarrer si en pause

    _gameState!.phase = GamePhase.reaction;
    _gameState!.reactionTimeRemaining = _currentReactionTimeMs;
    reactionTimeRemaining.value = _currentReactionTimeMs;

    _reactionTimer?.cancel();

    _reactionTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_gameState == null) {
        timer.cancel();
        return;
      }
      
      // Ne pas décrémenter si en pause
      if (_isPaused) return;

      _gameState!.reactionTimeRemaining -= 30;
      reactionTimeRemaining.value = _gameState!.reactionTimeRemaining;

      if (_gameState!.reactionTimeRemaining <= 0) {
        timer.cancel();
        _endReactionPhase();
        return;
      }
      
      notifyListeners();
    });

    notifyListeners();
    _simulateBotReaction();
  }

  void _pauseReactionTimer() {
    if (_reactionTimer != null && _reactionTimer!.isActive) {
      _reactionTimer!.cancel();
      _remainingReactionTimeMs = _gameState?.reactionTimeRemaining;
    }
  }

  void _resumeReactionTimer() {
    if (_remainingReactionTimeMs != null &&
        _remainingReactionTimeMs! > 0 &&
        _gameState != null) {
      _gameState!.reactionTimeRemaining = _remainingReactionTimeMs!;
      reactionTimeRemaining.value = _remainingReactionTimeMs!;

      _reactionTimer?.cancel();
      _reactionTimer =
          Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (_gameState == null) {
          timer.cancel();
          return;
        }

        if (_isPaused) {
          timer.cancel();
          return;
        }

        _gameState!.reactionTimeRemaining -= 30;
        reactionTimeRemaining.value = _gameState!.reactionTimeRemaining;

        if (_gameState!.reactionTimeRemaining <= 0) {
          timer.cancel();
          _endReactionPhase();
        }

        notifyListeners();
      });

      _remainingReactionTimeMs = null;
      notifyListeners();
    }
  }

  void _endReactionPhase() {
    if (_gameState == null) return;
    if (_isPaused) return; // Ne pas terminer si en pause

    _reactionTimer?.cancel();
    _gameState!.phase = GamePhase.playing;
    _gameState!.lastSpiedCard = null;

    GameLogic.nextPlayer(_gameState!);
    
    // Tracker: incrémenter le compteur de tours pour tous les bots à chaque changement de joueur
    for (var player in _gameState!.players.where((p) => !p.isHuman)) {
      _botLearningService.incrementTurn(player.id);
    }
    
    notifyListeners();

    if (!_gameState!.currentPlayer.isHuman && !_isPaused) {
      _checkAndPlayBotTurn();
    }
  }

  void _simulateBotReaction() async {
    if (_gameState == null || _gameState!.phase != GamePhase.reaction) return;
    if (_isPaused) return; // Ne pas simuler si en pause

    PlayingCard? topCard = _gameState!.topDiscardCard;
    if (topCard == null) return;

    for (var bot in _gameState!.players.where((p) => !p.isHuman)) {
      if (_gameState == null || _gameState!.phase != GamePhase.reaction) return;
      if (_isPaused) return; // Vérifier à chaque itération

      int delay = Random().nextInt(800) + 300;
      await Future.delayed(Duration(milliseconds: delay));

      if (_gameState == null || _gameState!.phase != GamePhase.reaction) return;

      bool matched =
          await BotAI.tryReactionMatch(_gameState!, bot, playerMMR: _playerMMR);

      if (matched) {
        notifyListeners();
        return;
      }
    }
    
    // Notify listeners even if no bot matched to ensure UI updates
    notifyListeners();
  }

  bool _checkInstantEnd() {
    if (_gameState == null) return false;
    if (_gameState!.deck.isEmpty) {
      // Essayer de remplir la pioche avec la défausse
      _refillDeckFromDiscard();
      // Si toujours vide après avoir essayé de remplir, terminer le jeu
      if (_gameState!.deck.isEmpty) {
        endGame();
        return true;
      }
    }
    return false;
  }
  
  /// Remplit la pioche avec les cartes de la défausse (sauf la carte du dessus)
  /// Utilise smartShuffle avec le mode de mélange des paramètres
  void _refillDeckFromDiscard() {
    if (_gameState == null) return;
    if (_gameState!.discardPile.length > 1) {
      // Garder la carte du dessus de la défausse
      PlayingCard topCard = _gameState!.discardPile.removeLast();
      // Ajouter le reste à la pioche
      _gameState!.deck.addAll(_gameState!.discardPile);
      _gameState!.discardPile.clear();
      _gameState!.discardPile.add(topCard);
      // Mélanger la nouvelle pioche avec smartShuffle (utilise la difficulté du gameState)
      _gameState!.smartShuffle();
      _gameState!.addToHistory("🔄 Pioche vide ! Défausse mélangée (${_gameState!.deck.length} cartes)");
      notifyListeners();
    }
  }

  Future<void> _checkAndPlayBotTurn() async {
    if (_gameState == null) return;
    if (_gameState!.phase == GamePhase.ended) return;
    if (_isPaused) return; // Ne pas jouer si en pause
    if (_checkInstantEnd()) return;

    if (_gameState!.currentPlayer.isHuman) {
      isProcessing = false;
      notifyListeners();
      return;
    }

    int loopCount = 0;
    while (_gameState != null &&
        !_gameState!.currentPlayer.isHuman &&
        _gameState!.phase == GamePhase.playing &&
        !_isPaused) { // Arrêter la boucle si en pause
      loopCount++;

      if (loopCount > 10) break;
      if (_isPaused) break; // Arrêter si en pause
      if (_checkInstantEnd()) return;

      isProcessing = true;
      notifyListeners();

      // Attendre mais vérifier la pause régulièrement
      for (int i = 0; i < 8; i++) {
        if (_isPaused) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_isPaused) break;

      if (_gameState == null) break;

      try {
        if (_isPaused) break;
        await BotAI.playBotTurn(_gameState!, playerMMR: _playerMMR, context: _currentContext);
        if (_isPaused) break;
        notifyListeners();

        if (_gameState!.phase == GamePhase.dutchCalled) {
          endGame();
          return;
        }

        if (_gameState!.isWaitingForSpecialPower) {
          // Attendre mais vérifier la pause
          for (int i = 0; i < 8; i++) {
            if (_isPaused) break;
            await Future.delayed(const Duration(milliseconds: 100));
          }
          if (_isPaused) break;
          
          await BotAI.useBotSpecialPower(_gameState!, playerMMR: _playerMMR, context: _currentContext);
          if (_isPaused) break;
          notifyListeners();

          _gameState!.isWaitingForSpecialPower = false;
          _gameState!.specialCardToActivate = null;
        }
      } catch (e) {
        if (_gameState != null && _gameState!.drawnCard != null) {
          _gameState!.discardPile.add(_gameState!.drawnCard!);
          _gameState!.drawnCard = null;
        }
      }

      if (_isPaused) break;
      if (_gameState != null && _gameState!.phase == GamePhase.playing) {
        startReactionPhase();
        break;
      } else {
        break;
      }
    }

    isProcessing = false;
    notifyListeners();
  }

  void pauseGame() {
    _isPaused = true;
    _pauseReactionTimer();
    isProcessing = false; // Arrêter le processing
    notifyListeners();
  }
  
  void resumeGame() {
    _isPaused = false;
    // Reprendre le timer de réaction si on était en phase reaction
    if (_gameState != null && _gameState!.phase == GamePhase.reaction && _remainingReactionTimeMs != null) {
      _resumeReactionTimer();
    }
    notifyListeners();
    // Relancer le tour des bots si c'est leur tour
    if (_gameState != null && !_gameState!.currentPlayer.isHuman && _gameState!.phase == GamePhase.playing) {
      _checkAndPlayBotTurn();
    }
  }

  void endGame() {
    if (_gameState == null) return;
    _gameState!.phase = GamePhase.ended;

    for (var p in _gameState!.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }

    // Finaliser l'enregistrement des bots
    _finalizeBotRecordings();

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    int playerRank = ranking.indexWhere((p) => p.id == human.id) + 1;
    bool calledDutch = _gameState!.dutchCallerId == human.id;
    bool wonDutch = calledDutch && playerRank == 1;
    bool isSBMM = _playerMMR != null;

    final gameId = _currentGameId;
    if (gameId != null) {
      _playerLearningService
          .endGame(
            gameId: gameId,
            slotId: _currentSlotId,
            usedSBMM: isSBMM,
            gameState: _gameState!,
            human: human,
            finalRank: playerRank,
            finalScore: _gameState!.getFinalScore(human),
            calledDutch: calledDutch,
            wonDutch: wonDutch,
          )
          .then((_) {});
    }

    if (_gameState!.dutchCallerId != null) {
      Player dutchCaller = _gameState!.players
          .firstWhere((p) => p.id == _gameState!.dutchCallerId);
      int dutchCallerRank =
          ranking.indexWhere((p) => p.id == dutchCaller.id) + 1;

      if (!dutchCaller.isHuman) {
        dutchCaller.dutchHistory.add(DutchAttempt(
          estimatedScore: dutchCaller.getEstimatedScore(),
          actualScore: _gameState!.getFinalScore(dutchCaller),
          won: dutchCallerRank == 1,
          opponentsCount: _gameState!.players.length - 1,
        ));

        if (dutchCaller.dutchHistory.length > 10) {
          dutchCaller.dutchHistory.removeAt(0);
        }
      }
    }

    final ranksWithTies = _gameState!.getFinalRanksWithTies();
    _gameState!.addToHistory("🏁 Classement final");
    String rankEmoji(int rank) {
      switch (rank) {
        case 1:
          return "🥇";
        case 2:
          return "🥈";
        case 3:
          return "🥉";
        default:
          return "";
      }
    }
    for (int i = 0; i < ranking.length; i++) {
      final player = ranking[i];
      final rank = ranksWithTies[player.id] ?? (i + 1);
      final score = _gameState!.getFinalScore(player);
      final badge = rankEmoji(rank);
      final badgePrefix = badge.isEmpty ? "" : "$badge ";
      final dutchTag =
          player.id == _gameState!.dutchCallerId ? " (DUTCH)" : "";
      _gameState!
          .addToHistory("$badgePrefix#$rank ${player.name}$dutchTag — $score pts");
    }

    // Calculer le numéro de manche tournoi (1, 2 ou 3)
    int currentTournamentRound = _gameState!.gameMode == GameMode.tournament 
        ? _gameState!.tournamentRound 
        : 1;
    
    // Nombre de joueurs dans cette manche
    int totalPlayersInRound = _gameState!.players.length;
    
    StatsService.saveGameResult(
      playerRank: playerRank,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      hasEmptyHand: human.hand.isEmpty,
      slotId: _currentSlotId,
      isSBMM: isSBMM,
      totalPlayers: totalPlayersInRound,
      isTournament: _gameState!.gameMode == GameMode.tournament,
      tournamentRound: currentTournamentRound,
      tournamentId: _activeTournamentId,
      actionHistory: List<String>.from(_gameState!.actionHistory),
    );

    notifyListeners();
  }

  bool isHumanEliminatedInTournament() {
    if (_gameState == null) return false;
    if (_gameState!.gameMode != GameMode.tournament) return false;

    List<Player> ranking = _gameState!.getFinalRanking();
    final ranksWithTies = _gameState!.getFinalRanksWithTies();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);

    int humanRank = ranksWithTies[human.id] ??
        (ranking.indexWhere((p) => p.id == human.id) + 1);
    int lastRank = ranking.length;
    if (ranksWithTies.isNotEmpty) {
      lastRank = ranksWithTies.values.reduce(max);
    }
    return humanRank == lastRank;
  }

  void finishTournamentForHuman() {
    if (_gameState == null) return;

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);
    int currentRound = _gameState!.tournamentRound;

    _tournamentFinalRanking = [];

    int humanFinalPosition = 5 - currentRound;

    List<Player> survivors = [];
    for (int i = 0; i < ranking.length - 1; i++) {
      survivors.add(ranking[i]);
    }

    List<Player> currentPlayers = survivors;
    int simulatedRound = currentRound + 1;

    while (currentPlayers.length > 1 && simulatedRound <= 3) {
      currentPlayers.shuffle();
      Player eliminated = currentPlayers.removeLast();

      int eliminatedPosition = 5 - simulatedRound;
      _tournamentFinalRanking!.add(TournamentResult(
        player: eliminated,
        finalPosition: eliminatedPosition,
        eliminatedAtRound: simulatedRound,
      ));

      simulatedRound++;
    }

    if (currentPlayers.isNotEmpty) {
      _tournamentFinalRanking!.add(TournamentResult(
        player: currentPlayers.first,
        finalPosition: 1,
        eliminatedAtRound: null,
      ));
    }

    _tournamentFinalRanking!.add(TournamentResult(
      player: human,
      finalPosition: humanFinalPosition,
      eliminatedAtRound: currentRound,
    ));

    _tournamentFinalRanking!
        .sort((a, b) => a.finalPosition.compareTo(b.finalPosition));

    _gameState!.tournamentRound = 3;
    notifyListeners();
  }

  int getTournamentRP(int finalPosition) {
    switch (finalPosition) {
      case 1:
        return 150;
      case 2:
        return 60;
      case 3:
        return -5;
      case 4:
        return -30;
      default:
        return 0;
    }
  }

  void startNextTournamentRound() {
    if (_gameState == null) return;

    // Mettre à jour les scores cumulés avant de changer de manche
    _gameState!.updateCumulativeScores();
    _tournamentCumulativeScores = Map.from(_gameState!.tournamentCumulativeScores);

    List<Player> ranking = _gameState!.getFinalRanking();
    List<Player> survivors = [];
    
    // Adapter le nombre de joueurs gardés selon le nombre actuel
    // 6 joueurs → 4 → 3 → 2 (4 parties)
    // 5 joueurs → 4 → 3 → 2 (4 parties)
    // 4 joueurs → 3 → 2 (3 parties)
    // 3 joueurs → 2 (2 parties)
    int playersToKeep;
    if (ranking.length >= 6) {
      playersToKeep = 4; // Garder 4 joueurs sur 6
    } else if (ranking.length >= 5) {
      playersToKeep = 4; // Garder 4 joueurs sur 5
    } else if (ranking.length >= 4) {
      playersToKeep = 3; // Garder 3 joueurs sur 4
    } else {
      playersToKeep = ranking.length - 1; // Éliminer 1 joueur
    }

    for (int i = 0; i < playersToKeep; i++) {
      Player p = ranking[i];
      survivors.add(Player(
          id: p.id,
          name: p.name,
          isHuman: p.isHuman,
          botBehavior: p.botBehavior,
          botSkillLevel: p.botSkillLevel,
          position: i));
    }

    if (survivors.length < 2) return;

    bool wasSBMM = _playerMMR != null;

    createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId,
      useSBMM: wasSBMM,
    );
  }

  void quitGame() {
    // Enregistrer l'abandon comme une défaite (dernier)
    if (_gameState != null) {
      int playerCount = _gameState!.players.length;
      
      // Enregistrer dans les stats comme si on avait fini dernier
      StatsService.saveGameResult(
        score: 999, // Score élevé = défaite
        playerRank: playerCount, // Dernier
        calledDutch: false,
        wonDutch: false,
        hasEmptyHand: false, // Abandon = pas de main vide
        isSBMM: _playerMMR != null,
        slotId: _currentSlotId,
        totalPlayers: playerCount,
        isTournament: _gameState!.gameMode == GameMode.tournament,
        tournamentRound: _gameState!.tournamentRound,
        tournamentId: _activeTournamentId,
        actionHistory: List<String>.from(_gameState!.actionHistory),
      );
    }
    
    _gameState = null;
    _isPaused = false;
    isProcessing = false;
    shakingCardIndices.clear();
    _reactionTimer?.cancel();
    _playerMMR = null;
    _tournamentFinalRanking = null;
    _remainingReactionTimeMs = null;
    _activeTournamentId = null;
    notifyListeners();
  }

  /// Enregistre une action de bot

  /// Termine l'enregistrement des bots en fin de partie
  Future<void> _finalizeBotRecordings() async {
    if (_gameState == null || _currentGameId == null) return;
    
    // Calculer les rangs finaux
    final players = List<Player>.from(_gameState!.players);
    players.sort((a, b) => a.calculateScore().compareTo(b.calculateScore()));
    
    final human = _gameState!.players.firstWhere((p) => p.isHuman);
    final humanFinalScore = _gameState!.getFinalScore(human);
    final humanFinalHandSize = human.hand.length;

    for (var player in _gameState!.players) {
      if (player.isHuman) continue;
      
      final rank = players.indexOf(player) + 1;
      final calledDutch = _gameState!.dutchCallerId == player.id;
      final wonDutch = calledDutch && rank == 1;
      
      await _botLearningService.endGameRecording(
        botPlayerId: player.id,
        finalScore: player.calculateScore(),
        finalRank: rank,
        calledDutch: calledDutch,
        wonDutch: wonDutch,
        cardsAtDutch: calledDutch ? player.hand.length : 0,
        scoreAtDutch: calledDutch ? player.calculateScore() : 0,
        humanFinalScore: humanFinalScore,
        humanFinalHandSize: humanFinalHandSize,
        botFinalHandSize: player.hand.length,
      );
    }
  }

  String _getPowerType(PlayingCard card) {
    if (card.value == '7' || card.value == '8') return card.value;
    if (card.value == '9' || card.value == '10') return card.value;
    if (card.value == 'V') return 'jack';
    if (card.value == 'JOKER') return 'joker';
    return 'unknown';
  }

  String _getTargetStrategy(Player target) {
    if (_gameState == null) return 'random';
    final players = List<Player>.from(_gameState!.players);
    players.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
    final targetRank = players.indexOf(target) + 1;
    if (targetRank == 1) return 'leader';
    if (targetRank == players.length) return 'weak';
    return 'balanced';
  }

  @override
  void dispose() {
    _reactionTimer?.cancel();
    reactionTimeRemaining.dispose();
    super.dispose();
  }
}

class TournamentResult {
  final Player player;
  final int finalPosition;
  final int? eliminatedAtRound;

  TournamentResult({
    required this.player,
    required this.finalPosition,
    this.eliminatedAtRound,
  });
}
