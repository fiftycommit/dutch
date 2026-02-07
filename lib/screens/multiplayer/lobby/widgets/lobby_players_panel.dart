import 'package:flutter/material.dart';
import '../../../../providers/multiplayer_game_provider.dart';
import '../../../../utils/ui_constants.dart';

class LobbyPlayersPanel extends StatelessWidget {
  final MultiplayerGameProvider provider;
  final int connectedHumans;
  final int maxPlayers;
  final double uiScale;

  const LobbyPlayersPanel({
    super.key,
    required this.provider,
    required this.connectedHumans,
    required this.maxPlayers,
    required this.uiScale,
  });

  double _f(double size) => size * uiScale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasScores = provider.cumulativeScores.isNotEmpty;
    final size = MediaQuery.of(context).size;
    final isCompactLandscape = size.height < 400 && size.width > size.height;

    return Container(
      padding: EdgeInsets.all(_f(isCompactLandscape ? 8 : 12)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_f(isCompactLandscape ? 12 : 16)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: _f(1.2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 50) {
            return const Center(
              child: Text('...', style: TextStyle(color: AppColors.textDisabled)),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colors, hasScores, isCompactLandscape),
              SizedBox(height: _f(isCompactLandscape ? 6 : 10)),
              Expanded(
                child: provider.playersInLobby.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: provider.playersInLobby.length,
                        itemBuilder: (context, index) {
                          return _buildPlayerItem(
                            context, index, colors, isCompactLandscape);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors, bool hasScores, bool isCompactLandscape) {
    return Row(
      children: [
        Icon(Icons.people, size: _f(isCompactLandscape ? 16 : 20), color: Colors.white),
        SizedBox(width: _f(6)),
        Text(
          'Joueurs ($connectedHumans/$maxPlayers)',
          style: TextStyle(
            fontSize: _f(isCompactLandscape ? 13 : 16),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (hasScores && !isCompactLandscape) ...[
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: _f(8), vertical: _f(3)),
            decoration: BoxDecoration(
              color: colors.tertiary.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(_f(12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events,
                    size: _f(14), color: Colors.white),
                SizedBox(width: _f(4)),
                Text(
                  'Classement',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _f(11),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlayerItem(
    BuildContext context, int index, ColorScheme colors, bool isCompactLandscape,
  ) {
    final player = provider.playersInLobby[index];
    final isYou = (player['clientId'] != null &&
            player['clientId'] == provider.clientId) ||
        (player['id'] == provider.playerId);
    final isHost = provider.hostPlayerId != null &&
        player['id'] == provider.hostPlayerId;
    final presence =
        provider.presenceByClientId[player['clientId']] ??
            provider.presenceById[player['id']];
    final isSpectator = presence?['isSpectator'] == true;
    final isReady = presence?['ready'] == true ||
        player['ready'] == true;

    final playerClientId = player['clientId']?.toString();
    final playerScore = _getPlayerScore(playerClientId);
    final playerRank = _getPlayerRank(playerClientId);

    if (isCompactLandscape) {
      return _buildCompactPlayerItem(
        context, player, colors, isYou, isHost, isReady, isSpectator, presence);
    }

    return _buildNormalPlayerItem(
      context, player, colors, isYou, isHost, isReady, isSpectator,
      presence, playerScore, playerRank);
  }

  Widget _buildCompactPlayerItem(
    BuildContext context,
    Map<String, dynamic> player,
    ColorScheme colors,
    bool isYou, bool isHost, bool isReady, bool isSpectator,
    Map<String, dynamic>? presence,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: _f(4)),
      padding: EdgeInsets.symmetric(
        horizontal: _f(8),
        vertical: _f(4),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(_f(8)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _f(12),
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            child: Text(
              (player['name'] ?? 'J')[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: _f(10),
              ),
            ),
          ),
          SizedBox(width: _f(6)),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player['name'] ?? 'Joueur',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _f(11),
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (isYou)
                  _buildMiniTag(colors.primary, 'Vous'),
                if (isHost)
                  _buildMiniTag(colors.secondary, 'Hote'),
              ],
            ),
          ),
          if (isReady && !isSpectator)
            Icon(Icons.check_circle, color: colors.tertiary, size: _f(14)),
          SizedBox(width: _f(4)),
          _presenceDot(presence),
        ],
      ),
    );
  }

  Widget _buildNormalPlayerItem(
    BuildContext context,
    Map<String, dynamic> player,
    ColorScheme colors,
    bool isYou, bool isHost, bool isReady, bool isSpectator,
    Map<String, dynamic>? presence,
    int? playerScore, int? playerRank,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: _f(8)),
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_f(12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _f(12),
          vertical: _f(10),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: _f(18),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: Text(
                    (player['name'] ?? 'J')[0].toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _f(14),
                    ),
                  ),
                ),
                if (playerRank != null && playerRank <= 3)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: EdgeInsets.all(_f(3)),
                      decoration: BoxDecoration(
                        color: _getRankColor(playerRank),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: _f(1.5),
                        ),
                      ),
                      child: Text(
                        '$playerRank',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _f(9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: _f(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          player['name'] ?? 'Joueur',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: _f(14),
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (isYou)
                        _buildMiniTag(colors.primary, 'Vous'),
                      if (isHost)
                        _buildMiniTag(colors.secondary, 'Hote'),
                    ],
                  ),
                  SizedBox(height: _f(2)),
                  Row(
                    children: [
                      Text(
                        _presenceLabel(presence, provider.roomStatus),
                        style: TextStyle(
                          fontSize: _f(11),
                          color: Colors.grey[600],
                        ),
                      ),
                      if (playerScore != null) ...[
                        SizedBox(width: _f(8)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: _f(6),
                            vertical: _f(1),
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(_f(8)),
                          ),
                          child: Text(
                            '$playerScore pts',
                            style: TextStyle(
                              fontSize: _f(10),
                              fontWeight: FontWeight.bold,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isReady && !isSpectator)
              Icon(Icons.check_circle, color: colors.tertiary, size: _f(20)),
            if (isSpectator)
              Icon(Icons.visibility, color: Colors.blueGrey, size: _f(20)),
            SizedBox(width: _f(4)),
            _presenceDot(presence),
            if (provider.isHost && !isYou) ...[
              SizedBox(width: _f(8)),
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    color: Colors.orange, size: _f(20)),
                tooltip: 'Exclure (peut revenir)',
                onPressed: () => _confirmKick(context, player),
              ),
              IconButton(
                icon: Icon(Icons.block,
                    color: colors.error, size: _f(20)),
                tooltip: 'Bannir (définitif)',
                onPressed: () => _confirmBan(context, player, colors),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmKick(BuildContext context, Map<String, dynamic> player) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exclure ce joueur ?'),
        content: Text(
            '${player['name']} sera exclu mais pourra revenir dans la room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Exclure'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final clientId = player['clientId'] as String?;
      if (clientId != null) {
        await provider.kickPlayer(clientId);
      }
    }
  }

  Future<void> _confirmBan(BuildContext context, Map<String, dynamic> player, ColorScheme colors) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bannir ce joueur ?'),
        content: Text(
            '${player['name']} sera banni et ne pourra PLUS rejoindre cette room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bannir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final clientId = player['clientId'] as String?;
      if (clientId != null) {
        await provider.banPlayer(clientId);
      }
    }
  }

  int? _getPlayerScore(String? clientId) {
    if (clientId == null || provider.cumulativeScores.isEmpty) return null;
    for (final entry in provider.cumulativeScores) {
      if (entry['clientId'] == clientId) {
        return entry['score'] as int?;
      }
    }
    return null;
  }

  int? _getPlayerRank(String? clientId) {
    if (clientId == null || provider.cumulativeScores.isEmpty) return null;
    for (int i = 0; i < provider.cumulativeScores.length; i++) {
      if (provider.cumulativeScores[i]['clientId'] == clientId) {
        return i + 1;
      }
    }
    return null;
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return Colors.grey;
    }
  }

  Widget _buildMiniTag(Color color, String text) {
    return Container(
      margin: EdgeInsets.only(left: _f(6)),
      padding: EdgeInsets.symmetric(horizontal: _f(6), vertical: _f(2)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_f(10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: _f(9),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _presenceLabel(Map<String, dynamic>? presence, String roomStatus) {
    if (presence == null) return 'Statut inconnu';
    if (presence['isSpectator'] == true) return 'Spectateur';
    if (presence['connected'] != true) return 'Deconnecte';
    if (presence['focused'] != true) return 'En arriere-plan';
    if (roomStatus == 'playing') return 'En jeu';
    return presence['ready'] == true ? 'Pret' : 'En ligne';
  }

  Widget _presenceDot(Map<String, dynamic>? presence) {
    Color color = Colors.grey;
    if (presence != null) {
      final isSpectator = presence['isSpectator'] == true;
      final connected = presence['connected'] == true;
      final focused = presence['focused'] == true;

      if (isSpectator) {
        color = Colors.blueGrey;
      } else if (!connected) {
        color = Colors.red;
      } else if (!focused) {
        color = Colors.orange;
      } else if (presence['ready'] == true) {
        color = Colors.teal;
      } else {
        color = Colors.green;
      }
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
