// Enum pour la difficulté (Chance/Mélange)
enum Difficulty { 
  easy, 
  medium, 
  hard 
}

// Enum pour la personnalité des bots
enum BotPersonality { 
  beginner, 
  novice, 
  balanced, 
  cautious, 
  aggressive, 
  legend 
}

class GameSettings {
  // Difficulté liée à la chance (Mélange)
  Difficulty luckDifficulty;
  
  // Difficulté par défaut des bots (Sauvegardée dans les réglages)
  Difficulty botDifficulty; 
  
  int reactionTimeMs;
  bool useSBMM;
  String cardBackStyle;
  
  bool soundEnabled;
  bool hapticEnabled;
  String playerName;

  GameSettings({
    this.luckDifficulty = Difficulty.medium,
    this.botDifficulty = Difficulty.medium, // ✅ RESTAURÉ
    this.reactionTimeMs = 3000,
    this.useSBMM = true,
    this.cardBackStyle = 'classic',
    this.soundEnabled = true,
    this.hapticEnabled = true,
    this.playerName = "Vous",
  });

  // ✅ RESTAURÉ : Indispensable pour SettingsProvider
  GameSettings copyWith({
    Difficulty? luckDifficulty,
    Difficulty? botDifficulty,
    int? reactionTimeMs,
    bool? useSBMM,
    String? cardBackStyle,
    bool? soundEnabled,
    bool? hapticEnabled,
    String? playerName,
  }) {
    return GameSettings(
      luckDifficulty: luckDifficulty ?? this.luckDifficulty,
      botDifficulty: botDifficulty ?? this.botDifficulty,
      reactionTimeMs: reactionTimeMs ?? this.reactionTimeMs,
      useSBMM: useSBMM ?? this.useSBMM,
      cardBackStyle: cardBackStyle ?? this.cardBackStyle,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      playerName: playerName ?? this.playerName,
    );
  }

  // ✅ RESTAURÉ : Indispensable pour le chargement JSON
  factory GameSettings.fromJson(Map<String, dynamic> json) {
    return GameSettings(
      luckDifficulty: Difficulty.values[json['luckDifficulty'] ?? 1],
      botDifficulty: Difficulty.values[json['botDifficulty'] ?? 1],
      reactionTimeMs: json['reactionTimeMs'] ?? 3000,
      useSBMM: json['useSBMM'] ?? true,
      cardBackStyle: json['cardBackStyle'] ?? 'classic',
      soundEnabled: json['soundEnabled'] ?? true,
      hapticEnabled: json['hapticEnabled'] ?? true,
      playerName: json['playerName'] ?? "Vous",
    );
  }

  // ✅ RESTAURÉ : Indispensable pour la sauvegarde JSON
  Map<String, dynamic> toJson() {
    return {
      'luckDifficulty': luckDifficulty.index,
      'botDifficulty': botDifficulty.index,
      'reactionTimeMs': reactionTimeMs,
      'useSBMM': useSBMM,
      'cardBackStyle': cardBackStyle,
      'soundEnabled': soundEnabled,
      'hapticEnabled': hapticEnabled,
      'playerName': playerName,
    };
  }
}