import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/logging/game_logger_service.dart';
import '../../utils/screen_utils.dart';
import '../../utils/ui_constants.dart';
import '../../widgets/game/player_avatar.dart';

/// Résultat RP pour un joueur
class PlayerRPResult {
  final int rpChange;
  final String? streakText;

  const PlayerRPResult({required this.rpChange, this.streakText});

  String get formattedChange =>
      rpChange >= 0 ? '+$rpChange RP' : '$rpChange RP';
  Color get color => rpChange > 0
      ? (rpChange >= 50 ? Colors.amber : Colors.greenAccent)
      : (rpChange < -30 ? Colors.red : Colors.redAccent);
}

/// Configuration pour l'écran de résultats
class ResultsConfig {
  final GameState gameState;
  final String? localPlayerId;
  final List<Widget> Function(BuildContext context) buildActionButtons;

  /// Titre personnalisé (par défaut "RÉSULTATS")
  final String? title;

  /// Sous-titre optionnel (ex: "MANCHE 2 TERMINÉE")
  final String? subtitle;

  /// Indique si on est en finale de tournoi (pour textes spécifiques)
  final bool isTournamentFinal;

  /// Message d'alerte optionnel (ex: "Vous avez été éliminé")
  final Widget? alertBanner;

  /// Liste des joueurs éliminés à cette manche (tournoi)
  final Set<String>? eliminatedPlayerIds;

  /// Callback pour vérifier si on doit rediriger (multiplayer lobby)
  final bool Function()? shouldRedirect;
  final VoidCallback? onRedirect;

  /// Callback optionnel pour calculer les RP d'un joueur (si null, pas d'affichage RP)
  final PlayerRPResult? Function(Player player, int rank)? rpCalculator;

  const ResultsConfig({
    required this.gameState,
    required this.buildActionButtons,
    this.localPlayerId,
    this.title,
    this.subtitle,
    this.isTournamentFinal = false,
    this.alertBanner,
    this.eliminatedPlayerIds,
    this.shouldRedirect,
    this.onRedirect,
    this.rpCalculator,
  });
}

/// Écran de résultats unifié (solo + multiplayer)
class ResultsScreen extends StatelessWidget {
  final ResultsConfig config;

  const ResultsScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    // Vérifier redirection (multiplayer)
    if (config.shouldRedirect?.call() == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          config.onRedirect?.call();
        }
      });
    }

    final gameState = config.gameState;
    final ranking = gameState.getFinalRanking();
    final ranksWithTies = gameState.getFinalRanksWithTies();

    final callerId = gameState.dutchCallerId;
    final caller = callerId != null
        ? gameState.players.firstWhere((p) => p.id == callerId)
        : null;
    final callerWon = gameState.didDutchCallerWin();

    return Scaffold(
      body: Container(
        decoration: AppDecorations.pageBackground,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: ScreenUtils.spacing(context, 16)),

              // Titre + bouton log
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    config.title ?? "RÉSULTATS",
                    style: TextStyle(
                      fontFamily: 'Rye',
                      fontSize: ScreenUtils.scaleFont(context, 32),
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(2, 2),
                        )
                      ],
                    ),
                  ),
                  if (GameLoggerService.instance.hasLog) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => _downloadGameLog(context),
                      icon: const Icon(Icons.download, color: Colors.white70),
                      tooltip: 'Télécharger le log de la partie',
                      iconSize: 24,
                    ),
                  ],
                ],
              ),

              // Sous-titre optionnel
              if (config.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  config.subtitle!,
                  style: TextStyle(
                    fontSize: ScreenUtils.scaleFont(context, 14),
                    color: AppColors.textSecondary,
                  ),
                ),
              ],

              // Bannière d'alerte optionnelle
              if (config.alertBanner != null) ...[
                const SizedBox(height: 8),
                config.alertBanner!,
              ],

              // Bannière Dutch caller
              if (caller != null) ...[
                SizedBox(height: ScreenUtils.spacing(context, 8)),
                _buildDutchCallerBanner(context, caller, callerWon),
              ],

              SizedBox(height: ScreenUtils.spacing(context, 12)),

              // Liste des joueurs
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenUtils.spacing(context, 16),
                  ),
                  itemCount: ranking.length,
                  itemBuilder: (context, index) {
                    final player = ranking[index];
                    final rank = ranksWithTies[player.id] ?? (index + 1);
                    return _buildPlayerResult(context, player, rank, gameState);
                  },
                ),
              ),

              // Boutons d'action
              Padding(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
                child: Column(
                  children: config.buildActionButtons(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadGameLog(BuildContext context) async {
    try {
      await GameLoggerService.instance.downloadLog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Log exporté !'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors du téléchargement'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDutchCallerBanner(
      BuildContext context, Player caller, bool callerWon) {
    final isFinal = config.isTournamentFinal;
    final callerWinsTournament = isFinal && callerWon;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ScreenUtils.spacing(context, 16),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ScreenUtils.spacing(context, 12),
        vertical: ScreenUtils.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: callerWon
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: callerWon ? Colors.greenAccent : Colors.redAccent,
        ),
      ),
      child: Text(
        callerWon
            ? "${caller.name} a crié DUTCH et gagne ${callerWinsTournament ? "le tournoi" : "la manche"} !"
            : "${caller.name} a crié DUTCH mais perd ${isFinal ? "la finale" : "la manche"}.",
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPlayerResult(
      BuildContext context, Player player, int rank, GameState gs) {
    final isWinner = rank == 1;
    final isDutchCaller = gs.dutchCallerId == player.id;
    final isDutchEliminated = isDutchCaller && !isWinner;
    final isTournamentEliminated =
        config.eliminatedPlayerIds?.contains(player.id) ?? false;
    final isEliminated = isDutchEliminated || isTournamentEliminated;
    final score = gs.getFinalScore(player);
    final isLocalPlayer = player.id == config.localPlayerId ||
        (config.localPlayerId == null && player.isHuman);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEliminated
            ? Colors.red.withValues(alpha: 0.2)
            : (isWinner
                ? Colors.amber.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
        border: isEliminated
            ? Border.all(color: Colors.red, width: 2)
            : (isDutchCaller
                ? Border.all(color: Colors.amber, width: 2)
                : null),
      ),
      child: Row(
        children: [
          // Position
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getPositionColor(rank),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "#$rank",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Avatar
          PlayerAvatar(player: player, size: 44),
          const SizedBox(width: 12),

          // Nom et badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        player.name,
                        style: TextStyle(
                          color: isLocalPlayer ? Colors.amber : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLocalPlayer) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "VOUS",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                    if (isDutchCaller) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "DUTCH",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (isEliminated)
                  Text(
                    isDutchEliminated
                        ? "❌ ÉLIMINÉ (Dutch raté !)"
                        : "❌ ÉLIMINÉ",
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                if (isWinner && !isEliminated)
                  const Text(
                    "🏆 Gagnant !",
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          // Score et RP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$score pts",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (config.rpCalculator != null) ...[
                Builder(builder: (context) {
                  final rpResult = config.rpCalculator!(player, rank);
                  if (rpResult == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        rpResult.formattedChange,
                        style: TextStyle(
                          color: rpResult.color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (rpResult.streakText != null)
                        Text(
                          rpResult.streakText!,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _getPositionColor(int position) {
    switch (position) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.grey.shade400;
      case 3:
        return Colors.brown.shade400;
      default:
        return Colors.blueGrey.shade700;
    }
  }
}

/// Widget bouton d'action standard pour les résultats
class ResultsActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final double width;

  const ResultsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = Colors.amber,
    this.width = 280,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
