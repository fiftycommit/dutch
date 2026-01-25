import 'package:flutter/material.dart';
import '../models/player.dart';
import '../utils/screen_utils.dart';

class PlayerAvatar extends StatelessWidget {
  final Player player;
  final bool isActive; // Si c'est le tour du joueur
  final bool showName;
  final double size;
  final bool compactMode; // Mode compact: juste le badge avec emoji + nom

  const PlayerAvatar({
    super.key,
    required this.player,
    this.isActive = false,
    this.showName = true,
    this.size = 60.0,
    this.compactMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Mode compact: juste un badge avec emoji + nom qui s'illumine
    if (compactMode) {
      return _buildCompactBadge(context);
    }
    
    // Mode classique avec avatar circulaire (pour les bots)
    return _buildClassicAvatar(context);
  }
  
  /// Badge compact: emoji + nom dans une seule bande
  Widget _buildCompactBadge(BuildContext context) {
    final badgeHeight = ScreenUtils.scale(context, size * 0.6);
    final fontSize = ScreenUtils.scaleFont(context, size * 0.35);
    final emojiSize = ScreenUtils.scaleFont(context, size * 0.4);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: ScreenUtils.spacing(context, 10),
        vertical: ScreenUtils.spacing(context, 4),
      ),
      constraints: BoxConstraints(minHeight: badgeHeight),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                colors: [Colors.amber.shade400, Colors.amber.shade600],
              )
            : null,
        color: isActive ? null : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(
          ScreenUtils.borderRadius(context, 20),
        ),
        border: Border.all(
          color: isActive ? Colors.amber : Colors.white24,
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            player.displayAvatar,
            style: TextStyle(fontSize: emojiSize),
          ),
          SizedBox(width: ScreenUtils.spacing(context, 4)),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              player.displayName,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Avatar classique avec cercle (pour les bots sur les côtés)
  Widget _buildClassicAvatar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar circulaire avec indicateur de tour
        Container(
          width: ScreenUtils.scale(context, size),
          height: ScreenUtils.scale(context, size),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [
                      Colors.amber.shade400,
                      Colors.amber.shade700,
                    ]
                  : [
                      const Color(0xFF2d5f3e),
                      const Color(0xFF1a472a),
                    ],
            ),
            border: Border.all(
              color: isActive ? Colors.amber : Colors.white24,
              width: isActive ? 3 : 2,
            ),
            boxShadow: isActive
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
              player.displayAvatar,
              style: TextStyle(
                fontSize: ScreenUtils.scaleFont(context, size * 0.5),
              ),
            ),
          ),
        ),

        // Nom du joueur
        if (showName) ...[
          SizedBox(height: ScreenUtils.spacing(context, 4)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenUtils.spacing(context, 6),
              vertical: ScreenUtils.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.amber.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(
                ScreenUtils.borderRadius(context, 10),
              ),
              border:
                  isActive ? Border.all(color: Colors.amber, width: 1) : null,
            ),
            child: Text(
              player.displayName,
              style: TextStyle(
                color: Colors.white,
                fontSize: ScreenUtils.scaleFont(context, 10),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
