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
    required int playerRank, // 🆕 Classement (1, 2, 3, 4)
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    int slotId = 1,
    bool isSBMM = false, // 🆕 Flag SBMM
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> stats = await getStats(slotId: slotId);

    // --- MISE À JOUR DES STATISTIQUES GÉNÉRALES ---
    stats["gamesPlayed"] = (stats["gamesPlayed"] ?? 0) + 1;
    
    // Seul le premier est considéré comme gagnant
    if (playerRank == 1) {
      stats["gamesWon"] = (stats["gamesWon"] ?? 0) + 1;
    }
    
    // Mise à jour du meilleur score
    int? currentBest = stats["bestScore"];
    if (currentBest == null || score < currentBest) {
      stats["bestScore"] = score;
    }
    stats["totalScore"] = (stats["totalScore"] ?? 0) + score;

    // Statistiques Dutch
    if (calledDutch) {
      stats["dutchCalls"] = (stats["dutchCalls"] ?? 0) + 1;
      if (wonDutch) {
        stats["dutchWins"] = (stats["dutchWins"] ?? 0) + 1;
      }
    }

    // --- LOGIQUE MMR AMÉLIORÉE (Système de classement) ---
    int currentMMR = stats["mmr"] ?? 0;
    int mmrChange = 0;

    // ✅ NOUVEAU : RP = 0 si pas SBMM
    if (isSBMM) {
      // 🏆 Calcul selon le classement
      switch (playerRank) {
        case 1: // 🥇 Premier
          mmrChange = 50; // Victoire de base
          if (calledDutch) {
            mmrChange += 30; // Bonus Dutch réussi
          }
          break;
          
        case 2: // 🥈 Deuxième
          mmrChange = 25; // Récompense pour la 2ème place
          break;
          
        case 3: // 🥉 Troisième
          mmrChange = -15; // Légère pénalité
          break;
          
        case 4: // 💀 Quatrième
          mmrChange = -30; // Grosse pénalité
          if (calledDutch && !wonDutch) {
            mmrChange -= 30; // Pénalité Dutch raté (-30 supplémentaires)
          }
          break;
      }

      int newMMR = currentMMR + mmrChange;
      if (newMMR < 0) newMMR = 0; // On ne descend pas en négatif
      
      stats["mmr"] = newMMR;
    } else {
      // ✅ Mode manuel : RP = 0
      mmrChange = 0;
      // Le MMR ne change pas
    }
    // ------------------------------------------

    // --- HISTORIQUE DES PARTIES ---
    List<dynamic> history = List.from(stats["history"] ?? []);
    history.insert(0, {
      "date": DateTime.now().toIso8601String(),
      "score": score,
      "rank": playerRank, // 🆕 Sauvegarder le classement
      "dutch": calledDutch,
      "mmrChange": mmrChange, // ✅ 0 si pas SBMM
    });
    
    if (history.length > 20) history = history.sublist(0, 20);
    stats["history"] = history;

    // --- SAUVEGARDE ---
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