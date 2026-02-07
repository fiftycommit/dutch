import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../providers/multiplayer_game_provider.dart';
import '../../../../models/game_state.dart';
import '../../../../utils/ui_constants.dart';

class LobbyRoomCodeCard extends StatelessWidget {
  final MultiplayerGameProvider provider;
  final double uiScale;

  const LobbyRoomCodeCard({
    super.key,
    required this.provider,
    required this.uiScale,
  });

  double _f(double size) => size * uiScale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('room_code_card'),
      margin: EdgeInsets.symmetric(vertical: _f(4)),
      padding: EdgeInsets.symmetric(horizontal: _f(16), vertical: _f(10)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(_f(12)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: _f(1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Code',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: _f(11),
            ),
          ),
          SizedBox(width: _f(12)),
          Text(
            provider.roomCode ?? '------',
            style: TextStyle(
              color: Colors.white,
              fontSize: _f(22),
              fontWeight: FontWeight.bold,
              letterSpacing: _f(3),
            ),
          ),
          SizedBox(width: _f(8)),
          IconButton(
            icon: Icon(Icons.copy, color: AppColors.textSecondary, size: _f(18)),
            tooltip: 'Copier',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              final code = provider.roomCode;
              if (code == null) return;
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Code copié'),
                  backgroundColor: colors.primaryContainer,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class LobbyPublicBadge extends StatelessWidget {
  final double uiScale;

  const LobbyPublicBadge({super.key, required this.uiScale});

  double _f(double size) => size * uiScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: _f(8)),
      padding: EdgeInsets.all(_f(16)),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(_f(16)),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.5),
          width: _f(1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.public,
            color: Colors.green.shade300,
            size: _f(24),
          ),
          SizedBox(width: _f(12)),
          Text(
            'Salon Public',
            style: TextStyle(
              color: Colors.green.shade300,
              fontSize: _f(18),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class LobbySettingsRow extends StatelessWidget {
  final MultiplayerGameProvider provider;
  final int minPlayers;
  final int maxPlayers;
  final double uiScale;

  const LobbySettingsRow({
    super.key,
    required this.provider,
    required this.minPlayers,
    required this.maxPlayers,
    required this.uiScale,
  });

  double _f(double size) => size * uiScale;

  @override
  Widget build(BuildContext context) {
    final isQuickMode = provider.roomSettings!.gameMode == GameMode.quick;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: _f(8)),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: _f(8),
        runSpacing: _f(8),
        children: [
          if (provider.isHost)
            _buildGameModeSelector(context, isQuickMode)
          else
            _buildSettingChip(
              label: isQuickMode ? 'Rapide' : 'Tournoi',
              icon: Icons.flag,
            ),
          _buildSettingChip(label: 'Min $minPlayers', icon: Icons.people),
          _buildSettingChip(label: 'Max $maxPlayers', icon: Icons.groups),
        ],
      ),
    );
  }

  Widget _buildGameModeSelector(BuildContext context, bool isQuickMode) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _f(4), vertical: _f(2)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(_f(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            label: 'Rapide',
            icon: Icons.bolt,
            isSelected: isQuickMode,
            onTap: () => provider.setGameMode(GameMode.quick),
          ),
          _buildModeButton(
            label: 'Tournoi',
            icon: Icons.emoji_events,
            isSelected: !isQuickMode,
            onTap: () => provider.setGameMode(GameMode.tournament),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: _f(10), vertical: _f(6)),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_f(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: _f(14),
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            SizedBox(width: _f(4)),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: _f(11),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingChip({required String label, required IconData icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _f(10), vertical: _f(6)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(_f(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _f(12), color: Colors.white),
          SizedBox(width: _f(4)),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: _f(11),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
