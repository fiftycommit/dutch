import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/bot_learning_data.dart';
import '../../models/player.dart';
import '../../models/game_state.dart';
import '../../models/game_settings.dart';
import '../../providers/game_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/learning/player_learning_service.dart';
import '../../services/learning/bot_learning_service.dart';
import '../../services/learning/bot_training_service.dart';
import '../../services/learning/ghost_clone_service.dart';
import '../../services/game/bot/bot_config.dart';
import '../../services/multiplayer/client_id_service.dart';

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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/'),
        ),
        title: Text(
            widget.isTournament ? 'Configuration Tournoi' : 'Nouvelle Partie',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1a3a28),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a3a28), Color(0xFF0d1f15)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              );
            }

            final scale = (constraints.maxHeight / 680).clamp(0.55, 1.0);
            final isCompact = scale < 0.85;
            double f(double size) => size * scale;

            final spacingSmall = f(20);
            final spacingMedium = f(30);
            final spacingLarge = f(50);
            final buttonPadding = EdgeInsets.symmetric(
              horizontal: f(50),
              vertical: f(15),
            );
            
            // Couleurs pour les segments
            const unselectedBg = Color(0xFF2D4F3C);
            const selectedBotBg = Colors.amber;
            const selectedPlayerBg = Colors.green;
            const segmentBorder = Color(0xFF4A7A5C);
            
            final botSegmentStyle = ButtonStyle(
              visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
              tapTargetSize:
                  isCompact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: f(12), vertical: f(6)),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: f(13), fontWeight: FontWeight.w600),
              ),
              backgroundColor:
                  WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedBotBg;
                }
                return unselectedBg;
              }),
              foregroundColor:
                  WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return Colors.white;
              }),
              iconColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return Colors.white;
              }),
              side: WidgetStateProperty.all(
                const BorderSide(color: segmentBorder, width: 1),
              ),
              // Overlay transparent pour éviter effet de hover gris
              overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withValues(alpha: 0.1);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.05);
                }
                return Colors.transparent;
              }),
            );
            final playerSegmentStyle = ButtonStyle(
              visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
              tapTargetSize:
                  isCompact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: f(12), vertical: f(6)),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: f(13), fontWeight: FontWeight.w600),
              ),
              backgroundColor:
                  WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedPlayerBg;
                }
                return unselectedBg;
              }),
              foregroundColor:
                  WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.white;
              }),
              iconColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.white;
              }),
              side: WidgetStateProperty.all(
                const BorderSide(color: segmentBorder, width: 1),
              ),
              // Overlay transparent pour éviter effet de hover gris
              overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withValues(alpha: 0.1);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.05);
                }
                return Colors.transparent;
              }),
            );
            final content = Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Niveau des Bots",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: f(20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: spacingSmall),
                if (useSBMM) ...[
                  Container(
                    padding: EdgeInsets.all(f(20)),
                    margin: EdgeInsets.symmetric(
                      horizontal: f(40),
                    ),
                    decoration: BoxDecoration(
                      // Fond plus opaque pour meilleur contraste
                      color: const Color(0xFF2a4a38),
                      border: Border.all(color: Colors.amber, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Colors.amber,
                          size: f(40),
                        ),
                        SizedBox(height: f(10)),
                        Text(
                          "Mode Adaptatif Actif",
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: f(18),
                          ),
                        ),
                        SizedBox(height: f(5)),
                        Text(
                          "Le niveau s'ajuste automatiquement à vos résultats.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            // Blanc pur pour lisibilité maximale
                            color: Colors.white,
                            fontSize: f(13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Theme(
                    data: Theme.of(context).copyWith(
                      segmentedButtonTheme: SegmentedButtonThemeData(
                        style: botSegmentStyle,
                      ),
                    ),
                    child: SegmentedButton<Difficulty>(
                      segments: [
                        ButtonSegment(
                          value: Difficulty.easy,
                          label: const Text("Facile"),
                          icon: Icon(Icons.sentiment_satisfied, size: f(18)),
                        ),
                        ButtonSegment(
                          value: Difficulty.medium,
                          label: const Text("Moyen"),
                          icon: Icon(Icons.sentiment_neutral, size: f(18)),
                        ),
                        ButtonSegment(
                          value: Difficulty.hard,
                          label: const Text("Difficile"),
                          icon:
                              Icon(Icons.sentiment_very_dissatisfied, size: f(18)),
                        ),
                        ButtonSegment(
                          value: Difficulty.platinum,
                          label: const Text("Platine"),
                          icon: Icon(Icons.diamond, size: f(18)),
                        ),
                        ButtonSegment(
                          value: Difficulty.mix,
                          label: const Text("Mix"),
                          icon: Icon(Icons.shuffle, size: f(18)),
                        ),
                      ],
                      selected: {selectedBotDifficulty},
                      onSelectionChanged: (Set<Difficulty> newSelection) {
                        setState(() {
                          selectedBotDifficulty = newSelection.first;
                        });
                      },
                      style: botSegmentStyle,
                    ),
                  ),
                ],
                SizedBox(height: spacingSmall),
                // Description du niveau sélectionné (mode manuel uniquement)
                if (!useSBMM && (selectedBotDifficulty == Difficulty.hard || selectedBotDifficulty == Difficulty.platinum)) ...[
                  _buildDifficultyDescription(f, selectedBotDifficulty),
                ],
                SizedBox(height: spacingMedium),
                Text(
                  "Nombre de joueurs",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: f(20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: spacingSmall),
                Theme(
                  data: Theme.of(context).copyWith(
                    segmentedButtonTheme: SegmentedButtonThemeData(
                      style: playerSegmentStyle,
                    ),
                  ),
                  child: SegmentedButton<int>(
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
                    style: playerSegmentStyle,
                  ),
                ),
                SizedBox(height: spacingLarge),
                ElevatedButton(
                  onPressed: () => _startGame(context, useSBMM),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: buttonPadding,
                    textStyle: TextStyle(
                      fontSize: f(18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text("COMMENCER"),
                ),
              ],
            );

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  void _startGame(BuildContext context, bool useSBMM) async {
    setState(() => _isLoading = true);

    try {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final int numberOfBots = selectedNumberOfPlayers - 1;

      List<Player> players = [
        Player(id: 'human', name: 'Vous', isHuman: true, position: 0)
      ];

      if (useSBMM) {
        players.addAll(await _createSBMMBots(numberOfBots)
            .timeout(const Duration(seconds: 8)));
      } else {
        players.addAll(await _createManualBots(numberOfBots)
            .timeout(const Duration(seconds: 8)));
      }

      if (!mounted) return;

      // Déterminer le hardcoreLevel basé sur la difficulté sélectionnée
      HardcoreLevel? hardcoreLevel;
      if (selectedBotDifficulty == Difficulty.hard) {
        hardcoreLevel = HardcoreLevel.nightmare;
      } else if (selectedBotDifficulty == Difficulty.platinum) {
        hardcoreLevel = HardcoreLevel.impossible;
      }

      await gameProvider.createNewGame(
        players: players,
        gameMode: widget.isTournament ? GameMode.tournament : GameMode.quick,
        difficulty: settings.luckDifficulty,
        reactionTimeMs: settings.reactionTimeMs,
        saveSlot: widget.saveSlot,
        useSBMM: useSBMM,
        hardcoreLevel: hardcoreLevel,
      );

      if (!mounted) return;
      context.go('/solo/memorization');
    } catch (e) {
      debugPrint('❌ Erreur démarrage partie: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur de connexion. Réessayez.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Crée les bots en mode SBMM (vrai matchmaking adaptatif)
  ///
  /// Les bots sont des "miroirs" du joueur : mêmes paramètres avec petite
  /// variance aléatoire. Pas de seuils MMR, pas de multiplicateur de skill.
  Future<List<Player>> _createSBMMBots(int numberOfBots) async {
    final botTrainingService = BotTrainingService();
    final ghostCloneService = GhostCloneService();

    // Récupérer le profil joueur (une seule fois)
    final profile = await PlayerLearningService().getProfile(slotId: widget.saveSlot);

    // Infos pour le ghost clone
    final ghostPlayerId = await ClientIdService.ensureClientId();
    final ghostPlayerName = profile.profileId;

    // Vrai SBMM : copier les params du joueur avec petite variance par bot
    final botParamsList = BotConfig.generateMatchmakingBotParams(
      playerProfile: profile,
      botCount: numberOfBots,
      forceChallenge: widget.isTournament,
    );

    // Ghost profile (chargé une seule fois si nécessaire)
    GhostProfile? ghostProfile;

    final players = <Player>[];
    final skillLevel = _mmrToSkillLevel(profile.mmr);

    for (int i = 0; i < numberOfBots; i++) {
      final baseParams = botParamsList[i];

      // Récupérer le training state pour ce type de bot
      final botKey = BotTrainingService.buildBotKey(
        behavior: BotBehavior.balanced,
        skillLevel: skillLevel,
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
        name: _getBotName(BotBehavior.balanced, skillLevel),
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: skillLevel,
        aiParameters: aiParameters,
        position: i + 1,
      ));
    }

    return players;
  }

  /// Crée les bots en mode manuel (difficulté choisie par l'utilisateur)
  /// Bronze/Silver/Gold : sélection par winrate moyen cible
  /// Platinum : meilleurs bots absolus de la catégorie
  Future<List<Player>> _createManualBots(int numberOfBots) async {
    if (numberOfBots <= 0) return [];

    // Platinum : logique élite (meilleurs absolus)
    if (selectedBotDifficulty == Difficulty.platinum) {
      return _createEliteBots(numberOfBots);
    }

    // Mix : logique spéciale (mélange de niveaux)
    if (selectedBotDifficulty == Difficulty.mix) {
      return _createMixBots(numberOfBots);
    }

    // Bronze / Silver / Gold : sélection par tranche de winrate
    return _createWinrateBots(numberOfBots);
  }

  /// Winrate minimum par difficulté (pas de max, on prend les plus proches du min)
  double _winrateMin() {
    switch (selectedBotDifficulty) {
      case Difficulty.easy:   return 0.0;  // Bronze : tous les bots, triés du plus faible
      case Difficulty.medium: return 0.50; // Argent : minimum 50%
      case Difficulty.hard:   return 0.70; // Or : minimum 70%
      default:                return 0.0;
    }
  }

  /// Sélectionne les bots dont le winrate moyen tombe dans la tranche cible
  Future<List<Player>> _createWinrateBots(int numberOfBots) async {
    final botLearningService = BotLearningService();
    final allBots = await botLearningService.fetchTopBots(limit: 50);
    final targetSkill = _difficultyToSkillLevel(selectedBotDifficulty);

    double avgWinrate(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;
    final minWr = _winrateMin();
    final isBronze = selectedBotDifficulty == Difficulty.easy;

    // Filtrer par winrate minimum strict
    var candidates = allBots.where((b) => avgWinrate(b) >= minWr).toList();

    // Bronze : trier du plus faible au plus fort (on veut les plus nuls)
    // Argent/Or : trier du plus fort au plus faible (on veut les meilleurs au-dessus du min)
    if (isBronze) {
      candidates.sort((a, b) => avgWinrate(a).compareTo(avgWinrate(b)));
    } else {
      candidates.sort((a, b) => avgWinrate(b).compareTo(avgWinrate(a)));
    }

    debugPrint('🎯 Min winrate: ${(minWr * 100).toStringAsFixed(0)}% → ${candidates.length} bots trouvés');
    for (final bot in candidates) {
      debugPrint('  🤖 ${bot.botId} | WR: ${(avgWinrate(bot) * 100).toStringAsFixed(0)}%');
    }

    final isGold = selectedBotDifficulty == Difficulty.hard;
    final players = <Player>[];

    if (isGold) {
      // Or : 2/3 #1 + 1/3 #2 (duplication des meilleurs)
      final bestBot = candidates.isNotEmpty ? candidates.first : null;
      final secondBot = candidates.length >= 2 ? candidates[1] : bestBot;

      if (bestBot != null) {
        debugPrint('⭐ #1: ${bestBot.botId} | WR: ${(avgWinrate(bestBot) * 100).toStringAsFixed(0)}%');
      }
      if (secondBot != null && secondBot != bestBot) {
        debugPrint('⭐ #2: ${secondBot.botId} | WR: ${(avgWinrate(secondBot) * 100).toStringAsFixed(0)}%');
      }

      final secondBotCount = (numberOfBots / 3).ceil();
      final firstBotCount = numberOfBots - secondBotCount;

      for (int i = 0; i < numberOfBots; i++) {
        final source = i < firstBotCount ? bestBot : secondBot;
        if (source != null) {
          final behavior = _parseBehavior(source.behavior);
          final aiParams = _extractAiParams(source.learnedParameters);
          aiParams['serverMMR'] = source.mmr.toDouble();
          aiParams['serverWinRateVsHuman'] = source.avgPBeatHuman;

          players.add(Player(
            id: 'bot_$i',
            name: _getBotName(behavior, targetSkill),
            isHuman: false,
            botBehavior: behavior,
            botSkillLevel: targetSkill,
            aiParameters: aiParams.isNotEmpty ? aiParams : null,
            position: i + 1,
          ));
        } else {
          players.add(Player(
            id: 'bot_$i',
            name: _getBotName(BotBehavior.balanced, targetSkill),
            isHuman: false,
            botBehavior: BotBehavior.balanced,
            botSkillLevel: targetSkill,
            position: i + 1,
          ));
        }
      }
    } else {
      // Bronze / Argent : bots tous différents
      for (int i = 0; i < numberOfBots; i++) {
        final source = i < candidates.length ? candidates[i] : null;
        if (source != null) {
          debugPrint('⭐ Bot $i: ${source.botId} | WR: ${(avgWinrate(source) * 100).toStringAsFixed(0)}%');
          final behavior = _parseBehavior(source.behavior);
          final aiParams = _extractAiParams(source.learnedParameters);
          aiParams['serverMMR'] = source.mmr.toDouble();
          aiParams['serverWinRateVsHuman'] = source.avgPBeatHuman;

          players.add(Player(
            id: 'bot_$i',
            name: _getBotName(behavior, targetSkill),
            isHuman: false,
            botBehavior: behavior,
            botSkillLevel: targetSkill,
            aiParameters: aiParams.isNotEmpty ? aiParams : null,
            position: i + 1,
          ));
        } else {
          players.add(Player(
            id: 'bot_$i',
            name: _getBotName(BotBehavior.balanced, targetSkill),
            isHuman: false,
            botBehavior: BotBehavior.balanced,
            botSkillLevel: targetSkill,
            position: i + 1,
          ));
        }
      }
    }

    return players;
  }

  /// Mode Mix : un bot de chaque tranche de winrate
  Future<List<Player>> _createMixBots(int numberOfBots) async {
    final botLearningService = BotLearningService();
    final allBots = await botLearningService.fetchTopBots(limit: 50);

    double avgWinrate(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final mixTargets = [0.25, 0.50, 0.75];
    final mixSkills = [BotSkillLevel.bronze, BotSkillLevel.silver, BotSkillLevel.gold];
    final players = <Player>[];

    for (int i = 0; i < numberOfBots; i++) {
      final target = mixTargets[i % mixTargets.length];
      final skill = mixSkills[i % mixSkills.length];

      // Trouver le bot le plus proche du winrate cible
      final sorted = List<BotProfile>.from(allBots)
        ..sort((a, b) =>
            (avgWinrate(a) - target).abs().compareTo((avgWinrate(b) - target).abs()));

      final source = sorted.isNotEmpty ? sorted.first : null;

      if (source != null) {
        final behavior = _parseBehavior(source.behavior);
        final aiParams = _extractAiParams(source.learnedParameters);
        aiParams['serverMMR'] = source.mmr.toDouble();
        aiParams['serverWinRateVsHuman'] = source.avgPBeatHuman;

        players.add(Player(
          id: 'bot_$i',
          name: _getBotName(behavior, skill),
          isHuman: false,
          botBehavior: behavior,
          botSkillLevel: skill,
          aiParameters: aiParams.isNotEmpty ? aiParams : null,
          position: i + 1,
        ));
      } else {
        players.add(Player(
          id: 'bot_$i',
          name: _getBotName(BotBehavior.balanced, skill),
          isHuman: false,
          botBehavior: BotBehavior.balanced,
          botSkillLevel: skill,
          position: i + 1,
        ));
      }
    }

    return players;
  }

  /// Crée les bots élite pour Silver/Gold/Platinum :
  /// 3/4 = meilleur bot de la catégorie, 1/4 = second meilleur
  Future<List<Player>> _createEliteBots(int numberOfBots) async {
    final botLearningService = BotLearningService();
    final targetSkill = _difficultyToSkillLevel(selectedBotDifficulty);

    final allBots = await botLearningService.fetchTopBots(limit: 20);

    double eliteScore(BotProfile b) => (b.winRate + b.avgPBeatHuman) / 2;

    final targetSkillName = _skillLevelToString(targetSkill);
    final filteredBots = allBots.where((b) => b.skillLevel == targetSkillName).toList();

    for (final bot in allBots) {
      final marker = bot.skillLevel == targetSkillName ? '→' : ' ';
      debugPrint('$marker 🤖 ${bot.botId} | MMR: ${bot.mmr} | Vs humain: ${(bot.avgPBeatHuman * 100).toStringAsFixed(0)}% | WinRate: ${(bot.winRate * 100).toStringAsFixed(0)}% | Score: ${(eliteScore(bot) * 100).toStringAsFixed(0)}%');
    }

    filteredBots.sort((a, b) => eliteScore(b).compareTo(eliteScore(a)));

    final bestBot = filteredBots.isNotEmpty ? filteredBots.first : (allBots.isNotEmpty ? allBots.first : null);
    final secondBot = filteredBots.length >= 2 ? filteredBots[1] : bestBot;

    if (bestBot != null) {
      debugPrint('⭐ #1: ${bestBot.botId} | MMR: ${bestBot.mmr} | Score: ${(eliteScore(bestBot) * 100).toStringAsFixed(0)}%');
    }
    if (secondBot != null && secondBot != bestBot) {
      debugPrint('⭐ #2: ${secondBot.botId} | MMR: ${secondBot.mmr} | Score: ${(eliteScore(secondBot) * 100).toStringAsFixed(0)}%');
    }

    final players = <Player>[];
    // 2/3 avec le #1, 1/3 avec le #2
    final secondBotCount = (numberOfBots / 3).ceil();
    final firstBotCount = numberOfBots - secondBotCount;

    for (int i = 0; i < numberOfBots; i++) {
      final source = i < firstBotCount ? bestBot : secondBot;
      if (source != null) {
        final behavior = _parseBehavior(source.behavior);
        final aiParams = _extractAiParams(source.learnedParameters);
        aiParams['serverMMR'] = source.mmr.toDouble();
        aiParams['serverWinRateVsHuman'] = source.avgPBeatHuman;

        players.add(Player(
          id: 'bot_$i',
          name: _getBotName(behavior, targetSkill),
          isHuman: false,
          botBehavior: behavior,
          botSkillLevel: targetSkill,
          aiParameters: aiParams.isNotEmpty ? aiParams : null,
          position: i + 1,
        ));
      } else {
        players.add(Player(
          id: 'bot_$i',
          name: _getBotName(BotBehavior.balanced, targetSkill),
          isHuman: false,
          botBehavior: BotBehavior.balanced,
          botSkillLevel: targetSkill,
          position: i + 1,
        ));
      }
    }

    return players;
  }

  BotBehavior _parseBehavior(String? raw) {
    switch (raw) {
      case 'fast':
        return BotBehavior.fast;
      case 'aggressive':
        return BotBehavior.aggressive;
      case 'balanced':
      default:
        return BotBehavior.balanced;
    }
  }

  String _skillLevelToString(BotSkillLevel level) {
    return level.toString().split('.').last;
  }

  Map<String, double> _extractAiParams(Map<String, dynamic> raw) {
    final params = <String, double>{};
    raw.forEach((key, value) {
      if (value is num) {
        params[key] = value.toDouble();
      }
    });
    return params;
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
      case Difficulty.platinum:
        return BotSkillLevel.platinum;
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

  /// Construit la description du niveau de difficulté
  Widget _buildDifficultyDescription(double Function(double) f, Difficulty difficulty) {
    final isPlatinum = difficulty == Difficulty.platinum;
    final color = isPlatinum ? Colors.purple : Colors.red;
    final icon = isPlatinum ? Icons.diamond : Icons.local_fire_department;
    final title = isPlatinum ? "MODE PLATINE" : "MODE DIFFICILE";
    final description = isPlatinum
        ? "💀 IA parfaite. Vous allez perdre. 💀"
        : "🔥 Bots experts avec 70-85% winrate 🔥";

    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(16), vertical: f(10)),
      margin: EdgeInsets.symmetric(horizontal: f(40)),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: f(18)),
          SizedBox(width: f(8)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: f(13),
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: f(11),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
