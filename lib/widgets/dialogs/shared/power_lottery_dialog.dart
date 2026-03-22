import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../../models/game_sub_states.dart';
import '../../../utils/ui_constants.dart';
import '../responsive_dialog.dart';
import 'power_dialog_widgets.dart';

/// Dialog de loterie pour déterminer l'ordre d'utilisation des pouvoirs
/// suite à des matchs pendant la phase de réaction.
///
/// Chaque joueur avec un pouvoir en attente appuie sur un bouton pour
/// révéler son numéro d'ordre. Au bout de 10 secondes, les numéros
/// non révélés sont assignés automatiquement.
class PowerLotteryDialog extends StatefulWidget {
  final List<PendingMatchPower> pendingPowers;
  final String? localPlayerId;
  final VoidCallback onComplete;
  final DialogMetrics metrics;

  const PowerLotteryDialog({
    super.key,
    required this.pendingPowers,
    this.localPlayerId,
    required this.onComplete,
    required this.metrics,
  });

  /// Affiche le dialog de loterie
  static void show(
    BuildContext context, {
    required List<PendingMatchPower> pendingPowers,
    String? localPlayerId,
    required VoidCallback onComplete,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (dialogContext, metrics) {
          return PowerLotteryDialog(
            pendingPowers: pendingPowers,
            localPlayerId: localPlayerId,
            onComplete: onComplete,
            metrics: metrics,
          );
        },
      ),
    );
  }

  @override
  State<PowerLotteryDialog> createState() => _PowerLotteryDialogState();
}

class _PowerLotteryDialogState extends State<PowerLotteryDialog>
    with SingleTickerProviderStateMixin {
  static const _timeoutSeconds = 10;
  static const _postRevealDelayMs = 1500;

  final Set<String> _revealedPlayerIds = {};
  late final AnimationController _timerController;
  Timer? _autoRevealTimer;
  bool _allRevealed = false;
  bool _closing = false;

  final Map<String, Timer> _botTimers = {};

  DialogMetrics get metrics => widget.metrics;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _timeoutSeconds),
    );
    _timerController.forward();

    _autoRevealTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      _revealAll();
    });

    final rng = Random();
    for (final power in widget.pendingPowers) {
      if (power.playerId != widget.localPlayerId) {
        final delayMs = 1000 + rng.nextInt(4000);
        _botTimers[power.playerId] = Timer(
          Duration(milliseconds: delayMs),
          () => _revealPlayer(power.playerId),
        );
      }
    }
  }

  @override
  void dispose() {
    _timerController.dispose();
    _autoRevealTimer?.cancel();
    for (final timer in _botTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _revealPlayer(String playerId) {
    if (_revealedPlayerIds.contains(playerId) || _closing) return;
    setState(() {
      _revealedPlayerIds.add(playerId);
    });
    _checkAllRevealed();
  }

  void _revealAll() {
    if (_closing) return;
    setState(() {
      for (final power in widget.pendingPowers) {
        _revealedPlayerIds.add(power.playerId);
      }
      _allRevealed = true;
    });
    _timerController.stop();
    _scheduleClose();
  }

  void _checkAllRevealed() {
    if (_revealedPlayerIds.length >= widget.pendingPowers.length) {
      _autoRevealTimer?.cancel();
      _timerController.stop();
      setState(() => _allRevealed = true);
      _scheduleClose();
    }
  }

  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    Future.delayed(const Duration(milliseconds: _postRevealDelayMs), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onComplete();
    });
  }

  void _onLocalPlayerTap() {
    if (widget.localPlayerId == null) return;
    _revealPlayer(widget.localPlayerId!);
  }

  String _powerDescription(String cardValue) {
    return switch (cardValue) {
      '7' => 'Regarder une de ses cartes',
      '10' => 'Espionner une carte adverse',
      'V' => 'Échanger une carte',
      'JOKER' => 'Mélanger une main',
      _ => 'Pouvoir inconnu',
    };
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<PendingMatchPower>.from(widget.pendingPowers);
    if (_allRevealed) {
      sorted
          .sort((a, b) => (a.drawNumber ?? 0).compareTo(b.drawNumber ?? 0));
    }

    final localCanTap = widget.localPlayerId != null &&
        !_revealedPlayerIds.contains(widget.localPlayerId) &&
        !_closing;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimerBar(),
          SizedBox(height: metrics.space(12)),
          PowerDialogWidgets.dialogHeader(
            icon: Icons.casino,
            iconColor: Colors.amber,
            title: "TIRAGE AU SORT",
            titleColor: Colors.amber,
            subtitle: _allRevealed
                ? "Le n°1 utilise son pouvoir en premier"
                : "${widget.pendingPowers.length} joueurs ont matché une carte pouvoir.\nTirez votre numéro pour déterminer l'ordre !",
            metrics: metrics,
          ),
          SizedBox(height: metrics.space(16)),
          ...sorted.map((power) => _buildPlayerRow(power)),
          if (localCanTap) ...[
            SizedBox(height: metrics.space(16)),
            PowerDialogWidgets.confirmButton(
              label: "TIRER MON NUMÉRO",
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
              onPressed: _onLocalPlayerTap,
              metrics: metrics,
            ),
          ],
          SizedBox(height: metrics.space(8)),
        ],
      ),
    );
  }

  Widget _buildTimerBar() {
    return AnimatedBuilder(
      animation: _timerController,
      builder: (context, child) {
        final remaining = _timeoutSeconds * (1.0 - _timerController.value);
        final seconds = remaining.ceil().clamp(0, _timeoutSeconds);
        final progress = 1.0 - _timerController.value;
        final color = Color.lerp(Colors.red, Colors.amber, progress)!;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_allRevealed)
              Text(
                "Temps restant : ${seconds}s",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: metrics.font(12),
                ),
              ),
            SizedBox(height: metrics.space(4)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _allRevealed ? 0.0 : progress,
                backgroundColor: Colors.black26,
                color: color,
                minHeight: 4,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayerRow(PendingMatchPower power) {
    final isRevealed = _revealedPlayerIds.contains(power.playerId);
    final isLocal = power.playerId == widget.localPlayerId;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.space(4)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.space(14),
          vertical: metrics.space(10),
        ),
        decoration: BoxDecoration(
          color: isRevealed
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRevealed
                ? Colors.amber.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: isRevealed
                  ? _buildNumber(power.drawNumber ?? 0)
                  : _buildQuestionMark(),
            ),
            SizedBox(width: metrics.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLocal ? "Vous" : power.playerName,
                    style: TextStyle(
                      color:
                          isLocal ? Colors.amber : AppColors.textPrimary,
                      fontSize: metrics.font(15),
                      fontWeight:
                          isLocal ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: metrics.space(2)),
                  Text(
                    _powerDescription(power.card.value),
                    style: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: metrics.font(11),
                    ),
                  ),
                ],
              ),
            ),
            _buildPowerBadge(power.card.value),
          ],
        ),
      ),
    );
  }

  Widget _buildNumber(int number) {
    final size = metrics.size(36);
    return Container(
      key: ValueKey('num_$number'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Colors.amber.shade700, Colors.orange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          "$number",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: metrics.font(18),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionMark() {
    final size = metrics.size(36);
    return Container(
      key: const ValueKey('question'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          "?",
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: metrics.font(18),
          ),
        ),
      ),
    );
  }

  Widget _buildPowerBadge(String cardValue) {
    final (label, icon, color) = switch (cardValue) {
      '7' => ('7', Icons.visibility, Colors.blue),
      '10' => ('10', Icons.search, Colors.purple),
      'V' => ('V', Icons.swap_horiz, Colors.teal),
      'JOKER' => ('J', Icons.shuffle, Colors.red),
      _ => ('?', Icons.help, Colors.grey),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.space(8),
        vertical: metrics.space(4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: metrics.size(14)),
          SizedBox(width: metrics.space(4)),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: metrics.font(12),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
