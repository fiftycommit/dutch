import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../utils/ui_constants.dart';
import '../../models/game_state.dart';
import '../../models/playing_card.dart';
import '../../core/interfaces/i_haptic_service.dart';
import '../../core/service_locator.dart';
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

  /// Largeur disponible pour les textes d'historique.
  /// Correspond à baseCenterWidth (largeur du bloc deck/discard) pour que
  /// les textes wrappent à la bonne largeur au lieu d'être réduits par le FittedBox.
  final double? availableWidth;

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
    this.availableWidth,
  });

  @override
  State<CenterTable> createState() => _CenterTableState();
}

class _CenterTableState extends State<CenterTable>
    with TickerProviderStateMixin {
  bool _isDrawnCardExpanded = false;
  String? _lastDrawnCardId;
  int? _lastRedZoneHapticAtMs;

  // ── Reaction timer ──
  double _currentProgress = 1.0;
  Ticker? _reactionTicker;
  DateTime? _lastServerUpdate;
  int _lastServerRemaining = 0;

  // ── Power timer ──
  double _powerProgress = 1.0;
  Ticker? _powerTicker;

  /// Fallback client-side si le serveur ne fournit pas specialPowerStartTime
  int? _powerStartFallback;

  /// Détecte la fin du pouvoir pour resync la réaction
  bool _wasPowerPending = false;

  @override
  void initState() {
    super.initState();
    _lastDrawnCardId = widget.gameState.drawnCard?.id;
    _initReactionProgress();
    // Initialiser le power timer si un pouvoir est déjà en cours au premier build
    if (widget.gameState.phase == GamePhase.specialPower) {
      _wasPowerPending = true;
      _startPowerTicker();
    }
  }

  void _initReactionProgress() {
    final total = widget.reactionTimeTotalMs;
    final remaining = widget.gameState.reactionTimeRemaining;
    _currentProgress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 1.0;
    _lastServerRemaining = remaining;
    _lastServerUpdate = DateTime.now();
    _startReactionTicker();
  }

  // ── Reaction ticker (remplace Timer.periodic pour respecter le vsync) ──

  void _startReactionTicker() {
    _reactionTicker?.dispose();
    _reactionTicker = null;
    if (widget.gameState.phase == GamePhase.reaction) {
      _reactionTicker = createTicker((_) => _onReactionTick());
      _reactionTicker!.start();
    }
  }

  void _stopReactionTicker() {
    _reactionTicker?.dispose();
    _reactionTicker = null;
  }

  void _onReactionTick() {
    if (!mounted) return;
    if (widget.gameState.phase != GamePhase.reaction) {
      _stopReactionTicker();
      return;
    }

    final total = widget.reactionTimeTotalMs;
    if (total <= 0) return;

    final serverRemaining = widget.gameState.reactionTimeRemaining;

    // Si le jeu est en pause ou qu'un pouvoir est en cours, geler l'animation
    if (widget.isPaused || widget.gameState.phase == GamePhase.specialPower) {
      _lastServerUpdate = DateTime.now();
      _lastServerRemaining = serverRemaining;
      return;
    }

    final now = DateTime.now();
    final localElapsedMs = _lastServerUpdate != null
        ? now.difference(_lastServerUpdate!).inMilliseconds
        : 0;
    final currentEstimate =
        (_lastServerRemaining - localElapsedMs).clamp(0, total);

    // Détecter un désaccord majeur (> 500ms) ou un reset du chrono
    final diffFromEstimate = (serverRemaining - currentEstimate).abs();
    if (diffFromEstimate > 500 ||
        serverRemaining > _lastServerRemaining ||
        _lastServerUpdate == null) {
      _lastServerRemaining = serverRemaining;
      _lastServerUpdate = now;
    }

    final finalElapsedMs = _lastServerUpdate != null
        ? now.difference(_lastServerUpdate!).inMilliseconds
        : 0;
    final estimatedRemaining =
        (_lastServerRemaining - finalElapsedMs).clamp(0, total);
    final smoothProgress = (estimatedRemaining / total).clamp(0.0, 1.0);

    setState(() {
      _currentProgress = smoothProgress;
    });
  }

  // ── Power ticker ──

  void _startPowerTicker() {
    _powerTicker?.dispose();
    _powerTicker = null;
    _powerProgress = 1.0;
    // Mémoriser le moment où le pouvoir a commencé côté client (fallback)
    _powerStartFallback ??= DateTime.now().millisecondsSinceEpoch;
    _powerTicker = createTicker((_) => _onPowerTick());
    _powerTicker!.start();
  }

  void _stopPowerTicker() {
    _powerTicker?.dispose();
    _powerTicker = null;
    _powerStartFallback = null;
  }

  void _onPowerTick() {
    if (!mounted) return;
    if (widget.isPaused) return;
    if (widget.gameState.phase != GamePhase.specialPower) {
      _stopPowerTicker();
      return;
    }

    // Utiliser le timestamp serveur quand disponible, sinon le fallback client
    final startTime =
        widget.gameState.specialPowerStartTime ?? _powerStartFallback;
    if (startTime == null) {
      // Ni serveur ni fallback — ne devrait pas arriver, mais on se protège
      _powerStartFallback = DateTime.now().millisecondsSinceEpoch;
      return;
    }

    // turnTimeoutMs est mis à la valeur specialPowerTimeoutMs par le serveur
    // quand un pouvoir est en attente ; fallback sur le prop du widget
    final totalMs = widget.gameState.turnTimeoutMs > 0
        ? widget.gameState.turnTimeoutMs
        : widget.specialPowerTimeTotalMs;
    if (totalMs <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - startTime;
    // Protéger contre les timestamps dans le futur (désync d'horloge)
    final clampedElapsed = elapsed.clamp(0, totalMs);
    final remaining = totalMs - clampedElapsed;
    final progress = (remaining / totalMs).clamp(0.0, 1.0);

    setState(() {
      _powerProgress = progress;
    });
  }

  // ── Coordination des transitions de phase ──

  void _updateProgressTarget() {
    final gs = widget.gameState;
    final isPowerPending = gs.phase == GamePhase.specialPower;

    // Détecter la fin du pouvoir → resync immédiate du timer de réaction
    if (_wasPowerPending && !isPowerPending) {
      _lastServerRemaining = gs.reactionTimeRemaining;
      _lastServerUpdate = DateTime.now();
    }
    _wasPowerPending = isPowerPending;

    // Gérer le ticker du pouvoir
    if (isPowerPending) {
      if (_powerTicker == null || !_powerTicker!.isActive) {
        _startPowerTicker();
      }
    } else {
      _stopPowerTicker();
    }

    // Gérer le ticker de réaction
    if (gs.phase == GamePhase.reaction) {
      if (isPowerPending) {
        _stopReactionTicker();
      } else if (_reactionTicker == null || !_reactionTicker!.isActive) {
        final serverRemaining = gs.reactionTimeRemaining;
        final total = widget.reactionTimeTotalMs;
        final isResume = total > 0 && serverRemaining < total * 0.95;

        if (!isResume || _lastServerUpdate == null) {
          _lastServerUpdate = DateTime.now();
        }
        _lastServerRemaining = serverRemaining;
        _startReactionTicker();
      }
    } else if (!isPowerPending) {
      _stopReactionTicker();
      _currentProgress = 1.0;
    }
  }

  @override
  void dispose() {
    _stopReactionTicker();
    _stopPowerTicker();
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
      ServiceLocator().get<IHapticService>().cardTap();
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
          _buildConstrainedText(
            "$powerPlayerName pouvoir...",
            fontSize: widget.isCompactMode ? 14 : 18,
            italic: true,
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
            _buildConstrainedText(
              "Vite ! Avez-vous un${topCardValue == 'Dame' ? 'e' : ''} $topCardValue ?",
              fontSize: widget.isCompactMode ? 12 : 16,
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

  /// Texte contraint avec maxLines pour éviter les débordements.
  /// SizedBox(width: availableWidth) force le wrapping à la largeur du bloc
  /// deck/discard, empêchant le FittedBox parent de réduire le texte.
  Widget _buildConstrainedText(String text,
      {required double fontSize, bool italic = false}) {
    final textWidget = AutoSizeText(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      minFontSize: 5,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
      ),
    );
    if (widget.availableWidth != null) {
      return SizedBox(width: widget.availableWidth, child: textWidget);
    }
    return textWidget;
  }

  /// Dernière action d'un bot/joueur, affichée au centre.
  /// SizedBox(width: availableWidth) force le wrapping à la largeur du bloc
  /// deck/discard, empêchant le FittedBox parent de réduire le texte.
  Widget _buildLastBotAction(GameState gs) {
    final raw = gs.actionHistory.first;
    final rawText =
        raw.contains('] ') ? raw.substring(raw.indexOf('] ') + 2) : raw;
    final text =
        HistoryPersonalizer.personalize(rawText, widget.localPlayerName);

    final fontSize = widget.isCompactMode ? 12.0 : 16.0;
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
    );

    // 1 ligne pour les textes courts, 2 lignes pour les longs
    final maxLines = text.length > 35 ? 2 : 1;

    final textWidget = AutoSizeText(
      text,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      minFontSize: 5,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );

    if (widget.availableWidth != null) {
      return SizedBox(width: widget.availableWidth, child: textWidget);
    }
    return textWidget;
  }
}
