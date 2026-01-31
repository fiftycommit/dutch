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
  
  /// Getters
  Map<String, int> get cumulativeScores => _cumulativeScores;
  String? get activeTournamentId => _activeTournamentId;
  List<TournamentResult>? get finalRanking => _finalRanking;

  /// Initialiser un nouveau tournoi
  void initializeTournament(int tournamentRound) {
    if (tournamentRound == 1) {
      _finalRanking = null;
      _cumulativeScores = {};
      _activeTournamentId = DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  /// Réinitialiser le tournoi
  void resetTournament() {
    _activeTournamentId = null;
    _finalRanking = null;
    _cumulativeScores = {};
  }

  /// Mettre à jour les scores cumulés
  void updateCumulativeScores(GameState gameState) {
    _cumulativeScores = Map.from(gameState.tournamentCumulativeScores);
  }

  /// Vérifier si le joueur humain est éliminé
  bool isHumanEliminated(GameState gameState) {
    if (gameState.gameMode != GameMode.tournament) return false;

    List<Player> ranking = gameState.getFinalRanking();
    final ranksWithTies = gameState.getFinalRanksWithTies();
    Player human = gameState.players.firstWhere((p) => p.isHuman);

    int humanRank = ranksWithTies[human.id] ??
        (ranking.indexWhere((p) => p.id == human.id) + 1);
    int lastRank = ranking.length;
    if (ranksWithTies.isNotEmpty) {
      lastRank = ranksWithTies.values.reduce(max);
    }
    return humanRank == lastRank;
  }

  /// Terminer le tournoi pour le joueur humain (simulation des manches restantes)
  void finishTournamentForHuman(GameState gameState) {
    List<Player> ranking = gameState.getFinalRanking();
    Player human = gameState.players.firstWhere((p) => p.isHuman);
    int currentRound = gameState.tournamentRound;

    _finalRanking = [];

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

  /// Préparer les survivants pour la manche suivante
  List<Player> prepareSurvivorsForNextRound(GameState gameState) {
    List<Player> ranking = gameState.getFinalRanking();
    List<Player> survivors = [];
    
    // Adapter le nombre de joueurs gardés selon le nombre actuel
    int playersToKeep;
    if (ranking.length >= 6) {
      playersToKeep = 4;
    } else if (ranking.length >= 5) {
      playersToKeep = 4;
    } else if (ranking.length >= 4) {
      playersToKeep = 3;
    } else {
      playersToKeep = ranking.length - 1;
    }

    for (int i = 0; i < playersToKeep; i++) {
      Player p = ranking[i];
      survivors.add(Player(
        id: p.id,
        name: p.name,
        isHuman: p.isHuman,
        botBehavior: p.botBehavior,
        botSkillLevel: p.botSkillLevel,
        position: i,
      ));
    }

    return survivors;
  }
}
