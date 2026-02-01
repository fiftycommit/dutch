import 'dart:math';
import '../../../models/player.dart';
import '../../../models/game_state.dart';

/// Résultat d'un tournoi
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

/// Manager dédié à la gestion des tournois
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion des tournois
/// Principe SOLID: SRP - Ne gère que la logique de tournoi
class TournamentManager {
  /// Scores cumulés du tournoi (persiste entre les manches)
  Map<String, int> _cumulativeScores = {};
  
  /// ID du tournoi actif
  String? _activeTournamentId;
  
  /// Classement final du tournoi
  List<TournamentResult>? _finalRanking;
  int? _initialPlayers;
  
  /// Getters
  Map<String, int> get cumulativeScores => _cumulativeScores;
  String? get activeTournamentId => _activeTournamentId;
  List<TournamentResult>? get finalRanking => _finalRanking;
  int? get initialPlayers => _initialPlayers;

  /// Initialiser un nouveau tournoi
  void initializeTournament(int tournamentRound, {required int playerCount}) {
    if (tournamentRound == 1) {
      _finalRanking = null;
      _cumulativeScores = {};
      _activeTournamentId = DateTime.now().millisecondsSinceEpoch.toString();
      _initialPlayers = playerCount;
    } else {
      _initialPlayers ??= playerCount + (tournamentRound - 1);
    }
  }

  /// Réinitialiser le tournoi
  void resetTournament() {
    _activeTournamentId = null;
    _finalRanking = null;
    _cumulativeScores = {};
    _initialPlayers = null;
  }

  /// Mettre à jour les scores cumulés
  void updateCumulativeScores(GameState gameState) {
    _cumulativeScores = Map.from(gameState.tournamentCumulativeScores);
  }

  /// Vérifier si le joueur humain est éliminé
  bool isHumanEliminated(GameState gameState) {
    if (gameState.gameMode != GameMode.tournament) return false;
    Player human = gameState.players.firstWhere((p) => p.isHuman);
    final keepIds = _getSurvivorIds(gameState);
    return !keepIds.contains(human.id);
  }

  /// Liste des joueurs éliminés à cette manche
  Set<String> getEliminatedPlayerIds(GameState gameState) {
    if (gameState.gameMode != GameMode.tournament) return {};
    final keepIds = _getSurvivorIds(gameState);
    return gameState.players
        .where((p) => !keepIds.contains(p.id))
        .map((p) => p.id)
        .toSet();
  }

  /// Terminer le tournoi pour le joueur humain (simulation des manches restantes)
  void finishTournamentForHuman(GameState gameState) {
    List<Player> ranking = gameState.getFinalRanking();
    Player human = gameState.players.firstWhere((p) => p.isHuman);
    int currentRound = gameState.tournamentRound;

    _finalRanking = [];

    int humanFinalPosition = gameState.players.length;

    List<Player> survivors = [];
    for (int i = 0; i < ranking.length; i++) {
      if (!ranking[i].isHuman) survivors.add(ranking[i]);
    }

    List<Player> currentPlayers = survivors;
    int simulatedRound = currentRound + 1;

    while (currentPlayers.length > 1) {
      currentPlayers.shuffle();
      int eliminatedPosition = currentPlayers.length;
      Player eliminated = currentPlayers.removeLast();

      _finalRanking!.add(TournamentResult(
        player: eliminated,
        finalPosition: eliminatedPosition,
        eliminatedAtRound: simulatedRound,
      ));

      simulatedRound++;
    }

    if (currentPlayers.isNotEmpty) {
      _finalRanking!.add(TournamentResult(
        player: currentPlayers.first,
        finalPosition: 1,
        eliminatedAtRound: null,
      ));
    }

    _finalRanking!.add(TournamentResult(
      player: human,
      finalPosition: humanFinalPosition,
      eliminatedAtRound: currentRound,
    ));

    _finalRanking!.sort((a, b) => a.finalPosition.compareTo(b.finalPosition));
  }

  /// Calculer les points de rang (RP) selon la position finale
  int calculateRP(int finalPosition) {
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

  int getTotalRounds(GameState gameState) {
    final initialCount =
        _initialPlayers ?? (gameState.players.length + (gameState.tournamentRound - 1));
    return max(1, initialCount - 1);
  }

  int _playersToKeep(int totalPlayers) => max(1, totalPlayers - 1);

  Set<String> _getSurvivorIds(GameState gameState) {
    final ranking = gameState.getFinalRanking();
    final keepCount = _playersToKeep(ranking.length);
    return ranking.take(keepCount).map((p) => p.id).toSet();
  }

  /// Préparer les survivants pour la manche suivante
  List<Player> prepareSurvivorsForNextRound(GameState gameState) {
    final keepIds = _getSurvivorIds(gameState);
    final survivors = gameState.players
        .where((p) => keepIds.contains(p.id))
        .toList();

    return survivors
        .map((p) => Player(
              id: p.id,
              name: p.name,
              isHuman: p.isHuman,
              botBehavior: p.botBehavior,
              botSkillLevel: p.botSkillLevel,
              aiParameters: p.aiParameters,
              position: p.position,
              isSpectator: p.isSpectator,
            ))
        .toList();
  }
}
