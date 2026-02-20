import 'game_state.dart';

enum Difficulty { easy, medium, hard, platinum, mix }

enum BotBehavior { fast, aggressive, balanced, moi }

enum BotSkillLevel { bronze, silver, gold, platinum }

class GameSettings {
  GameMode gameMode;
  Difficulty luckDifficulty;
  Difficulty botDifficulty;
  int minPlayers;
  int maxPlayers;
  bool fillBots;

  int reactionTimeMs;
  int actionTextDisplayMs;
  bool useSBMM;
  String cardBackStyle;

  bool soundEnabled;
  bool hapticEnabled;
  bool animationsEnabled;
  bool cardRainEnabled;
  String playerName;

  bool isPublic;
  int numberOfPlayers;
  String? roomName;

  GameSettings({
    this.gameMode = GameMode.quick,
    this.luckDifficulty = Difficulty.medium,
    this.botDifficulty = Difficulty.medium,
    this.minPlayers = 2,
    this.maxPlayers = 6,
    this.fillBots = true,
    this.reactionTimeMs = 3000,
    this.actionTextDisplayMs = 1500,
    this.useSBMM = true,
    this.cardBackStyle = 'classic',
    this.soundEnabled = true,
    this.hapticEnabled = true,
    this.animationsEnabled = true,
    this.cardRainEnabled = true,
    this.playerName = "Vous",
    this.isPublic = false,
    this.numberOfPlayers = 4,
    this.roomName,
  });

  GameSettings copyWith({
    GameMode? gameMode,
    Difficulty? luckDifficulty,
    Difficulty? botDifficulty,
    int? minPlayers,
    int? maxPlayers,
    bool? fillBots,
    int? reactionTimeMs,
    int? actionTextDisplayMs,
    bool? useSBMM,
    String? cardBackStyle,
    bool? soundEnabled,
    bool? hapticEnabled,
    bool? animationsEnabled,
    bool? cardRainEnabled,
    String? playerName,
    bool? isPublic,
    int? numberOfPlayers,
    String? roomName,
  }) {
    return GameSettings(
      gameMode: gameMode ?? this.gameMode,
      luckDifficulty: luckDifficulty ?? this.luckDifficulty,
      botDifficulty: botDifficulty ?? this.botDifficulty,
      minPlayers: minPlayers ?? this.minPlayers,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      fillBots: fillBots ?? this.fillBots,
      reactionTimeMs: reactionTimeMs ?? this.reactionTimeMs,
      actionTextDisplayMs: actionTextDisplayMs ?? this.actionTextDisplayMs,
      useSBMM: useSBMM ?? this.useSBMM,
      cardBackStyle: cardBackStyle ?? this.cardBackStyle,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      cardRainEnabled: cardRainEnabled ?? this.cardRainEnabled,
      playerName: playerName ?? this.playerName,
      isPublic: isPublic ?? this.isPublic,
      numberOfPlayers: numberOfPlayers ?? this.numberOfPlayers,
      roomName: roomName ?? this.roomName,
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
      actionTextDisplayMs: json['actionTextDisplayMs'] ?? 1500,
      useSBMM: json['useSBMM'] ?? true,
      cardBackStyle: json['cardBackStyle'] ?? 'classic',
      soundEnabled: json['soundEnabled'] ?? true,
      hapticEnabled: json['hapticEnabled'] ?? true,
      animationsEnabled: json['animationsEnabled'] ?? true,
      cardRainEnabled: json['cardRainEnabled'] ?? true,
      playerName: json['playerName'] ?? "Vous",
      isPublic: json['isPublic'] ?? false,
      numberOfPlayers: json['numberOfPlayers'] ?? 4,
      roomName: json['roomName'],
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
      'actionTextDisplayMs': actionTextDisplayMs,
      'useSBMM': useSBMM,
      'cardBackStyle': cardBackStyle,
      'soundEnabled': soundEnabled,
      'hapticEnabled': hapticEnabled,
      'animationsEnabled': animationsEnabled,
      'cardRainEnabled': cardRainEnabled,
      'playerName': playerName,
      'isPublic': isPublic,
      'numberOfPlayers': numberOfPlayers,
      if (roomName != null) 'roomName': roomName,
    };
  }
}
