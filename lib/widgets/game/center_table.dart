import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';
import '../../models/game_state.dart';
import '../../models/playing_card.dart';
import '../../services/ui/haptic_service.dart';
import 'card_widget.dart';
import 'deck_discard_widget.dart';
import 'svg_builder_provider.dart';
import '../../utils/history_personalizer.dart';

class CenterTable extends StatefulWidget {
  final GameState gameState;
  final bool isMyTurn;
  final bool hasDrawn;
  final bool isCompactMode;
  final VoidCallback? onShowDiscard;
  final VoidCallback? onDrawCard;
  final VoidCallback? onTakeFromDiscard;
  final int reactionTimeTotalMs;
  final int specialPowerTimeTotalMs;
  final bool enableHaptics;
  final SvgBuilder? svgBuilder;
  final GlobalKey? deckKey;
  final GlobalKey? discardKey;
  final PlayingCard? discardCardOverride;
  final GlobalKey? drawnCardKey;
  final bool showDeckAndDiscard;
  final bool isPaused;
  final String? localPlayerName;

  const CenterTable({
    super.key,
    required this.gameState,
    required this.isMyTurn,
    required this.hasDrawn,
    required this.isCompactMode,
    this.onShowDiscard,
    this.onDrawCard,
    this.onTakeFromDiscard,
    this.reactionTimeTotalMs = 3000,
    this.specialPowerTimeTotalMs = 15000,
    this.enableHaptics = false,
    this.svgBuilder,
    this.deckKey,
    this.discardKey,
    this.discardCardOverride,
    this.drawnCardKey,
    this.showDeckAndDiscard = true,
    this.isPaused = false,
    this.localPlayerName,
  });

  @override
  State<CenterTable> createState() => _CenterTableState();
}

class _CenterTableState extends State<CenterTable>
    with SingleTickerProviderStateMixin {
  bool _isDrawnCardExpanded = false;
  String? _lastDrawnCardId;
  int? _lastRedZoneHapticAtMs;
  late AnimationController _progressController;
  double _currentProgress = 1.0;
  Timer? _progressTimer; // Timer fluide pour le refresh à 24ms
  bool _wasPowerPending =
      false; // Pour détecter la fin du pouvoir et forcer resync
  double _powerProgress =
      1.0; // Progression du timer pouvoir (1.0 = début, 0.0 = expiré)
  Timer? _powerTimer; // Timer fluide pour la barre du pouvoir

  @override
  void initState() {
    super.initState();
    _lastDrawnCardId = widget.gameState.drawnCard?.id;
    // Controller uniquement pour vsync (ne pas addListener pour éviter le double-tick)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _initProgress();
    // Init power timer if power is already pending at first build
    if (widget.gameState.phase == GamePhase.specialPower) {
      _wasPowerPending = true;
      _startPowerTimer();
    }
  }

  void _initProgress() {
    final total = widget.reactionTimeTotalMs;
    final remaining = widget.gameState.reactionTimeRemaining;
    _currentProgress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 1.0;
    _lastServerRemaining = remaining;
    _lastServerUpdate = DateTime.now();
    _startProgressTimer();
  }

  /// Timer fluide à 24ms (~41fps) pour un refresh constant
  void _startProgressTimer() {
    _progressTimer?.cancel();
    if (widget.gameState.phase == GamePhase.reaction) {
      _progressTimer = Timer.periodic(const Duration(milliseconds: 24), (_) {
        if (!mounted) return;
        _onProgressTick();
      });
    }
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  DateTime? _lastServerUpdate;
  int _lastServerRemaining = 0;

  void _onProgressTick() {
    if (!mounted) return;
    if (widget.gameState.phase != GamePhase.reaction) {
      _stopProgressTimer();
      return;
    }

    final total = widget.reactionTimeTotalMs;
    final serverRemaining = widget.gameState.reactionTimeRemaining;

    // Si le jeu est en pause ou qu'un pouvoir est en cours, on gèle l'animation
    // et on met à jour le temps de référence pour que lors de la reprise,
    // on ne soustraie pas le temps passé en pause/pouvoir.
    if (widget.isPaused || widget.gameState.phase == GamePhase.specialPower) {
      _lastServerUpdate = DateTime.now();
      _lastServerRemaining = serverRemaining;
      return;
    }

    // Détecter un changement significatif (pas juste le décompte normal)
    // Un saut de plus de 500ms indique un reset ou une nouvelle phase
    final now = DateTime.now();
    final localElapsedMs = _lastServerUpdate != null
        ? now.difference(_lastServerUpdate!).inMilliseconds
        : 0;
    final currentEstimate =
        (_lastServerRemaining - localElapsedMs).clamp(0, total);

    // Détecter un désaccord majeur (> 500ms) entre notre temps estimé et le temps réel du serveur
    // ou si le serveur a plus de temps (reset du chrono)
    final diffFromEstimate = (serverRemaining - currentEstimate).abs();

    if (diffFromEstimate > 500 ||
        serverRemaining > _lastServerRemaining ||
        _lastServerUpdate == null) {
      _lastServerRemaining = serverRemaining;
      _lastServerUpdate = now;
    }

    // Recalcul de l'estimate avec les nouvelles ou anciennes valeurs baselines
    final finalElapsedMs = _lastServerUpdate != null
        ? now.difference(_lastServerUpdate!).inMilliseconds
        : 0;

    // Estimer le temps restant réel = baseline - temps écoulé localement
    final estimatedRemaining =
        (_lastServerRemaining - finalElapsedMs).clamp(0, total);
    final smoothProgress =
        total > 0 ? (estimatedRemaining / total).clamp(0.0, 1.0) : 0.0;

    // Toujours mettre à jour pour une animation fluide
    setState(() {
      _currentProgress = smoothProgress;
    });
  }

  void _updateProgressTarget() {
    final gs = widget.gameState;
    final isPowerPending = gs.phase == GamePhase.specialPower;

    // Détecter la fin du pouvoir : pouvoir était en cours et ne l'est plus
    // → la réaction démarre immédiatement (pas de délai)
    if (_wasPowerPending && !isPowerPending) {
      _lastServerRemaining = gs.reactionTimeRemaining;
      _lastServerUpdate = DateTime.now();
    }
    _wasPowerPending = isPowerPending;

    // Gérer le timer du pouvoir (fonctionne en phase playing ET reaction)
    if (isPowerPending) {
      if (_powerTimer == null || !_powerTimer!.isActive) {
        _startPowerTimer();
      }
    } else {
      _stopPowerTimer();
    }

    // Démarrer/arrêter le timer de réaction selon la phase
    if (gs.phase == GamePhase.reaction) {
      if (isPowerPending) {
        // Pouvoir en cours : stopper le timer de réaction
        _stopProgressTimer();
      } else if (_progressTimer == null || !_progressTimer!.isActive) {
        final serverRemaining = gs.reactionTimeRemaining;
        final total = widget.reactionTimeTotalMs;
        final isResume =
            serverRemaining < total * 0.95; // Moins de 95% = resume probable

        if (!isResume || _lastServerUpdate == null) {
          _lastServerUpdate = DateTime.now();
        }
        _lastServerRemaining = serverRemaining;
        _startProgressTimer();
      }
    } else if (!isPowerPending) {
      // Phase playing sans pouvoir : pas de timer de réaction
      _stopProgressTimer();
      _currentProgress = 1.0;
    }
  }

  void _startPowerTimer() {
    _powerTimer?.cancel();
    _powerTimer = Timer.periodic(const Duration(milliseconds: 24), (_) {
      if (!mounted) return;
      _onPowerTick();
    });
  }

  void _stopPowerTimer() {
    _powerTimer?.cancel();
    _powerTimer = null;
  }

  void _onPowerTick() {
    if (!mounted) return;
    final startTime = widget.gameState.specialPowerStartTime;
    if (startTime == null || widget.gameState.phase != GamePhase.specialPower) {
      _stopPowerTimer();
      return;
    }
    // Utiliser turnTimeoutMs du gameState (le serveur le met à specialPowerTimeoutMs
    // quand un pouvoir est en attente) au lieu du hardcoded specialPowerTimeTotalMs
    final totalMs = widget.gameState.turnTimeoutMs > 0
        ? widget.gameState.turnTimeoutMs
        : widget.specialPowerTimeTotalMs;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
    final remaining = (totalMs - elapsed).clamp(0, totalMs);
    final progress = (remaining / totalMs).clamp(0.0, 1.0);
    setState(() {
      _powerProgress = progress;
    });
  }

  @override
  void dispose() {
    _stopProgressTimer();
    _stopPowerTimer();
    _progressController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CenterTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newId = widget.gameState.drawnCard?.id;
    if (newId != _lastDrawnCardId) {
      _lastDrawnCardId = newId;
      setState(() {
        _isDrawnCardExpanded = false;
      });
    }
    if (widget.enableHaptics) {
      _maybeTriggerHaptic(oldWidget.gameState.reactionTimeRemaining);
    }
    _updateProgressTarget();
  }

  int _redZoneIntervalMs(double progress) {
    final t = (0.3 - progress) / 0.3;
    final interval = 600 - (480 * t);
    return interval.round();
  }

  Widget _buildPowerProgress() {
    final progress = _powerProgress;
    final color = Color.lerp(Colors.red, Colors.amber, progress)!;
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: Colors.black26,
      color: color,
      borderRadius: BorderRadius.circular(4),
    );
  }

  Widget _buildReactionProgress() {
    final progress = _currentProgress;

    Color progressColor;
    if (progress > 0.6) {
      progressColor =
          Color.lerp(Colors.orange, Colors.green, (progress - 0.6) / 0.4)!;
    } else if (progress > 0.3) {
      progressColor =
          Color.lerp(Colors.red, Colors.orange, (progress - 0.3) / 0.3)!;
    } else {
      progressColor = Colors.red;
    }

    return LinearProgressIndicator(
      value: progress,
      backgroundColor: Colors.black26,
      color: progressColor,
      borderRadius: BorderRadius.circular(4),
    );
  }

  void _maybeTriggerHaptic(int previousRemaining) {
    if (!mounted || !widget.enableHaptics) return;

    if (widget.gameState.phase != GamePhase.reaction) {
      _lastRedZoneHapticAtMs = null;
      return;
    }

    final total = widget.reactionTimeTotalMs;
    if (total <= 0) return;

    final remaining = widget.gameState.reactionTimeRemaining;
    if (remaining == previousRemaining) return;

    final progress = (remaining / total).clamp(0.0, 1.0);

    if (progress > 0.3) {
      _lastRedZoneHapticAtMs = null;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final interval = _redZoneIntervalMs(progress);
    if (_lastRedZoneHapticAtMs == null ||
        now - _lastRedZoneHapticAtMs! >= interval) {
      HapticService.cardTap();
      _lastRedZoneHapticAtMs = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gs = widget.gameState;
    final isReaction = gs.phase == GamePhase.reaction;
    final topCardValue = gs.topDiscardCard?.displayName ?? "?";

    final cardSize = widget.isCompactMode ? CardSize.small : CardSize.medium;
    final padding = widget.isCompactMode ? 8.0 : 15.0;
    final deckCount = gs.deck.length;

    // Détecter si on attend qu'un joueur choisisse son pouvoir
    final isWaitingForPower = gs.phase == GamePhase.specialPower;
    final powerPlayerName = isWaitingForPower
        ? (gs.currentPlayer.name == widget.localPlayerName
            ? 'Vous utilisez votre'
            : '${gs.currentPlayer.name} utilise son')
        : "";

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWaitingForPower) ...[
          // Power progress: visible pour les autres joueurs
          // (le joueur actif a son propre dialogue de pouvoir)
          if (gs.actionHistory.isNotEmpty) ...[
            _buildLastBotAction(gs),
            const SizedBox(height: 6),
          ],
          Text(
            "$powerPlayerName pouvoir...",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.isCompactMode ? 14 : 18,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: widget.isCompactMode ? 100 : 150,
            height: widget.isCompactMode ? 5 : 8,
            child: _buildPowerProgress(),
          ),
          const SizedBox(height: 10),
        ] else if (isReaction) ...[
          // Show what happened (e.g., "X ne garde pas le A") above the reaction prompt
          if (!widget.isMyTurn && gs.actionHistory.isNotEmpty) ...[
            _buildLastBotAction(gs),
            const SizedBox(height: 6),
          ],
          // Pendant le délai post-pouvoir (remaining > total), ne pas afficher
          // la barre de réaction (elle serait bloquée au vert).
          // On attend que le vrai countdown commence.
          if (gs.reactionTimeRemaining <= widget.reactionTimeTotalMs + 200) ...[
            Text(
              "Vite ! Avez-vous un${topCardValue == 'Dame' ? 'e' : ''} $topCardValue ?",
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.isCompactMode ? 12 : 16,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
              ),
            ),
            SizedBox(height: widget.isCompactMode ? 2 : 5),
            SizedBox(
              width: widget.isCompactMode ? 100 : 150,
              height: widget.isCompactMode ? 5 : 8,
              child: _buildReactionProgress(),
            ),
            SizedBox(height: widget.isCompactMode ? 4 : 10),
          ],
        ] else if (!widget.isMyTurn && gs.actionHistory.isNotEmpty) ...[
          _buildLastBotAction(gs),
          SizedBox(height: widget.isCompactMode ? 4 : 10),
        ],
        if (widget.isMyTurn && widget.hasDrawn && gs.drawnCard != null) ...[
          _buildDrawnCardDisplay(gs),
        ] else if (widget.showDeckAndDiscard) ...[
          _buildDeckAndDiscard(gs, cardSize, padding, deckCount),
        ],
      ],
    );
  }

  Widget _buildDrawnCardDisplay(GameState gs) {
    const baseScale = 1.0;
    final expandedScale = widget.isCompactMode ? 1.6 : 1.4;
    final cardSize = widget.isCompactMode ? CardSize.medium : CardSize.large;
    final frame = AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.all(widget.isCompactMode ? 12 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isDrawnCardExpanded
              ? [
                  Colors.amber.shade700,
                  Colors.amber.shade900,
                ]
              : [
                  Colors.green.shade800,
                  Colors.green.shade900,
                ],
        ),
        borderRadius: BorderRadius.circular(widget.isCompactMode ? 16 : 24),
        border: Border.all(
          color: _isDrawnCardExpanded ? Colors.amber : Colors.green.shade600,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: (_isDrawnCardExpanded ? Colors.amber : Colors.green)
                .withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isDrawnCardExpanded ? Icons.visibility : Icons.zoom_out_map,
                color: Colors.white,
                size: widget.isCompactMode ? 16 : 20,
              ),
              SizedBox(width: widget.isCompactMode ? 4 : 8),
              Text(
                _isDrawnCardExpanded ? "CARTE PIOCHÉE" : "TAP POUR AGRANDIR",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.isCompactMode ? 11 : 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: widget.isCompactMode ? 8 : 12),
          Container(
            key: widget.drawnCardKey,
            child: CardWidget(
              card: gs.drawnCard,
              size: cardSize,
              isRevealed: true,
              svgBuilder: widget.svgBuilder,
            ),
          ),
          SizedBox(height: widget.isCompactMode ? 8 : 12),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.isCompactMode ? 8 : 12,
              vertical: widget.isCompactMode ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "${gs.drawnCard!.displayName} (${gs.drawnCard!.points} pts)",
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.isCompactMode ? 11 : 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    final scale = _isDrawnCardExpanded ? expandedScale : baseScale;

    return GestureDetector(
      onTap: () {
        setState(() {
          _isDrawnCardExpanded = !_isDrawnCardExpanded;
        });
      },
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        child: frame,
      ),
    );
  }

  Widget _buildDeckAndDiscard(
      GameState gs, CardSize cardSize, double padding, int deckCount) {
    final canDraw = widget.onDrawCard != null &&
        widget.isMyTurn &&
        !widget.hasDrawn &&
        gs.phase == GamePhase.playing;
    final canTakeDiscard = widget.onTakeFromDiscard != null &&
        widget.isMyTurn &&
        !widget.hasDrawn &&
        gs.phase == GamePhase.playing &&
        gs.discardPile.isNotEmpty;

    final deckWidgetWithKey = DeckCardWidget(
      key: widget.deckKey,
      deckCount: deckCount,
      cardSize: cardSize,
      isCompact: widget.isCompactMode,
      enabled: canDraw,
      onTap: canDraw ? widget.onDrawCard : null,
      svgBuilder: widget.svgBuilder,
    );

    final discardWidgetWithKey = DiscardCardWidget(
      key: widget.discardKey,
      card: widget.discardCardOverride ?? gs.topDiscardCard,
      cardSize: cardSize,
      onTap: canTakeDiscard ? widget.onTakeFromDiscard : widget.onShowDiscard,
      svgBuilder: widget.svgBuilder,
    );

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(widget.isCompactMode ? 12 : 20),
        border: Border.all(color: Colors.white12, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.green.shade900.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              deckWidgetWithKey,
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompactMode ? 4 : 6,
                    vertical: widget.isCompactMode ? 1 : 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$deckCount',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: widget.isCompactMode ? 9 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: widget.isCompactMode ? 10 : 20),
          discardWidgetWithKey,
        ],
      ),
    );
  }

  Widget _buildLastBotAction(GameState gs) {
    final raw = gs.actionHistory.first;
    final rawText =
        raw.contains('] ') ? raw.substring(raw.indexOf('] ') + 2) : raw;
    final text =
        HistoryPersonalizer.personalize(rawText, widget.localPlayerName);

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.isCompactMode ? 12 : 16,
        fontWeight: FontWeight.bold,
        shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
      ),
    );
  }
}
