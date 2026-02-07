import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/ui_constants.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/player.dart';
import '../../models/game_state.dart';
import '../../models/game_settings.dart';
import '../../providers/game_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/game/bot_factory.dart';

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
  int selectedNumberOfPlayers = 4;

  @override
  void initState() {
    super.initState();
    _loadPersistedPrefs();
  }

  Future<void> _loadPersistedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        selectedNumberOfPlayers = prefs.getInt('lastNumberOfPlayers') ?? 4;
        final diffIndex = prefs.getInt('lastBotDifficulty');
        if (diffIndex != null && diffIndex < Difficulty.values.length) {
          selectedBotDifficulty = Difficulty.values[diffIndex];
        }
      });
    }
  }

  Future<void> _saveNumberOfPlayers(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastNumberOfPlayers', count);
  }

  Future<void> _saveBotDifficulty(Difficulty diff) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastBotDifficulty', diff.index);
  }

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
        backgroundColor: AppColors.backgroundMedium,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDecorations.darkGradient,
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
                        _saveBotDifficulty(newSelection.first);
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
                      _saveNumberOfPlayers(newSelection.first);
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

      BotFactory.resetUsedNames();
      List<Player> players = [
        Player(id: 'human', name: 'Vous', isHuman: true, position: 0)
      ];

      if (useSBMM) {
        players.addAll(await BotFactory.createSBMMBots(
          numberOfBots: numberOfBots,
          saveSlot: widget.saveSlot,
          isTournament: widget.isTournament,
        ).timeout(const Duration(seconds: 8)));
      } else {
        players.addAll(await BotFactory.createManualBots(
          numberOfBots: numberOfBots,
          difficulty: selectedBotDifficulty,
        ).timeout(const Duration(seconds: 8)));
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
        actionTextDisplayMs: settings.actionTextDisplayMs,
        saveSlot: widget.saveSlot,
        useSBMM: useSBMM,
        hardcoreLevel: hardcoreLevel,
      );

      if (!mounted) return;
      context.go('/solo/memorization');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Erreur démarrage partie: $e');
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
