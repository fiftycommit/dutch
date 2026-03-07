import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../models/playing_card.dart';
import '../../../utils/ui_constants.dart';
import '../../game/card_widget.dart';
import '../../multiplayer/game_overlays.dart';
import '../responsive_dialog.dart';

/// Widgets partagés pour les dialogs de pouvoirs spéciaux
/// Principe GRASP: Pure Fabrication - Regroupe les widgets UI communs
class PowerDialogWidgets {
  static const double cardAspectRatio = 7 / 5;

  /// Calcule la largeur de carte pour une grille
  static double cardWidthForGrid(DialogMetrics metrics,
      {required int columns, double maxHeightFraction = 0.35}) {
    final spacing = metrics.space(8);
    final widthByCols = columns > 0
        ? (metrics.contentWidth - spacing * (columns - 1)) / columns
        : metrics.contentWidth;
    final heightByRows =
        (metrics.contentHeight * maxHeightFraction) / cardAspectRatio;
    return math.max(0.0, math.min(widthByCols, heightByRows));
  }

  /// Crée une carte mise à l'échelle
  static Widget scaledCard({
    required double width,
    required bool isRevealed,
    PlayingCard? card,
  }) {
    final height = width * cardAspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: CardWidget(
          card: card,
          size: CardSize.large,
          isRevealed: isRevealed,
        ),
      ),
    );
  }

  /// Crée un bouton de sélection de joueur
  static Widget playerSelectionButton({
    required String label,
    required bool isSelected,
    required Color baseColor,
    required VoidCallback onTap,
    required DialogMetrics metrics,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.space(12),
          vertical: metrics.space(8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? baseColor.withValues(alpha: 0.8) : baseColor,
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white30,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: metrics.font(12),
          ),
        ),
      ),
    );
  }

  /// Crée une sélection de carte cliquable
  static Widget cardSelectionItem({
    required double cardWidth,
    required bool isSelected,
    required Color borderColor,
    required VoidCallback onTap,
    required DialogMetrics metrics,
  }) {
    final borderWidth = math.max(1.0, metrics.scale * 1.5);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.amber : borderColor,
            width: isSelected ? borderWidth * 2 : borderWidth,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: scaledCard(width: cardWidth, isRevealed: false),
      ),
    );
  }

  /// En-tête de dialog avec icône et titre
  static Widget dialogHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    String? subtitle,
    required DialogMetrics metrics,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: metrics.size(40)),
        SizedBox(height: metrics.space(8)),
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: metrics.font(20),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          SizedBox(height: metrics.space(8)),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: metrics.font(14),
            ),
          ),
        ],
      ],
    );
  }

  /// Bouton "PASSER" ou "ANNULER"
  static Widget skipButton({
    required String label,
    required VoidCallback onPressed,
    required DialogMetrics metrics,
  }) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textDisabled,
          fontSize: metrics.font(16),
        ),
      ),
    );
  }

  /// Bouton "PASSER" ou "ANNULER" avec auto-close
  static Widget tickingSkipButton({
    required String labelPrefix,
    required VoidCallback onPressed,
    required DialogMetrics metrics,
    required int autoCloseSeconds,
    VoidCallback? onTimeout,
  }) {
    if (autoCloseSeconds <= 0) {
      return skipButton(
        label: labelPrefix,
        onPressed: onPressed,
        metrics: metrics,
      );
    }
    return _TickingSkipButton(
      autoCloseSeconds: autoCloseSeconds,
      labelPrefix: labelPrefix,
      onPressed: onPressed,
      onTimeout: onTimeout,
      metrics: metrics,
    );
  }

  /// Bouton de confirmation stylisé
  static Widget confirmButton({
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback? onPressed,
    required DialogMetrics metrics,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.space(28),
          vertical: metrics.space(12),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: metrics.font(16),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Bouton de confirmation stylisé avec auto-close
  static Widget tickingConfirmButton({
    required String labelPrefix,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback? onPressed,
    required DialogMetrics metrics,
    required int autoCloseSeconds,
    VoidCallback? onTimeout,
  }) {
    if (autoCloseSeconds <= 0) {
      return confirmButton(
        label: labelPrefix,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        onPressed: onPressed,
        metrics: metrics,
      );
    }
    return _TickingConfirmButton(
      autoCloseSeconds: autoCloseSeconds,
      labelPrefix: labelPrefix,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      onPressed: onPressed ?? () {},
      onTimeout: onTimeout,
      metrics: metrics,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TickingConfirmButton : bouton de confirmation avec décompte auto-close
// Gèle automatiquement le décompte quand GamePauseScope.isPaused est true.
// ─────────────────────────────────────────────────────────────────────────────
class _TickingConfirmButton extends StatefulWidget {
  final int autoCloseSeconds;
  final String labelPrefix;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final VoidCallback? onTimeout;
  final DialogMetrics metrics;

  const _TickingConfirmButton({
    required this.autoCloseSeconds,
    required this.labelPrefix,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.onTimeout,
    required this.metrics,
  });

  @override
  State<_TickingConfirmButton> createState() => _TickingConfirmButtonState();
}

class _TickingConfirmButtonState extends State<_TickingConfirmButton>
    with SingleTickerProviderStateMixin {
  late int _remaining;
  Ticker? _ticker;
  late DateTime _startTime;
  bool _isPaused = false;

  /// Durée cumulée passée en pause
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStart;

  @override
  void initState() {
    super.initState();
    _remaining = widget.autoCloseSeconds;
    _startTime = DateTime.now();
    if (_remaining > 0) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.dispose();
    _ticker = createTicker((_) {
      if (!mounted || _isPaused) return;
      final elapsed = DateTime.now().difference(_startTime) - _pausedDuration;
      final newRemaining = (widget.autoCloseSeconds - elapsed.inSeconds)
          .clamp(0, widget.autoCloseSeconds);
      if (newRemaining != _remaining) {
        setState(() => _remaining = newRemaining);
        if (_remaining <= 0) {
          _ticker?.stop();
          if (widget.onTimeout != null) {
            widget.onTimeout!();
          } else {
            widget.onPressed();
          }
        }
      }
    });
    _ticker!.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paused = GamePauseScope.of(context);
    if (paused != _isPaused) {
      _isPaused = paused;
      if (_isPaused) {
        _pauseStart = DateTime.now();
        _ticker?.stop();
      } else {
        if (_pauseStart != null) {
          _pausedDuration += DateTime.now().difference(_pauseStart!);
          _pauseStart = null;
        }
        if (_remaining > 0) {
          _startTicker();
        }
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _remaining > 0
        ? "${widget.labelPrefix} ($_remaining s)"
        : widget.labelPrefix;
    return PowerDialogWidgets.confirmButton(
      label: label,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      onPressed: widget.onPressed,
      metrics: widget.metrics,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TickingSkipButton : bouton "Passer" avec décompte auto-close
// Gèle automatiquement le décompte quand GamePauseScope.isPaused est true.
// ─────────────────────────────────────────────────────────────────────────────
class _TickingSkipButton extends StatefulWidget {
  final int autoCloseSeconds;
  final String labelPrefix;
  final VoidCallback onPressed;
  final VoidCallback? onTimeout;
  final DialogMetrics metrics;

  const _TickingSkipButton({
    required this.autoCloseSeconds,
    required this.labelPrefix,
    required this.onPressed,
    this.onTimeout,
    required this.metrics,
  });

  @override
  State<_TickingSkipButton> createState() => _TickingSkipButtonState();
}

class _TickingSkipButtonState extends State<_TickingSkipButton>
    with SingleTickerProviderStateMixin {
  late int _remaining;
  Ticker? _ticker;
  late DateTime _startTime;
  bool _isPaused = false;

  /// Durée cumulée passée en pause
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStart;

  @override
  void initState() {
    super.initState();
    _remaining = widget.autoCloseSeconds;
    _startTime = DateTime.now();
    if (_remaining > 0) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.dispose();
    _ticker = createTicker((_) {
      if (!mounted || _isPaused) return;
      final elapsed = DateTime.now().difference(_startTime) - _pausedDuration;
      final newRemaining = (widget.autoCloseSeconds - elapsed.inSeconds)
          .clamp(0, widget.autoCloseSeconds);
      if (newRemaining != _remaining) {
        setState(() => _remaining = newRemaining);
        if (_remaining <= 0) {
          _ticker?.stop();
          if (widget.onTimeout != null) {
            widget.onTimeout!();
          } else {
            widget.onPressed();
          }
        }
      }
    });
    _ticker!.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paused = GamePauseScope.of(context);
    if (paused != _isPaused) {
      _isPaused = paused;
      if (_isPaused) {
        _pauseStart = DateTime.now();
        _ticker?.stop();
      } else {
        if (_pauseStart != null) {
          _pausedDuration += DateTime.now().difference(_pauseStart!);
          _pauseStart = null;
        }
        if (_remaining > 0) {
          _startTicker();
        }
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _remaining > 0
        ? "${widget.labelPrefix} ($_remaining s)"
        : widget.labelPrefix;
    return PowerDialogWidgets.skipButton(
      label: label,
      onPressed: widget.onPressed,
      metrics: widget.metrics,
    );
  }
}

/// Barre de progression du temps restant pour utiliser un pouvoir spécial.
/// Affichée en haut de chaque dialogue de pouvoir en mode multijoueur.
/// Lit GamePauseScope pour se geler automatiquement pendant la pause.
class PowerTimerBar extends StatefulWidget {
  final int startTimeMs;
  final int totalMs;

  const PowerTimerBar({
    super.key,
    required this.startTimeMs,
    required this.totalMs,
  });

  @override
  State<PowerTimerBar> createState() => _PowerTimerBarState();
}

class _PowerTimerBarState extends State<PowerTimerBar>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _progress = 1.0;

  /// Progrès gelé au moment de la pause, pour éviter de bouger pendant la pause
  double? _frozenProgress;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _updateProgress();
    _startTicker();
  }

  void _startTicker() {
    _ticker?.dispose();
    _ticker = createTicker((_) => _updateProgress());
    _ticker!.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paused = GamePauseScope.of(context);
    if (paused != _isPaused) {
      _isPaused = paused;
      if (_isPaused) {
        _frozenProgress = _progress;
        _ticker?.stop();
      } else {
        _frozenProgress = null;
        _updateProgress();
        _startTicker();
      }
    }
  }

  @override
  void didUpdateWidget(PowerTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si les paramètres changent (ex: nouveau startTimeMs après reconnexion),
    // recalculer immédiatement
    if (oldWidget.startTimeMs != widget.startTimeMs ||
        oldWidget.totalMs != widget.totalMs) {
      _frozenProgress = null;
      _updateProgress();
    }
  }

  void _updateProgress() {
    if (!mounted) return;
    if (_isPaused) return;
    final totalMs = widget.totalMs;
    if (totalMs <= 0 || widget.startTimeMs <= 0) {
      // Données invalides — afficher la barre pleine au lieu de crasher
      if (_progress != 1.0) {
        setState(() => _progress = 1.0);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - widget.startTimeMs;
    // Protéger contre les timestamps dans le futur (désync d'horloge)
    final clampedElapsed = elapsed.clamp(0, totalMs);
    final remaining = totalMs - clampedElapsed;
    final p = (remaining / totalMs).clamp(0.0, 1.0);
    if (p != _progress) {
      setState(() => _progress = p);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayProgress = _frozenProgress ?? _progress;
    final totalMs = widget.totalMs;
    // Éviter l'affichage de secondes négatives ou incohérentes
    final seconds = totalMs > 0
        ? (totalMs * displayProgress / 1000)
            .ceil()
            .clamp(0, totalMs ~/ 1000 + 1)
        : 0;
    final color = Color.lerp(Colors.red, Colors.amber, displayProgress)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Temps restant : ${seconds}s",
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: displayProgress,
            backgroundColor: Colors.black26,
            color: color,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
