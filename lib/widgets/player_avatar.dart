import 'package:flutter/material.dart';
import '../models/player.dart';
import '../utils/screen_utils.dart';

class PlayerAvatar extends StatelessWidget {
  final Player player;
  final bool isActive; // Si c'est le tour du joueur
  final bool showName;
  final double size;

  const PlayerAvatar({
    super.key,
    required this.player,
    this.isActive = false,
    this.showName = true,
    this.size = 60.0,
  });

  @override
  Widget build(BuildContext context) {
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
