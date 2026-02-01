import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/player.dart';
import '../../models/game_state.dart';
import '../../models/game_settings.dart';
import '../../providers/game_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/learning/player_learning_service.dart';
import '../../services/learning/bot_training_service.dart';
import '../../services/learning/ghost_clone_service.dart';
import '../../services/game/bot/bot_config.dart';
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
          onPressed: () => context.go('/'),
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

    final int numberOfBots = selectedNumberOfPlayers - 1;

    List<Player> players = [
      Player(id: 'human', name: 'Vous', isHuman: true, position: 0)
    ];

    if (useSBMM) {
      // === NOUVEAU SYSTÈME DE MATCHMAKING ===
      // Utilise le MMR du joueur pour calibrer les bots
      // Le rang (Bronze/Argent/Or/Platine) est purement cosmétique
      players.addAll(await _createSBMMBots(numberOfBots));
    } else {
      // Mode manuel : difficulté fixe choisie par l'utilisateur
      players.addAll(_createManualBots(numberOfBots));
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

  /// Crée les bots en mode SBMM (matchmaking adaptatif basé sur le MMR)
  Future<List<Player>> _createSBMMBots(int numberOfBots) async {
    final botTrainingService = BotTrainingService();
    final ghostCloneService = GhostCloneService();

    // Récupérer le profil joueur (une seule fois)
    final profile = await PlayerLearningService().getProfile(slotId: widget.saveSlot);

    // Infos pour le ghost clone
    final prefs = await SharedPreferences.getInstance();
    final ghostPlayerId = prefs.getString('multiplayer_client_id') ?? 'slot_${widget.saveSlot}';
    final ghostPlayerName = profile.profileId;

    // Générer les paramètres des bots via le nouveau MatchmakingService
    // Ceci prend en compte : MMR, progression vers le palier, distribution auto
    final botParamsList = BotConfig.generateMatchmakingBotParams(
      playerProfile: profile,
      botCount: numberOfBots,
      forceChallenge: widget.isTournament,
    );

    // Déterminer les comportements variés pour chaque bot
    final behaviors = _generateBotBehaviors(numberOfBots, profile.learnedParameters);

    // Ghost profile (chargé une seule fois si nécessaire)
    GhostProfile? ghostProfile;

    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final behavior = behaviors[i];
      final baseParams = botParamsList[i];

      // Récupérer le training state pour ce type de bot
      final botKey = BotTrainingService.buildBotKey(
        behavior: behavior,
        skillLevel: _mmrToSkillLevel(profile.mmr),
      );
      final trainingState = await botTrainingService.getStateForBot(
        botKey,
        consumeTrainingGame: true,
      );

      // Charger le ghost profile si nécessaire (une seule fois)
      if (trainingState.ghostInfluence > 0 && ghostProfile == null) {
        ghostProfile = await ghostCloneService.getGhostProfile(
          slotId: widget.saveSlot,
          playerId: ghostPlayerId,
          playerName: ghostPlayerName,
        );
      }

      // Appliquer le ghost blending sur les paramètres de base
      final aiParameters = _applyGhostBlending(
        baseParams: baseParams,
        ghostProfile: ghostProfile,
        trainingState: trainingState,
      );

      players.add(Player(
        id: 'bot_$i',
        name: _getBotName(behavior, _mmrToSkillLevel(profile.mmr)),
        isHuman: false,
        botBehavior: behavior,
        botSkillLevel: _mmrToSkillLevel(profile.mmr),
        aiParameters: aiParameters,
        position: i + 1,
      ));
    }

    return players;
  }

  /// Crée les bots en mode manuel (difficulté choisie par l'utilisateur)
  List<Player> _createManualBots(int numberOfBots) {
    final skillLevel = _difficultyToSkillLevel(selectedBotDifficulty);
    final isMixMode = selectedBotDifficulty == Difficulty.mix;
    final mixSkillLevels = [BotSkillLevel.bronze, BotSkillLevel.silver, BotSkillLevel.gold];
    final botBehaviors = [BotBehavior.fast, BotBehavior.aggressive, BotBehavior.balanced];

    final random = DateTime.now().millisecondsSinceEpoch;
    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final behaviorIndex = (i + (random >> i)) % botBehaviors.length;
      final behavior = botBehaviors[behaviorIndex];

      final botSkill = isMixMode
          ? mixSkillLevels[(i + (random >> (i + 3))) % mixSkillLevels.length]
          : skillLevel;

      players.add(Player(
        id: 'bot_$i',
        name: _getBotName(behavior, botSkill),
        isHuman: false,
        botBehavior: behavior,
        botSkillLevel: botSkill,
        position: i + 1,
      ));
    }

    return players;
  }

  /// Génère des comportements variés pour les bots basés sur le style du joueur
  List<BotBehavior> _generateBotBehaviors(int count, Map<String, dynamic> playerParams) {
    double numParam(String key, double fallback) {
      final v = playerParams[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    final aggressiveness = numParam('aggressiveness', 0.5);
    final caution = numParam('caution', 0.5);
    final riskTolerance = numParam('riskTolerance', 0.5);

    // Déterminer le style dominant du joueur
    BotBehavior primaryBehavior;
    if (aggressiveness >= 0.65 || riskTolerance >= 0.65) {
      primaryBehavior = BotBehavior.aggressive;
    } else if (caution >= 0.65 && riskTolerance <= 0.45) {
      primaryBehavior = BotBehavior.fast;
    } else {
      primaryBehavior = BotBehavior.balanced;
    }

    // Créer une distribution variée autour du style du joueur
    final behaviors = <BotBehavior>[];
    final allBehaviors = [BotBehavior.fast, BotBehavior.aggressive, BotBehavior.balanced];

    for (int i = 0; i < count; i++) {
      if (i == 0) {
        // Premier bot : même style que le joueur
        behaviors.add(primaryBehavior);
      } else {
        // Autres bots : varier les styles
        behaviors.add(allBehaviors[i % allBehaviors.length]);
      }
    }

    return behaviors;
  }

  /// Applique le ghost blending sur les paramètres de base
  Map<String, double> _applyGhostBlending({
    required Map<String, double> baseParams,
    GhostProfile? ghostProfile,
    required BotTrainingState trainingState,
  }) {
    final ghostParams = ghostProfile?.params ?? const <String, double>{};
    final ghostInfluence = trainingState.ghostInfluence;

    double blend(String key, double baseValue) {
      final ghostValue = ghostParams[key];
      if (ghostValue == null || ghostInfluence <= 0) return baseValue;
      return baseValue + (ghostValue - baseValue) * ghostInfluence;
    }

    // Copier les paramètres de base et appliquer le blending
    final result = Map<String, double>.from(baseParams);

    // Appliquer le ghost blending sur les paramètres clés
    result['aggressiveness'] = blend('aggressiveness', result['aggressiveness'] ?? 0.5);
    result['caution'] = blend('caution', result['caution'] ?? 0.5);
    result['riskTolerance'] = blend('riskTolerance', result['riskTolerance'] ?? 0.5);
    result['powerUsageRate'] = blend('powerUsageRate', result['powerUsageRate'] ?? 0.5);
    result['decisionSpeed'] = blend('decisionSpeed', result['decisionSpeed'] ?? 2000.0).clamp(500.0, 10000.0);
    result['dutchThreshold'] = blend('dutchThreshold', result['dutchThreshold'] ?? 15.0).clamp(5.0, 30.0);

    // Ajouter les paramètres de training
    result['ghostInfluence'] = ghostInfluence;
    result['ghostDutchThreshold'] = ghostParams['dutchThreshold'] ?? result['dutchThreshold']!;
    result['rankPenalty'] = trainingState.rankPenalty;

    return result;
  }

  /// Convertit un MMR en BotSkillLevel (pour affichage/nom uniquement)
  BotSkillLevel _mmrToSkillLevel(int mmr) {
    if (mmr >= 900) return BotSkillLevel.platinum;
    if (mmr >= 600) return BotSkillLevel.gold;
    if (mmr >= 300) return BotSkillLevel.silver;
    return BotSkillLevel.bronze;
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
    'Max', 'Yanis', 'Rohi', 'Millie', 'Kellinho', 'Kifa', 'Zoe', 'VR6',
    'Ruben', 'Lisa', 'Clara', 'Frizou', 'Tony', 'Leon', 'Elodie', '2T',
    'Guy2', 'Poppa', 'Messboal', 'Bersa', 'Juwa', 'Manboy', 'Bramsou', 'Lil Uzi'
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
