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
  int selectedNumberOfPlayers = 4; // Par défaut 4 joueurs

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final bool useSBMM = settings.useSBMM;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                        child: const Column(
                          children: [
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
                          ButtonSegment(
                              value: Difficulty.mix,
                              label: Text("Mix"),
                              icon: Icon(Icons.shuffle)),
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
                            if (states.contains(WidgetState.selected)) {
                              return Colors.amber;
                            }
                            return Colors.white10;
                          }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.black;
                            }
                            return Colors.white;
                          }),
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    const Text(
                      "Nombre de joueurs",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<int>(
                      segments: widget.isTournament 
                        ? const [
                            ButtonSegment(value: 4, label: Text("4")),
                            ButtonSegment(value: 6, label: Text("6")),
                          ]
                        : const [
                            ButtonSegment(value: 2, label: Text("2")),
                            ButtonSegment(value: 3, label: Text("3")),
                            ButtonSegment(value: 4, label: Text("4")),
                            ButtonSegment(value: 5, label: Text("5")),
                            ButtonSegment(value: 6, label: Text("6")),
                          ],
                      selected: {selectedNumberOfPlayers},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          selectedNumberOfPlayers = newSelection.first;
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.green;
                          }
                          return Colors.white10;
                        }),
                        foregroundColor:
                            WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.white70;
                        }),
                      ),
                    ),
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

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final navigator = Navigator.of(context);

    BotSkillLevel skillLevel;
    if (useSBMM) {
      Difficulty recommendedDifficulty = await StatsService.getRecommendedDifficulty(slotId: widget.saveSlot);
      skillLevel = _difficultyToSkillLevel(recommendedDifficulty);
    } else {
      skillLevel = _difficultyToSkillLevel(selectedBotDifficulty);
    }

    List<Player> players = [
      Player(id: 'human', name: 'Vous', isHuman: true, position: 0)
    ];

    // Nombre de bots à créer (nombre de joueurs - 1 pour le joueur humain)
    final int numberOfBots = selectedNumberOfPlayers - 1;
    
    // Comportements des bots (on cycle à travers eux)
    final botBehaviors = [BotBehavior.fast, BotBehavior.aggressive, BotBehavior.balanced];
    
    // Si mode mix, créer un mélange de difficultés
    final bool isMixMode = selectedBotDifficulty == Difficulty.mix;
    final mixSkillLevels = [BotSkillLevel.bronze, BotSkillLevel.silver, BotSkillLevel.gold];
    
    // Mélanger les comportements et niveaux pour plus de variété
    final random = DateTime.now().millisecondsSinceEpoch;
    final shuffledBehaviors = List<BotBehavior>.from(botBehaviors);
    final shuffledSkills = List<BotSkillLevel>.from(mixSkillLevels);
    
    for (int i = 0; i < numberOfBots; i++) {
      // Ajouter un peu d'aléatoire dans le choix du comportement
      final behaviorIndex = (i + (random >> i)) % botBehaviors.length;
      final behavior = shuffledBehaviors[behaviorIndex];
      
      // En mode mix, varier les niveaux de manière plus aléatoire
      final botSkill = isMixMode 
          ? shuffledSkills[(i + (random >> (i + 3))) % mixSkillLevels.length]
          : skillLevel;
      
      players.add(Player(
        id: 'bot_$i',
        name: _getBotName(behavior, botSkill),
        isHuman: false,
        botBehavior: behavior,
        botSkillLevel: botSkill,
        position: i + 1
      ));
    }

    if (!mounted) return;

    gameProvider.createNewGame(
      players: players,
      gameMode: widget.isTournament ? GameMode.tournament : GameMode.quick,
      difficulty: settings.luckDifficulty,
      reactionTimeMs: settings.reactionTimeMs,
      saveSlot: widget.saveSlot,
      useSBMM: useSBMM,
    );

    if (!mounted) return;
    navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const MemorizationScreen()));
  }


  BotSkillLevel _difficultyToSkillLevel(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:
        return BotSkillLevel.bronze;
      case Difficulty.medium:
        return BotSkillLevel.silver;
      case Difficulty.hard:
        return BotSkillLevel.gold;
      case Difficulty.mix:
        return BotSkillLevel.silver; // Valeur par défaut, sera mélangé lors de la création
    }
  }


  // Liste de prénoms pour les bots
  static final List<String> _botNames = [
    'Alice', 'Bob', 'Charlie', 'Diana', 'Emma', 'Felix',
    'Grace', 'Hugo', 'Iris', 'Jack', 'Luna', 'Max',
    'Nina', 'Oscar', 'Paul', 'Rose', 'Sam', 'Tom',
    'Victor', 'Zoe', 'Arthur', 'Clara', 'David', 'Eva'
  ];
  
  static final Set<String> _usedNames = {};

  String _getBotName(BotBehavior behavior, BotSkillLevel level) {
    // Réinitialiser les noms utilisés si on a tout utilisé
    if (_usedNames.length >= _botNames.length) {
      _usedNames.clear();
    }
    
    // Trouver un nom non utilisé
    String name;
    do {
      final randomIndex = DateTime.now().millisecondsSinceEpoch % _botNames.length;
      name = _botNames[randomIndex];
    } while (_usedNames.contains(name));
    
    _usedNames.add(name);
    return name;
  }
}
