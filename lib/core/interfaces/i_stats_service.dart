import '../../models/game_settings.dart';

/// Interface abstraite pour le service de statistiques
/// Principe SOLID: DIP - Dépendance sur une abstraction
/// Principe SOLID: ISP - Interface ségrégée pour les statistiques
abstract class IStatsService {
  /// Récupérer les statistiques d'un slot
  Future<Map<String, dynamic>> getStats({int slotId = 1});

  /// Sauvegarder le résultat d'une partie
  Future<void> saveGameResult({
    required int playerRank,
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    bool hasEmptyHand = false,
    int slotId = 1,
    bool isSBMM = false,
    int totalPlayers = 4,
    bool isTournament = false,
    int tournamentRound = 1,
    String? tournamentId,
    List<String>? actionHistory,
    String? gameLog,
    String? scoreDetail,
  });

  /// Réinitialiser les statistiques d'un slot
  Future<void> resetStats({int slotId = 1});

  /// Obtenir la difficulté recommandée basée sur le MMR
  Future<Difficulty> getRecommendedDifficulty({int slotId = 1});

  /// Obtenir le nom du rang basé sur le MMR
  String getRankName(int mmr);
  
  /// Enregistrer les données de télémétrie AI pour calibrage SBMM
  Future<void> recordAiTelemetry(Map<String, dynamic> telemetry, {int slotId = 1});
}
