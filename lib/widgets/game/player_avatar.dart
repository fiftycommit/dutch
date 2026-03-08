import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../core/interfaces/i_haptic_service.dart';
import '../../core/service_locator.dart';
import '../../utils/screen_utils.dart';

class PlayerAvatar extends StatefulWidget {
  final Player player;
  final bool isActive; // Si c'est le tour du joueur
  final bool showName;
  final double size;
  final bool compactMode; // Mode compact: juste le badge avec emoji + nom
  final bool reserveTrailingSpace; // Espace réservé pour le badge de cartes
  final int? turnStartTime; // Timestamp du début du tour (ms)
  final int? turnDuration; // Durée totale du tour (ms)
  final bool isAfk; // Si le joueur est AFK
  final bool isLocalPlayer; // Si c'est le joueur de l'appareil local

  const PlayerAvatar({
    super.key,
    required this.player,
    this.isActive = false,
    this.showName = true,
    this.size = 60.0,
    this.compactMode = false,
    this.reserveTrailingSpace = false,
    this.turnStartTime,
    this.turnDuration,
    this.isAfk = false,
    this.isLocalPlayer = false,
  });

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  int _lastHapticTick = 0;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), // Sera écrasé par la vraie durée
    )..addListener(() {
        if (mounted) setState(() {});
        _checkHaptic();
      });

    _updateTimer();
  }

  @override
  void didUpdateWidget(PlayerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive ||
        widget.turnStartTime != oldWidget.turnStartTime ||
        widget.turnDuration != oldWidget.turnDuration) {
      _updateTimer();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _updateTimer() {
    if (!widget.isActive ||
        widget.turnStartTime == null ||
        widget.turnDuration == null) {
      _progressController.stop();
      _progressController.value = 1.0;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    // Si turnStartTime est dans le futur (clock skew), elapsed est négatif.
    // En utilisant 0 au minimum, on force le timer à démarrer immédiatement.
    final elapsed =
        (now - widget.turnStartTime!).clamp(0, widget.turnDuration!);
    final remaining = widget.turnDuration! - elapsed;

    if (remaining > 0) {
      _progressController.duration =
          Duration(milliseconds: widget.turnDuration!);
      // On affecte la valeur actuelle
      _progressController.value = remaining / widget.turnDuration!;
      // On lance l'animation vers 0 depuis cette valeur actuelle
      _progressController.reverse();
    } else {
      _progressController.stop();
      _progressController.value = 0.0;
    }
  }

  void _checkHaptic() {
    if (!widget.isActive || !widget.isLocalPlayer) return;

    final progress = _progressController.value;
    if (progress > 0 && progress < 0.25) {
      // 80 BPM = une vibration toutes les 750ms
      // Le timer global correspond à turnDuration.
      // On calcule le temps écoulé théorique en millisecondes
      if (widget.turnDuration != null) {
        final elapsedTotal = widget.turnDuration! * (1.0 - progress);
        final tickIndex = (elapsedTotal / 100).round();
        if (tickIndex != _lastHapticTick && tickIndex % 7 == 0) {
          _lastHapticTick = tickIndex;
          ServiceLocator().get<IHapticService>().cardTap();
        }
      }
    }
  }

  /// Couleur progressive : vert vif → orange → rouge
  Color _timerColor() {
    final progress = _progressController.value;
    if (progress > 0.5) {
      // Vert → Orange (100% → 50%)
      final t = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(Colors.orange, const Color(0xFF4CAF50), t)!;
    } else {
      // Orange → Rouge (50% → 0%)
      final t = (progress / 0.5).clamp(0.0, 1.0);
      return Color.lerp(Colors.red, Colors.orange, t)!;
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

    if (widget.isAfk) {
      // Afk background logic can be handled separately if needed, but the container uses _timerColor
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
                      widthFactor: _progressController.value,
                      child: Container(
                        color: _timerColor().withValues(alpha: 0.7),
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
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          widget.isLocalPlayer
                              ? "Vous"
                              : widget.player.displayName,
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
                      if (widget.reserveTrailingSpace)
                        SizedBox(width: ScreenUtils.spacing(context, 18)),
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
                      Color(widget.player.avatarColorValue),
                      Color.lerp(
                        Color(widget.player.avatarColorValue),
                        Colors.black,
                        0.4,
                      )!,
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
              widget.isLocalPlayer ? "Vous" : widget.player.displayName,
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
