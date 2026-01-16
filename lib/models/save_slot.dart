// import 'package:hive/hive.dart'; // Commenté - non utilisé actuellement

// part 'save_slot.g.dart'; // Commenté - nécessite build_runner

// @HiveType(typeId: 0)
class SaveSlot {
  // @HiveField(0)
  final int slotNumber;

  // @HiveField(1)
  String playerName;

  // @HiveField(2)
  int totalXP;

  // @HiveField(3)
  int tournamentsWon;

  // @HiveField(4)
  int finalistCount;

  // @HiveField(5)
  int semifinalistCount;

  // @HiveField(6)
  int quarterfinalistCount;

  // @HiveField(7)
  int tournamentsPlayed;

  // @HiveField(8)
  int quickGamesPlayed;

  // @HiveField(9)
  int quickGamesWon;

  // @HiveField(10)
  int bestScore;

  // @HiveField(11)
  int dutchSuccessCount;

  // @HiveField(12)
  DateTime lastPlayed;

  // @HiveField(13)
  List<String> unlockedBotTiers;

  SaveSlot({
    required this.slotNumber,
    this.playerName = 'Joueur',
    this.totalXP = 0,
    this.tournamentsWon = 0,
    this.finalistCount = 0,
    this.semifinalistCount = 0,
    this.quarterfinalistCount = 0,
    this.tournamentsPlayed = 0,
    this.quickGamesPlayed = 0,
    this.quickGamesWon = 0,
    this.bestScore = 999,
    this.dutchSuccessCount = 0,
    DateTime? lastPlayed,
    List<String>? unlockedBotTiers,
  })  : lastPlayed = lastPlayed ?? DateTime.now(),
        unlockedBotTiers = unlockedBotTiers ?? ['beginner'];

  int get currentLevel => calculateLevel();
  
  int calculateLevel() {
    // Paliers de niveaux exponentiels
    const levels = [
      0, 500, 1500, 3000, 5000, 7500, 10500, 14000, 18000, 23000
    ];
    
    for (int i = levels.length - 1; i >= 0; i--) {
      if (totalXP >= levels[i]) {
        return i + 1;
      }
    }
    
    // Au-delà du niveau 10
    if (totalXP >= 23000) {
      int extraXP = totalXP - 23000;
      return 10 + (extraXP ~/ 6000);
    }
    
    return 1;
  }

  int xpToNextLevel() {
    const levels = [
      0, 500, 1500, 3000, 5000, 7500, 10500, 14000, 18000, 23000
    ];
    
    int currentLvl = currentLevel;
    
    if (currentLvl < levels.length) {
      return levels[currentLvl] - totalXP;
    }
    
    // Au-delà du niveau 10
    int currentThreshold = 23000 + ((currentLvl - 10) * 6000);
    int nextThreshold = currentThreshold + 6000;
    return nextThreshold - totalXP;
  }

  int xpForCurrentLevel() {
    const levels = [
      0, 500, 1500, 3000, 5000, 7500, 10500, 14000, 18000, 23000
    ];
    
    int currentLvl = currentLevel;
    
    if (currentLvl <= 1) return 0;
    if (currentLvl <= levels.length) {
      return levels[currentLvl - 2];
    }
    
    // Au-delà du niveau 10
    return 23000 + ((currentLvl - 11) * 6000);
  }

  double get xpProgress {
    int xpForLevel = xpForCurrentLevel();
    int xpNeeded = xpToNextLevel();
    int xpInLevel = totalXP - xpForLevel;
    int xpTotalForLevel = xpInLevel + xpNeeded;
    
    if (xpTotalForLevel == 0) return 1.0;
    return xpInLevel / xpTotalForLevel;
  }

  bool isBotTierUnlocked(String tier) {
    return unlockedBotTiers.contains(tier);
  }

  void checkAndUnlockBots() {
    int level = currentLevel;
    
    if (level >= 3 && !unlockedBotTiers.contains('intermediate')) {
      unlockedBotTiers.add('intermediate');
    }
    if (level >= 5 && !unlockedBotTiers.contains('expert')) {
      unlockedBotTiers.add('expert');
    }
    if (level >= 10 && !unlockedBotTiers.contains('master')) {
      unlockedBotTiers.add('master');
    }
  }

  void addXP(int xp) {
    totalXP += xp;
    checkAndUnlockBots();
  }

  void updateLastPlayed() {
    lastPlayed = DateTime.now();
  }

  String get formattedLastPlayed {
    Duration difference = DateTime.now().difference(lastPlayed);
    
    if (difference.inDays > 365) {
      return 'Il y a ${difference.inDays ~/ 365} an(s)';
    } else if (difference.inDays > 30) {
      return 'Il y a ${difference.inDays ~/ 30} mois';
    } else if (difference.inDays > 0) {
      return 'Il y a ${difference.inDays} jour(s)';
    } else if (difference.inHours > 0) {
      return 'Il y a ${difference.inHours} heure(s)';
    } else {
      return 'Aujourd\'hui';
    }
  }

  double get winRate {
    if (quickGamesPlayed == 0) return 0.0;
    return quickGamesWon / quickGamesPlayed;
  }

  SaveSlot copyWith({
    String? playerName,
    int? totalXP,
    int? tournamentsWon,
    int? finalistCount,
    int? semifinalistCount,
    int? quarterfinalistCount,
    int? tournamentsPlayed,
    int? quickGamesPlayed,
    int? quickGamesWon,
    int? bestScore,
    int? dutchSuccessCount,
    DateTime? lastPlayed,
    List<String>? unlockedBotTiers,
  }) {
    return SaveSlot(
      slotNumber: slotNumber,
      playerName: playerName ?? this.playerName,
      totalXP: totalXP ?? this.totalXP,
      tournamentsWon: tournamentsWon ?? this.tournamentsWon,
      finalistCount: finalistCount ?? this.finalistCount,
      semifinalistCount: semifinalistCount ?? this.semifinalistCount,
      quarterfinalistCount: quarterfinalistCount ?? this.quarterfinalistCount,
      tournamentsPlayed: tournamentsPlayed ?? this.tournamentsPlayed,
      quickGamesPlayed: quickGamesPlayed ?? this.quickGamesPlayed,
      quickGamesWon: quickGamesWon ?? this.quickGamesWon,
      bestScore: bestScore ?? this.bestScore,
      dutchSuccessCount: dutchSuccessCount ?? this.dutchSuccessCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      unlockedBotTiers: unlockedBotTiers ?? this.unlockedBotTiers,
    );
  }
}
