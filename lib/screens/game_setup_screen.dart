import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../services/stats_service.dart';
import 'memorization_screen.dart';

class GameSetupScreen extends StatefulWidget {
  final bool isTournament;
  final int saveSlot;

  const GameSetupScreen({
    super.key,
    required this.isTournament,
    required this.saveSlot,
  });

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  Difficulty selectedBotDifficulty = Difficulty.medium;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final bool useSBMM = settings.useSBMM;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.isTournament ? 'Configuration Tournoi' : 'Nouvelle Partie'),
        backgroundColor: const Color(0xFF1a3a28),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a3a28), Color(0xFF0d1f15)],
          ),
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.amber)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Niveau des Bots",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (useSBMM) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.amber),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.auto_awesome,
                                color: Colors.amber, size: 40),
                            SizedBox(height: 10),
                            Text("Mode Adaptatif Actif",
                                style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18)),
                            SizedBox(height: 5),
                            Text(
                                "Le niveau s'ajuste automatiquement à vos résultats.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ] else ...[
                      SegmentedButton<Difficulty>(
                        segments: const [
                          ButtonSegment(
                              value: Difficulty.easy,
                              label: Text("Facile"),
                              icon: Icon(Icons.sentiment_satisfied)),
                          ButtonSegment(
                              value: Difficulty.medium,
                              label: Text("Moyen"),
                              icon: Icon(Icons.sentiment_neutral)),
                          ButtonSegment(
                              value: Difficulty.hard,
                              label: Text("Difficile"),
                              icon: Icon(Icons.sentiment_very_dissatisfied)),
                        ],
                        selected: {selectedBotDifficulty},
                        onSelectionChanged: (Set<Difficulty> newSelection) {
                          setState(() {
                            selectedBotDifficulty = newSelection.first;
                          });
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                            if (states.contains(WidgetState.selected))
                              return Colors.amber;
                            return Colors.white10;
                          }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                            if (states.contains(WidgetState.selected))
                              return Colors.black;
                            return Colors.white;
                          }),
                        ),
                      ),
                    ],
                    const SizedBox(height: 50),
                    ElevatedButton(
                      onPressed: () => _startGame(context, useSBMM),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 50, vertical: 15),
                        textStyle: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: const Text("COMMENCER"),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _startGame(BuildContext context, bool useSBMM) async {
    setState(() => _isLoading = true);

    Difficulty botLevel;

    if (useSBMM) {
      botLevel =
          await StatsService.getRecommendedDifficulty(slotId: widget.saveSlot);
    } else {
      botLevel = selectedBotDifficulty;
    }

    List<Player> players = [
      Player(id: 'human', name: 'Vous', isHuman: true, position: 0)
    ];

    // ✅ NOUVEAU : Attribution des personnalités selon la difficulté
    List<BotPersonality> personalities = _getBotPersonalities(botLevel);

    for (int i = 0; i < 3; i++) {
      players.add(Player(
          id: 'bot_$i',
          name: _getBotName(personalities[i], i),
          isHuman: false,
          botPersonality: personalities[i],
          position: i + 1));
    }

    if (!mounted) return;

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    gameProvider.createNewGame(
      players: players,
      gameMode: widget.isTournament ? GameMode.tournament : GameMode.quick,
      difficulty: settings.luckDifficulty,
      reactionTimeMs: settings.reactionTimeMs,
      saveSlot: widget.saveSlot,
      useSBMM: useSBMM,
    );

    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (context) => const MemorizationScreen()));
  }

  /// 🎭 NOUVEAU : Obtenir les personnalités selon la difficulté
  List<BotPersonality> _getBotPersonalities(Difficulty level) {
    switch (level) {
      case Difficulty.easy:
        // Bronze : 1 Fast, 2 Équilibrés (comportement simple)
        return [
          BotPersonality.aggressive, // Fast
          BotPersonality.balanced,   // Équilibré
          BotPersonality.balanced,   // Équilibré
        ];

      case Difficulty.medium:
        // Argent : Mix équilibré (1 Fast, 1 Équilibré, 1 Réfléchi)
        return [
          BotPersonality.aggressive, // Fast
          BotPersonality.balanced,   // Équilibré
          BotPersonality.cautious,   // Réfléchi
        ];

      case Difficulty.hard:
        // Or : Équipe compétitive (1 Fast optimisé, 1 Équilibré, 1 Réfléchi)
        return [
          BotPersonality.aggressive, // Fast (très optimisé)
          BotPersonality.balanced,   // Équilibré adaptatif
          BotPersonality.cautious,   // Réfléchi (stratège)
        ];
    }
  }

  /// 🏷️ NOUVEAU : Noms des bots selon leur personnalité
  String _getBotName(BotPersonality personality, int index) {
    List<String> names;
    
    switch (personality) {
      case BotPersonality.aggressive: // 🏃 FAST
        names = ["Flash", "Speedy", "Bolt"];
        break;

      case BotPersonality.cautious: // 🧠 RÉFLÉCHI
        names = ["Sherlock", "Brain", "Prof"];
        break;

      case BotPersonality.balanced: // ⚖️ ÉQUILIBRÉ
        names = ["Jordan", "Casey", "Morgan"];
        break;

      // Anciens (ne devraient plus être utilisés mais on les garde)
      case BotPersonality.beginner:
        names = ["Noob", "Junior", "Bleu"];
        break;

      case BotPersonality.novice:
        names = ["Alex", "Sam", "Lou"];
        break;

      case BotPersonality.legend:
        names = ["Zeus", "Athena", "Thor"];
        break;

      default:
        names = ["Bot1", "Bot2", "Bot3"];
    }
    
    return names[index % names.length];
  }
}