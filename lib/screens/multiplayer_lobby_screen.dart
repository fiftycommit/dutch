import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import 'multiplayer_game_screen.dart';

class MultiplayerLobbyScreen extends StatelessWidget {
  const MultiplayerLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MultiplayerGameProvider>(
      builder: (context, provider, _) {
        // Si la partie démarre, naviguer vers l'écran de jeu
        if (provider.isPlaying && provider.gameState != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MultiplayerGameScreen(),
                ),
              );
            }
          });
        }

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              provider.leaveRoom();
            }
          },
          child: Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () {
                              provider.leaveRoom();
                              Navigator.pop(context);
                            },
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Salle d\'attente',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Code de la room
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Code de la partie',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                provider.roomCode ?? '------',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                ),
                              ),
                              const SizedBox(width: 15),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Colors.white),
                                onPressed: () {
                                  if (provider.roomCode != null) {
                                    Clipboard.setData(ClipboardData(text: provider.roomCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Code copié !'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Partage ce code avec tes amis !',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (provider.roomSettings != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSettingChip(
                              label: provider.roomSettings!.gameMode.name == 'tournament'
                                  ? 'Tournoi'
                                  : 'Rapide',
                              icon: Icons.flag,
                            ),
                            _buildSettingChip(
                              label: 'Min ${provider.roomSettings!.minPlayers}',
                              icon: Icons.people,
                            ),
                            _buildSettingChip(
                              label: provider.roomSettings!.fillBots
                                  ? 'Bots ON'
                                  : 'Bots OFF',
                              icon: Icons.smart_toy,
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Liste des joueurs
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.people, size: 28),
                                const SizedBox(width: 10),
                                Text(
                                  'Joueurs (${provider.playersInLobby.length}/${provider.roomSettings?.maxPlayers ?? 4})',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: provider.playersInLobby.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : ListView.builder(
                                      itemCount: provider.playersInLobby.length,
                                      itemBuilder: (context, index) {
                                        final player = provider.playersInLobby[index];
                                        final isYou = (player['clientId'] != null &&
                                                player['clientId'] == provider.clientId) ||
                                            (player['id'] == provider.playerId);
                                        final presence =
                                            provider.presenceByClientId[player['clientId']] ??
                                                provider.presenceById[player['id']];
                                        final isSpectator =
                                            presence != null && presence['isSpectator'] == true;
                                        return Card(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          color: Colors.white.withValues(alpha: 0.9),
                                          elevation: 2,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: Colors.white.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: Theme.of(context).colorScheme.primary,
                                              child: Text(
                                                (player['name'] ?? 'J')[0].toUpperCase(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                Text(
                                                  player['name'] ?? 'Joueur',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (isYou)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 10),
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: const Text(
                                                      'Vous',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                if (provider.isHost && index == 0)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 10),
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: const Text(
                                                      'Hôte',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isSpectator)
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 8),
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blueGrey,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: const Text(
                                                      'Spectateur',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                _presenceDot(presence),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bouton démarrer (seulement pour l'hôte)
                    if (provider.isHost)
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: provider.playersInLobby.length >=
                                    (provider.roomSettings?.minPlayers ?? 2)
                                ? () => provider.startGame()
                                : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(20),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                            ),
                            child: Text(
                              provider.playersInLobby.length <
                                      (provider.roomSettings?.minPlayers ?? 2)
                                  ? 'Minimum ${provider.roomSettings?.minPlayers ?? 2} joueurs'
                                  : 'Démarrer la partie',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: const Text(
                          'En attente que l\'hôte démarre la partie...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingChip({required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
      } else {
        color = Colors.green;
      }
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
