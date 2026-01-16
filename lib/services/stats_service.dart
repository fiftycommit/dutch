import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_settings.dart'; 

class StatsService {
  static const String _statsKeyPrefix = 'game_stats_slot_';

  static String _getKey(int slotId) => '$_statsKeyPrefix$slotId';

  static Future<Map<String, dynamic>> getStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    String? statsJson = prefs.getString(_getKey(slotId));
    
    if (statsJson == null) {
      return _getEmptyStats();
    }
    
    try {
      return jsonDecode(statsJson);
    } catch (e) {
      return _getEmptyStats();
    }
  }

  static Map<String, dynamic> _getEmptyStats() {
    return {
      "gamesPlayed": 0,
      "gamesWon": 0,
      "bestScore": null,
      "totalScore": 0,
      "mmr": 0, 
      "dutchCalls": 0,
      "dutchWins": 0,
      "history": [],
    };
  }

  static Future<void> saveGameResult({
    required bool isWin,
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    int slotId = 1,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> stats = await getStats(slotId: slotId);

    stats["gamesPlayed"] = (stats["gamesPlayed"] ?? 0) + 1;
    if (isWin) stats["gamesWon"] = (stats["gamesWon"] ?? 0) + 1;
    
    int? currentBest = stats["bestScore"];
    if (currentBest == null || score < currentBest) {
      stats["bestScore"] = score;
    }
    stats["totalScore"] = (stats["totalScore"] ?? 0) + score;

    if (calledDutch) {
      stats["dutchCalls"] = (stats["dutchCalls"] ?? 0) + 1;
      if (wonDutch) stats["dutchWins"] = (stats["dutchWins"] ?? 0) + 1;
    }

    // --- LOGIQUE MMR (Points de Classement) ---
    int currentMMR = stats["mmr"] ?? 0;
    int mmrChange = 0;

    if (isWin) {
      mmrChange += 50; // Victoire standard (Rapide !)
      if (wonDutch) mmrChange += 30; // Bonus Dutch réussi
    } else {
      if (calledDutch && !wonDutch) {
        mmrChange -= 50; // 💥 SANCTION : Dutch raté = -50 pts
      } else {
        mmrChange -= 20; // Défaite classique
      }
    }

    int newMMR = currentMMR + mmrChange;
    if (newMMR < 0) newMMR = 0; // On ne descend pas en négatif
    
    stats["mmr"] = newMMR;
    // ------------------------------------------

    List<dynamic> history = List.from(stats["history"] ?? []);
    history.insert(0, {
      "date": DateTime.now().toIso8601String(),
      "score": score,
      "win": isWin,
      "dutch": calledDutch,
      "mmrChange": mmrChange,
    });
    
    if (history.length > 20) history = history.sublist(0, 20);
    stats["history"] = history;

    await prefs.setString(_getKey(slotId), jsonEncode(stats));
  }

  static Future<void> resetStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(slotId));
  }

  // --- NOUVEAUX PALIERS PLUS RAPIDES ---
  static Future<Difficulty> getRecommendedDifficulty({int slotId = 1}) async {
    Map<String, dynamic> stats = await getStats(slotId: slotId);
    int mmr = stats["mmr"] ?? 0;

    if (mmr < 150) { // En 3 victoires on sort du mode facile
      return Difficulty.easy; 
    } else if (mmr < 450) { // Environ 6 victoires de plus pour passer Expert
      return Difficulty.medium; 
    } else {
      return Difficulty.hard; 
    }
  }
  
  static String getRankName(int mmr) {
    if (mmr < 150) return "Bronze";
    if (mmr < 450) return "Argent";
    return "Or";
  }
}