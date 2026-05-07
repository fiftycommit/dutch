import 'dart:math' show sqrt;
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
import '../../services/game/bot/bot_gossip_service.dart';
import '../../services/game/bot_factory.dart';
import '../../services/matchmaking/sbmm_client_service.dart';
import '../../services/matchmaking/sbmm_local_service.dart';
import '../../core/service_locator.dart';
import '../../core/interfaces/i_haptic_service.dart';

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

  // Preview du mix SBMM pour le nombre de joueurs courant
  SBMMBotMixResult? _previewResult;
  bool _previewLoading = false;
  int? _previewRequestedForCount;

  Difficulty _normalizeDisplayedBotDifficulty(Difficulty difficulty) {
    return difficulty == Difficulty.hard ? Difficulty.platinum : difficulty;
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedPrefs();
  }

  Future<void> _loadPersistedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final savedPlayers = prefs.getInt('lastNumberOfPlayers') ?? (widget.isTournament ? 6 : 4);
        // Clamp to valid range for tournament (3-6) vs quick (2-6)
        selectedNumberOfPlayers = widget.isTournament
            ? savedPlayers.clamp(3, 6)
            : savedPlayers.clamp(2, 6);
        final diffIndex = prefs.getInt('lastBotDifficulty');
        if (diffIndex != null && diffIndex < Difficulty.values.length) {
          selectedBotDifficulty = _normalizeDisplayedBotDifficulty(
            Difficulty.values[diffIndex],
          );
        }
      });
    }
    _refreshBotPreview();
  }

  Future<void> _refreshBotPreview() async {
    final botCount = selectedNumberOfPlayers - 1;
    if (botCount <= 0) return;
    if (_previewRequestedForCount == botCount && _previewLoading) return;
    _previewRequestedForCount = botCount;
    if (mounted) setState(() => _previewLoading = true);

    final result = await SBMMClientService.getBotMix(
      botCount: botCount,
      slotId: widget.saveSlot,
    );

    // Si un autre refresh a été demandé entre temps, ignorer ce résultat
    if (!mounted || _previewRequestedForCount != botCount) return;
    setState(() {
      _previewResult = result;
      _previewLoading = false;
    });

    if (SBMMLocalService.consumeTamperFlag() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 4),
          content: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "T'as voulu jouer, t'as perdu. Progression SBMM remise à zéro.",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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
      backgroundColor: AppColors.gradientBottom,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            final didPop = await Navigator.of(context).maybePop();
            if (!didPop && mounted) context.go('/');
          },
        ),
        title: Text(
            widget.isTournament ? 'Configuration Tournoi' : 'Nouvelle Partie',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.gradientTop,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    ServiceLocator().get<IHapticService>().buttonTap();
                    _startGame(context, useSBMM);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('COMMENCER'),
          ),
        ),
      ),
      body: Container(
        color: AppColors.gradientBottom,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              );
            }

            final scale = (constraints.maxHeight / 680).clamp(0.55, 1.0);
            final isCompact = scale < 0.85;
            double f(double size) {
              final minimum =
                  size < AppFontSizes.minimum ? size : AppFontSizes.minimum;
              return (size * scale).clamp(minimum, size).toDouble();
            }

            final spacingSmall = f(20);
            final spacingMedium = f(30);

            // Couleurs pour les segments
            const unselectedBg = Color(0xFF2D4F3C);
            const selectedBotBg = Colors.amber;
            const selectedPlayerBg = Colors.green;
            const segmentBorder = Color(0xFF4A7A5C);

            final botSegmentStyle = ButtonStyle(
              visualDensity:
                  isCompact ? VisualDensity.compact : VisualDensity.standard,
              tapTargetSize: isCompact
                  ? MaterialTapTargetSize.shrinkWrap
                  : MaterialTapTargetSize.padded,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: f(12), vertical: f(6)),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: f(13), fontWeight: FontWeight.w600),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedBotBg;
                }
                return unselectedBg;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
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
              visualDensity:
                  isCompact ? VisualDensity.compact : VisualDensity.standard,
              tapTargetSize: isCompact
                  ? MaterialTapTargetSize.shrinkWrap
                  : MaterialTapTargetSize.padded,
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: f(12), vertical: f(6)),
              ),
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: f(13), fontWeight: FontWeight.w600),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedPlayerBg;
                }
                return unselectedBg;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
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
              // start au lieu de center : empêche les enfants de "sauter"
              // verticalement quand le contenu interne change de hauteur
              // (passage Adaptatif <-> Manuel).
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: f(8)),
                Theme(
                  data: Theme.of(context).copyWith(
                    segmentedButtonTheme: SegmentedButtonThemeData(
                      style: botSegmentStyle,
                    ),
                  ),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: const Text('Adaptatif'),
                        icon: Icon(Icons.auto_awesome, size: f(18)),
                      ),
                      ButtonSegment(
                        value: false,
                        label: const Text('Manuel'),
                        icon: Icon(Icons.tune, size: f(18)),
                      ),
                    ],
                    selected: {useSBMM},
                    onSelectionChanged: (Set<bool> sel) {
                      if (sel.isEmpty) return;
                      final next = sel.first;
                      if (next == useSBMM) return;
                      ServiceLocator()
                          .get<IHapticService>()
                          .buttonTap();
                      context.read<SettingsProvider>().toggleSBMM(next);
                    },
                    style: botSegmentStyle,
                  ),
                ),
                SizedBox(height: spacingSmall),
                Text(
                  "Niveau des Bots",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: f(20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: spacingSmall),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    layoutBuilder: (currentChild, previousChildren) {
                      // Évite que les widgets sortants prennent de la place
                      // pendant le fade (sinon double-hauteur le temps de la transition).
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: useSBMM
                        ? SizedBox(
                            key: const ValueKey('mode-sbmm'),
                            width: double.infinity,
                            child: Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: f(24)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  // Bloc 1 : info sur le mode
                                  Container(
                                    padding: EdgeInsets.all(f(16)),
                                    decoration: BoxDecoration(
                                      color: Colors.black
                                          .withValues(alpha: 0.2),
                                      border: Border.all(
                                          color: Colors.amber, width: 1.5),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.auto_awesome,
                                            color: Colors.amber,
                                            size: f(36)),
                                        SizedBox(height: f(8)),
                                        Text(
                                          "Mode Adaptatif Actif",
                                          style: TextStyle(
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                            fontSize: f(17),
                                          ),
                                        ),
                                        SizedBox(height: f(4)),
                                        Text(
                                          "Le niveau s'ajuste automatiquement à vos résultats.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: f(13),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: f(10)),
                                  // Bloc 2 : preview des adversaires
                                  Container(
                                    padding: EdgeInsets.all(f(14)),
                                    decoration: BoxDecoration(
                                      color: Colors.black
                                          .withValues(alpha: 0.18),
                                      border: Border.all(
                                        color: Colors.amber
                                            .withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: _buildBotLevelPreview(f),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            key: const ValueKey('mode-manual'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.all(f(20)),
                                margin:
                                    EdgeInsets.symmetric(horizontal: f(40)),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  border: Border.all(
                                      color: Colors.lightBlueAccent,
                                      width: 1.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.tune,
                                      color: Colors.lightBlueAccent,
                                      size: f(36),
                                    ),
                                    SizedBox(height: f(10)),
                                    Text(
                                      "Mode Manuel Actif",
                                      style: TextStyle(
                                        color: Colors.lightBlueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: f(18),
                                      ),
                                    ),
                                    SizedBox(height: f(5)),
                                    Text(
                                      "A vous de choisir le niveau de difficulté des bots !",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: f(13),
                                      ),
                                    ),
                                    SizedBox(height: f(6)),
                                    Text(
                                      "Le RP augmente uniquement en mode Adaptatif.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.amber.shade200,
                                        fontSize: f(12),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: spacingSmall),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  segmentedButtonTheme:
                                      SegmentedButtonThemeData(
                                    style: botSegmentStyle,
                                  ),
                                ),
                                child: Wrap(
                                  spacing: f(10),
                                  runSpacing: f(10),
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    SegmentedButton<Difficulty>(
                                      emptySelectionAllowed: true,
                                      segments: [
                                        ButtonSegment(
                                          value: Difficulty.easy,
                                          label: const Text("Facile"),
                                          icon: Icon(Icons.sentiment_satisfied,
                                              size: f(18)),
                                        ),
                                        ButtonSegment(
                                          value: Difficulty.medium,
                                          label: const Text("Moyen"),
                                          icon: Icon(Icons.sentiment_neutral,
                                              size: f(18)),
                                        ),
                                        ButtonSegment(
                                          value: Difficulty.platinum,
                                          label: const Text("Difficile"),
                                          icon: Icon(Icons.diamond,
                                              size: f(18)),
                                        ),
                                      ],
                                      selected: selectedBotDifficulty ==
                                              Difficulty.mix
                                          ? <Difficulty>{}
                                          : {selectedBotDifficulty},
                                      onSelectionChanged:
                                          (Set<Difficulty> newSelection) {
                                        if (newSelection.isEmpty) return;
                                        setState(() {
                                          selectedBotDifficulty =
                                              newSelection.first;
                                        });
                                        _saveBotDifficulty(newSelection.first);
                                      },
                                      style: botSegmentStyle,
                                    ),
                                    ChoiceChip(
                                      avatar: Icon(
                                        Icons.shuffle,
                                        size: f(16),
                                        color: selectedBotDifficulty ==
                                                Difficulty.mix
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                      label: Text(
                                        'Mix',
                                        style: TextStyle(
                                          fontSize: f(13),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      selected: selectedBotDifficulty ==
                                          Difficulty.mix,
                                      onSelected: (_) {
                                        setState(() {
                                          selectedBotDifficulty =
                                              Difficulty.mix;
                                        });
                                        _saveBotDifficulty(Difficulty.mix);
                                      },
                                      selectedColor: selectedBotBg,
                                      backgroundColor: unselectedBg,
                                      side: const BorderSide(
                                          color: segmentBorder),
                                      labelStyle: TextStyle(
                                        color: selectedBotDifficulty ==
                                                Difficulty.mix
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: f(8),
                                        vertical: f(6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
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
                            ButtonSegment(value: 3, label: Text("3")),
                            ButtonSegment(value: 4, label: Text("4")),
                            ButtonSegment(value: 5, label: Text("5")),
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
                      _refreshBotPreview();
                    },
                    style: playerSegmentStyle,
                  ),
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
      BotGossipService.instance.reset();
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
          saveSlot: widget.saveSlot,
        ).timeout(const Duration(seconds: 10)));
      }

      if (!mounted) return;

      // Déterminer le hardcoreLevel basé sur la difficulté sélectionnée
      HardcoreLevel? hardcoreLevel;
      if (selectedBotDifficulty == Difficulty.platinum) {
        hardcoreLevel = HardcoreLevel.impossible;
      }

      await gameProvider.createNewGame(
        players: players,
        gameMode: widget.isTournament ? GameMode.tournament : GameMode.quick,
        difficulty: Difficulty.easy,
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

  Widget _buildBotLevelPreview(double Function(double) f) {
    final result = _previewResult;

    if (result == null || result.botLevels.isEmpty) {
      if (_previewLoading) {
        return SizedBox(
          height: f(22),
          width: f(22),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.amber.withValues(alpha: 0.7),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // Pair chaque bot (niveau, personnalité) et compte les paires identiques
    final pairCounts = <String, int>{};
    final pairCount = result.botLevels.length;
    for (var i = 0; i < pairCount; i++) {
      final lvl = result.botLevels[i];
      final beh = i < result.botBehaviors.length
          ? result.botBehaviors[i]
          : 'balanced';
      final key = '$lvl|$beh';
      pairCounts[key] = (pairCounts[key] ?? 0) + 1;
    }

    const levelOrder = {'bronze': 0, 'silver': 1, 'gold': 2};
    const behaviorOrder = {
      'balanced': 0,
      'fast': 1,
      'aggressive': 2,
      'moi': 3,
    };
    final sortedPairs = pairCounts.keys.toList()
      ..sort((a, b) {
        final pa = a.split('|');
        final pb = b.split('|');
        final lvlCmp = (levelOrder[pa[0]] ?? 0)
            .compareTo(levelOrder[pb[0]] ?? 0);
        if (lvlCmp != 0) return lvlCmp;
        return (behaviorOrder[pa[1]] ?? 0)
            .compareTo(behaviorOrder[pb[1]] ?? 0);
      });

    final skillLabel = SBMMLocalService.skillLabelFromCursor(result.cursor);
    final archetypeLabel = _archetypeLabel(result.archetype);

    return Column(
      children: [
        _playerSkillBadge(f, skillLabel, archetypeLabel),
        SizedBox(height: f(10)),
        Text(
          "Adversaires de cette partie",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: f(12),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: f(8)),
        Wrap(
          spacing: f(8),
          runSpacing: f(6),
          alignment: WrapAlignment.center,
          children: [
            for (final key in sortedPairs)
              _botPairBadge(f, key.split('|')[0], key.split('|')[1],
                  pairCounts[key]!),
          ],
        ),
        SizedBox(height: f(8)),
        _lobbyWeightIndicator(f, selectedNumberOfPlayers),
      ],
    );
  }

  Widget _lobbyWeightIndicator(double Function(double) f, int playerCount) {
    final weight = sqrt((playerCount - 1).clamp(1, 9)) / sqrt(5);
    final pct = (weight * 100).round();
    return Text(
      'Impact sur la progression : $pct%',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: f(11),
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _botPairBadge(
      double Function(double) f, String level, String behavior, int count) {
    late final String levelLabel;
    late final Color accent;
    switch (level) {
      case 'bronze':
        levelLabel = 'Bronze';
        accent = const Color(0xFFCD7F32);
        break;
      case 'silver':
        levelLabel = 'Argent';
        accent = const Color(0xFFB0B0B0);
        break;
      case 'gold':
      default:
        levelLabel = 'Or';
        accent = const Color(0xFFFFC107);
        break;
    }

    final behLabel = switch (behavior) {
      'fast' => 'Rapide',
      'aggressive' => 'Agressif',
      'moi' => 'Miroir',
      _ => 'Équilibré',
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(10), vertical: f(5)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: accent, size: f(14)),
          SizedBox(width: f(5)),
          Text(
            '$levelLabel • $behLabel${count > 1 ? ' × $count' : ''}',
            style: TextStyle(
              color: Colors.white,
              fontSize: f(12),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _archetypeLabel(PlayerArchetype archetype) {
    return switch (archetype) {
      PlayerArchetype.dominant => 'Dominant',
      PlayerArchetype.dutcher => 'Dutcher',
      PlayerArchetype.learner => 'Prudent',
      PlayerArchetype.balanced => 'Équilibré',
    };
  }

  Widget _playerSkillBadge(
      double Function(double) f, String label, String archetype) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(12), vertical: f(6)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, color: Colors.amber, size: f(14)),
          SizedBox(width: f(6)),
          Text(
            '$label • $archetype',
            style: TextStyle(
              color: Colors.white,
              fontSize: f(12),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /*
  /// Construit la description du niveau de difficulté
  Widget _buildDifficultyDescription(
      double Function(double) f, Difficulty difficulty) {
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
  */
}
