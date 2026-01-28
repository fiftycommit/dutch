import 'dart:async';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../utils/screen_utils.dart';

class PlayerAvatar extends StatefulWidget {
  final Player player;
  final bool isActive; // Si c'est le tour du joueur
  final bool showName;
  final double size;
  final bool compactMode; // Mode compact: juste le badge avec emoji + nom
  final int? turnStartTime; // Timestamp du début du tour (ms)
  final int? turnDuration; // Durée totale du tour (ms)
  final bool isAfk; // Si le joueur est AFK

  const PlayerAvatar({
    super.key,
    required this.player,
    this.isActive = false,
    this.showName = true,
    this.size = 60.0,
    this.compactMode = false,
    this.turnStartTime,
    this.turnDuration,
    this.isAfk = false,
  });

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  double _progress = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive && widget.turnStartTime != null) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(PlayerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive ||
        widget.turnStartTime != oldWidget.turnStartTime) {
      _timer?.cancel();
      if (widget.isActive && widget.turnStartTime != null) {
        _startTimer();
      } else {
        setState(() {
          _progress = 1.0;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateProgress();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateProgress();
    });
  }

  void _updateProgress() {
    if (widget.turnStartTime == null || widget.turnDuration == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - widget.turnStartTime!;
    final remaining = widget.turnDuration! - elapsed;
    final newProgress = (remaining / widget.turnDuration!).clamp(0.0, 1.0);

    if ((newProgress - _progress).abs() > 0.005 || newProgress == 0.0) {
      if (mounted) {
        setState(() {
          _progress = newProgress;
        });
      }
    }

    if (remaining <= 0) {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mode compact: juste un badge avec emoji + nom qui s'illumine
    if (widget.compactMode) {
      return _buildCompactBadge(context);
    }

    // Mode classique avec avatar circulaire (pour les bots)
    return _buildClassicAvatar(context);
  }

  /// Badge compact: emoji + nom dans une seule bande
  Widget _buildCompactBadge(BuildContext context) {
    final badgeHeight = ScreenUtils.scale(context, widget.size * 0.6);
    final fontSize = ScreenUtils.scaleFont(context, widget.size * 0.35);
    final emojiSize = ScreenUtils.scaleFont(context, widget.size * 0.4);

    Color backgroundColor = widget.isActive
        ? Colors.amber.shade700
        : Colors.black.withValues(alpha: 0.5);

    if (widget.isActive && widget.turnStartTime != null) {
      // Background color for timer is now consistent
      backgroundColor = Colors.grey.shade700;
    }

    if (widget.isAfk) {
      backgroundColor = Colors.grey.shade800;
    }

    return Stack(
      children: [
        // Container principal (fond + bordure)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          constraints: BoxConstraints(minHeight: badgeHeight),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5), // Fond noir de base
            borderRadius: BorderRadius.circular(
              ScreenUtils.borderRadius(context, 20),
            ),
            border: Border.all(
              color: widget.isAfk
                  ? Colors.red
                  : (widget.isActive ? Colors.amber : Colors.white24),
              width: widget.isActive || widget.isAfk ? 2 : 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              ScreenUtils.borderRadius(context, 20),
            ),
            child: Stack(
              children: [
                // Barre de progression en arrière-plan
                if (widget.isActive && widget.turnStartTime != null)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progress,
                      child: Container(
                        color: backgroundColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ),

                // Contenu (Emoji + Nom + indicateur AFK)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenUtils.spacing(context, 10),
                    vertical: ScreenUtils.spacing(context, 4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.player.displayAvatar,
                        style: TextStyle(fontSize: emojiSize),
                      ),
                      SizedBox(width: ScreenUtils.spacing(context, 4)),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          widget.player.displayName,
                          style: TextStyle(
                            color:
                                widget.isActive ? Colors.white : Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isAfk) ...[
                        SizedBox(width: ScreenUtils.spacing(context, 4)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "AFK",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: fontSize * 0.7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Avatar classique avec cercle (pour les bots sur les côtés)
  Widget _buildClassicAvatar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar circulaire avec indicateur de tour
        Container(
          width: ScreenUtils.scale(context, widget.size),
          height: ScreenUtils.scale(context, widget.size),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isActive
                  ? [
                      Colors.amber.shade400,
                      Colors.amber.shade700,
                    ]
                  : [
                      widget.player.avatarColor,
                      Color.lerp(widget.player.avatarColor, Colors.black, 0.4)!,
                    ],
            ),
            border: Border.all(
              color: widget.isActive ? Colors.amber : Colors.white24,
              width: widget.isActive ? 3 : 2,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              widget.player.displayAvatar,
              style: TextStyle(
                fontSize: ScreenUtils.scaleFont(context, widget.size * 0.5),
              ),
            ),
          ),
        ),

        // Nom du joueur
        if (widget.showName) ...[
          SizedBox(height: ScreenUtils.spacing(context, 4)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenUtils.spacing(context, 6),
              vertical: ScreenUtils.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? Colors.amber.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(
                ScreenUtils.borderRadius(context, 10),
              ),
              border: widget.isActive
                  ? Border.all(color: Colors.amber, width: 1)
                  : null,
            ),
            child: Text(
              widget.player.displayName,
              style: TextStyle(
                color: Colors.white,
                fontSize: ScreenUtils.scaleFont(context, 10),
                fontWeight:
                    widget.isActive ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
