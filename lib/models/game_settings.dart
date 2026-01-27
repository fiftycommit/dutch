import 'game_state.dart';

enum Difficulty { easy, medium, hard }

enum BotBehavior { 
  fast,
  aggressive,
  balanced
}

enum BotSkillLevel {
  bronze,
  silver,
  gold
}

class GameSettings {
  GameMode gameMode;
  Difficulty luckDifficulty;
  Difficulty botDifficulty;
  int minPlayers;
  int maxPlayers;
  bool fillBots;

  int reactionTimeMs;
  bool useSBMM;
  String cardBackStyle;

  bool soundEnabled;
  bool hapticEnabled;
  String playerName;

  GameSettings({
    this.gameMode = GameMode.quick,
    this.luckDifficulty = Difficulty.medium,
    this.botDifficulty = Difficulty.medium,
    this.minPlayers = 2,
    this.maxPlayers = 4,
    this.fillBots = true,
    this.reactionTimeMs = 3000,
    this.useSBMM = true,
    this.cardBackStyle = 'classic',
    this.soundEnabled = true,
    this.hapticEnabled = true,
    this.playerName = "Vous",
  });

  GameSettings copyWith({
    GameMode? gameMode,
    Difficulty? luckDifficulty,
    Difficulty? botDifficulty,
    int? minPlayers,
    int? maxPlayers,
    bool? fillBots,
    int? reactionTimeMs,
    bool? useSBMM,
    String? cardBackStyle,
    bool? soundEnabled,
    bool? hapticEnabled,
    String? playerName,
  }) {
    return GameSettings(
      gameMode: gameMode ?? this.gameMode,
      luckDifficulty: luckDifficulty ?? this.luckDifficulty,
      botDifficulty: botDifficulty ?? this.botDifficulty,
      minPlayers: minPlayers ?? this.minPlayers,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      fillBots: fillBots ?? this.fillBots,
      reactionTimeMs: reactionTimeMs ?? this.reactionTimeMs,
      useSBMM: useSBMM ?? this.useSBMM,
      cardBackStyle: cardBackStyle ?? this.cardBackStyle,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      playerName: playerName ?? this.playerName,
    );
  }

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    return GameSettings(
      gameMode: GameMode.values[json['gameMode'] ?? 0],
      luckDifficulty: Difficulty.values[json['luckDifficulty'] ?? 1],
      botDifficulty: Difficulty.values[json['botDifficulty'] ?? 1],
      minPlayers: json['minPlayers'] ?? 2,
      maxPlayers: json['maxPlayers'] ?? 4,
      fillBots: json['fillBots'] ?? true,
      reactionTimeMs: json['reactionTimeMs'] ?? 3000,
      useSBMM: json['useSBMM'] ?? true,
      cardBackStyle: json['cardBackStyle'] ?? 'classic',
      soundEnabled: json['soundEnabled'] ?? true,
      hapticEnabled: json['hapticEnabled'] ?? true,
      playerName: json['playerName'] ?? "Vous",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gameMode': gameMode.index,
      'luckDifficulty': luckDifficulty.index,
      'botDifficulty': botDifficulty.index,
      'minPlayers': minPlayers,
      'maxPlayers': maxPlayers,
      'fillBots': fillBots,
      'reactionTimeMs': reactionTimeMs,
      'useSBMM': useSBMM,
      'cardBackStyle': cardBackStyle,
      'soundEnabled': soundEnabled,
      'hapticEnabled': hapticEnabled,
      'playerName': playerName,
    };
  }
}
