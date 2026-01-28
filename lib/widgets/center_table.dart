import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../services/haptic_service.dart';
import 'card_widget.dart';

class CenterTable extends StatefulWidget {
  final GameState gameState;
  final bool isMyTurn;
  final bool hasDrawn;
  final bool isCompactMode;
  final VoidCallback? onShowDiscard;
  final VoidCallback? onDrawCard;
  final VoidCallback? onTakeFromDiscard;
  final int reactionTimeTotalMs;
  final bool enableHaptics;

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
    this.enableHaptics = false,
  });

  @override
  State<CenterTable> createState() => _CenterTableState();
}

class _CenterTableState extends State<CenterTable> {
  bool _isDrawnCardExpanded = false;
  String? _lastDrawnCardId;
  int? _lastRedZoneHapticAtMs;

  @override
  void initState() {
    super.initState();
    _lastDrawnCardId = widget.gameState.drawnCard?.id;
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
  }

  int _redZoneIntervalMs(double progress) {
    final t = (0.3 - progress) / 0.3;
    final interval = 600 - (480 * t);
    return interval.round();
  }

  Widget _buildReactionProgress() {
    final total = widget.reactionTimeTotalMs;
    final remaining = widget.gameState.reactionTimeRemaining;
    final progress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;

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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: progress, end: progress),
      duration: const Duration(milliseconds: 100),
      builder: (context, animatedProgress, child) {
        return LinearProgressIndicator(
          value: animatedProgress,
          backgroundColor: Colors.black26,
          color: progressColor,
          borderRadius: BorderRadius.circular(4),
        );
      },
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isReaction) ...[
          Text(
            "Vite ! Avez-vous un$topCardValue ?",
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
        if (widget.isMyTurn && widget.hasDrawn && gs.drawnCard != null) ...[
          _buildDrawnCardDisplay(gs),
        ] else ...[
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
          CardWidget(
            card: gs.drawnCard,
            size: cardSize,
            isRevealed: true,
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

    final deckCard = Opacity(
      opacity: canDraw ? 1.0 : 0.6,
      child: CardWidget(card: null, size: cardSize, isRevealed: false),
    );
    final deckWidget = canDraw
        ? GestureDetector(onTap: widget.onDrawCard, child: deckCard)
        : deckCard;
    final discardCard =
        CardWidget(card: gs.topDiscardCard, size: cardSize, isRevealed: true);
    final discardWidget = canTakeDiscard
        ? GestureDetector(onTap: widget.onTakeFromDiscard, child: discardCard)
        : (widget.onShowDiscard != null
            ? GestureDetector(onTap: widget.onShowDiscard, child: discardCard)
            : discardCard);

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
              deckWidget,
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
                      color: Colors.white70,
                      fontSize: widget.isCompactMode ? 9 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: widget.isCompactMode ? 10 : 20),
          discardWidget,
        ],
      ),
    );
  }
}
