import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/service_locator.dart';
import '../../../core/interfaces/i_haptic_service.dart';
import '../../../models/player.dart';
import '../../../utils/ui_constants.dart';
import '../responsive_dialog.dart';
import 'power_dialog_widgets.dart';

/// Widgets de sélection partagés pour les pouvoirs spéciaux
/// Principe GRASP: Pure Fabrication - Widgets de sélection réutilisables
class PowerSelectionWidgets {
  static String _cardCountLabel(int count) =>
      '$count carte${count > 1 ? 's' : ''}';

  /// Construit une sélection de joueurs sous forme de boutons
  static Widget buildPlayerSelection({
    required List<Player> players,
    required Player? selectedPlayer,
    required Color baseColor,
    required Function(Player) onSelect,
    required String Function(Player) getLabel,
    required DialogMetrics metrics,
    Player? excludePlayer,
  }) {
    final filteredPlayers = excludePlayer != null
        ? players.where((p) => p.id != excludePlayer.id).toList()
        : players;

    return Wrap(
      spacing: metrics.space(8),
      runSpacing: metrics.space(8),
      children: filteredPlayers.map((p) {
        final isSelected = selectedPlayer?.id == p.id;
        return GestureDetector(
          onTap: () => onSelect(p),
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
              '${getLabel(p)} (${_cardCountLabel(p.hand.length)})',
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.font(12),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Construit une grille de sélection de cartes
  static Widget buildCardSelection({
    required int cardCount,
    required int? selectedIndex,
    required Color borderColor,
    required Function(int) onSelect,
    required DialogMetrics metrics,
    int maxColumns = 6,
    double maxHeightFraction = 0.18,
  }) {
    final cardBorderWidth = math.max(1.0, metrics.scale * 1.5);
    final cardWidth = PowerDialogWidgets.cardWidthForGrid(
      metrics,
      columns: maxColumns,
      maxHeightFraction: maxHeightFraction,
    );

    return Wrap(
      spacing: metrics.space(8),
      runSpacing: metrics.space(8),
      children: List.generate(cardCount, (index) {
        final isSelected = selectedIndex == index;
        return GestureDetector(
          onTap: () => onSelect(index),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Colors.amber : borderColor,
                width: isSelected ? cardBorderWidth * 2 : cardBorderWidth,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: PowerDialogWidgets.scaledCard(
              width: cardWidth,
              isRevealed: false,
            ),
          ),
        );
      }),
    );
  }

  /// Construit le contenu complet du dialog de swap (Valet)
  static Widget buildSwapDialogContent({
    required List<Player> allPlayers,
    required Player? player1,
    required int? card1,
    required Player? player2,
    required int? card2,
    required Function(Player) onSelectPlayer1,
    required Function(int) onSelectCard1,
    required Function(Player) onSelectPlayer2,
    required Function(int) onSelectCard2,
    required VoidCallback onCancel,
    required VoidCallback? onConfirm,
    required String Function(Player) getPlayerLabel,
    required String Function(Player) getCardLabel,
    required DialogMetrics metrics,
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
    Widget? powerTimerBar,
  }) {
    final spacing = metrics.space(8);
    final sectionSpacing = metrics.space(16);
    final titleSize = metrics.font(14);
    final buttonSize = metrics.font(16);

    return SingleChildScrollView(
      child: SizedBox(
        width: metrics.contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (powerTimerBar != null) powerTimerBar,
            // Joueur A
            Text("1️⃣ Joueur A :",
                style: TextStyle(color: Colors.white, fontSize: titleSize)),
            SizedBox(height: spacing),
            buildPlayerSelection(
              players: allPlayers,
              selectedPlayer: player1,
              baseColor: Colors.blue.shade900,
              onSelect: onSelectPlayer1,
              getLabel: getPlayerLabel,
              metrics: metrics,
            ),

            // Carte de A
            if (player1 != null) ...[
              SizedBox(height: sectionSpacing),
              Text("2️⃣ Carte de ${getCardLabel(player1)} :",
                  style: TextStyle(color: Colors.white, fontSize: titleSize)),
              SizedBox(height: spacing),
              buildCardSelection(
                cardCount: player1.hand.length,
                selectedIndex: card1,
                borderColor: Colors.white30,
                onSelect: onSelectCard1,
                metrics: metrics,
              ),
            ],

            // Joueur B
            SizedBox(height: sectionSpacing),
            Text("3️⃣ Joueur B :",
                style: TextStyle(color: Colors.white, fontSize: titleSize)),
            SizedBox(height: spacing),
            buildPlayerSelection(
              players: allPlayers,
              selectedPlayer: player2,
              baseColor: Colors.red.shade900,
              onSelect: onSelectPlayer2,
              getLabel: getPlayerLabel,
              metrics: metrics,
              excludePlayer: player1,
            ),

            // Carte de B
            if (player2 != null) ...[
              SizedBox(height: sectionSpacing),
              Text("4️⃣ Carte de ${getCardLabel(player2)} :",
                  style: TextStyle(color: Colors.white, fontSize: titleSize)),
              SizedBox(height: spacing),
              buildCardSelection(
                cardCount: player2.hand.length,
                selectedIndex: card2,
                borderColor: Colors.white30,
                onSelect: onSelectCard2,
                metrics: metrics,
              ),
            ],

            // Boutons
            SizedBox(height: sectionSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PowerDialogWidgets.tickingSkipButton(
                  labelPrefix: "ANNULER",
                  onPressed: onCancel,
                  metrics: metrics,
                  autoCloseSeconds: autoCloseSeconds,
                  onTimeout: onTimeout,
                ),
                ElevatedButton(
                  onPressed: onConfirm == null
                      ? null
                      : () {
                          ServiceLocator().get<IHapticService>().buttonTap();
                          onConfirm();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: EdgeInsets.symmetric(
                        horizontal: metrics.space(20),
                        vertical: metrics.space(12)),
                  ),
                  child:
                      Text("ÉCHANGER", style: TextStyle(fontSize: buttonSize)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Construit un dialog d'introduction de pouvoir (Valet, Joker)
  static Widget buildPowerIntroDialog({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
    required DialogMetrics metrics,
    bool fullWidthButton = false,
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
    Widget? powerTimerBar,
  }) {
    final gapS = metrics.space(8);
    final gapM = metrics.space(16);
    final iconSize = metrics.size(40);
    final titleSize = metrics.font(20);
    final bodySize = metrics.font(14);
    final buttonSize = (fullWidthButton || buttonText.contains('\n'))
        ? metrics.font(14)
        : metrics.font(16);

    return SingleChildScrollView(
      child: SizedBox(
        width: metrics.contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (powerTimerBar != null) powerTimerBar,
            Icon(icon, color: color, size: iconSize),
            SizedBox(height: gapS),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: gapS),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: bodySize),
            ),
            SizedBox(height: gapM),
            SizedBox(
              width: fullWidthButton ? metrics.contentWidth : null,
              height: fullWidthButton ? metrics.space(64) : null,
              child: ElevatedButton(
                onPressed: () {
                  ServiceLocator().get<IHapticService>().buttonTap();
                  onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                  padding: fullWidthButton
                      ? null
                      : EdgeInsets.symmetric(
                          horizontal: metrics.space(20),
                          vertical: metrics.space(12),
                        ),
                ),
                child: Text(
                  buttonText,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: buttonSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(height: gapM),
            PowerDialogWidgets.tickingSkipButton(
              labelPrefix: "ANNULER",
              onPressed: onCancel,
              metrics: metrics,
              autoCloseSeconds: autoCloseSeconds,
              onTimeout: onTimeout,
            ),
          ],
        ),
      ),
    );
  }

  /// Construit un dialog de sélection de joueur (Joker)
  static Widget buildPlayerSelectionDialog({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required List<Player> players,
    required Function(Player, int) onSelectPlayer,
    required VoidCallback onCancel,
    required String Function(Player) getLabel,
    required bool Function(Player) isMe,
    required DialogMetrics metrics,
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
    Widget? powerTimerBar,
  }) {
    final gapS = metrics.space(8);
    final gapM = metrics.space(16);
    final iconSize = metrics.size(40);
    final titleSize = metrics.font(20);
    final bodySize = metrics.font(14);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (powerTimerBar != null) powerTimerBar,
        Icon(icon, color: color, size: iconSize),
        SizedBox(height: gapS),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: gapS),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize),
        ),
        SizedBox(height: gapM),
        buildJokerPlayerSelection(
          players: players,
          onSelect: onSelectPlayer,
          getLabel: getLabel,
          isMe: isMe,
          metrics: metrics,
        ),
        SizedBox(height: gapM),
        PowerDialogWidgets.tickingSkipButton(
          labelPrefix: "ANNULER",
          onPressed: onCancel,
          metrics: metrics,
          autoCloseSeconds: autoCloseSeconds,
          onTimeout: onTimeout,
        ),
      ],
    );
  }

  /// Construit une liste de boutons de sélection de joueurs pour le Joker
  static Widget buildJokerPlayerSelection({
    required List<Player> players,
    required Function(Player, int) onSelect,
    required String Function(Player) getLabel,
    required bool Function(Player) isMe,
    required DialogMetrics metrics,
  }) {
    return Wrap(
      spacing: metrics.space(12),
      runSpacing: metrics.space(8),
      alignment: WrapAlignment.center,
      children: players.asMap().entries.map((entry) {
        final index = entry.key;
        final player = entry.value;
        final playerIsMe = isMe(player);
        return ElevatedButton.icon(
          onPressed: () {
            ServiceLocator().get<IHapticService>().buttonTap();
            onSelect(player, index);
          },
          icon: Icon(
            playerIsMe ? Icons.person : Icons.smart_toy,
            size: metrics.size(20),
          ),
          label: Text(
            '${getLabel(player)} (${_cardCountLabel(player.hand.length)})',
            style: TextStyle(fontSize: metrics.font(14)),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                playerIsMe ? Colors.amber.shade700 : Colors.blue.shade800,
            padding: EdgeInsets.symmetric(
              horizontal: metrics.space(14),
              vertical: metrics.space(10),
            ),
          ),
        );
      }).toList(),
    );
  }
}
