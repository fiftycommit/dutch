import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../utils/ui_constants.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../models/game_settings.dart';
import '../../../../../services/social/social_hub_repository.dart';

class CreatePrivateRoomScreen extends StatefulWidget {
  const CreatePrivateRoomScreen({super.key});

  @override
  State<CreatePrivateRoomScreen> createState() =>
      _CreatePrivateRoomScreenState();
}

class _CreatePrivateRoomScreenState extends State<CreatePrivateRoomScreen> {
  String _playerName = 'Joueur';
  bool _isCreating = false;
  final SocialHubRepository _socialRepository = SocialHubRepository();

  @override
  void initState() {
    super.initState();
    _hydrateProfileName();
  }

  Future<void> _hydrateProfileName() async {
    final profile = await _socialRepository.getProfile();
    if (!mounted || profile == null) {
      return;
    }
    final profileName = profile.displayName.trim();
    if (profileName.isNotEmpty) {
      _playerName = profileName;
    }
  }

  Future<String> _resolvePlayerName() async {
    final cached = _playerName.trim();
    if (cached.isNotEmpty && cached != 'Joueur') {
      return cached;
    }

    final profile = await _socialRepository.getProfile();
    final resolved = profile?.displayName.trim() ?? '';
    if (resolved.isNotEmpty) {
      _playerName = resolved;
      return resolved;
    }
    return cached.isNotEmpty ? cached : 'Joueur';
  }

  Future<void> _createRoom() async {
    setState(() => _isCreating = true);

    try {
      final provider = context.read<MultiplayerGameProvider>();
      final playerName = await _resolvePlayerName();
      await provider.createRoom(
        settings: GameSettings(
          numberOfPlayers: 4,
          isPublic: false,
          minPlayers: 2,
          maxPlayers: 4,
        ),
        playerName: playerName,
      );

      if (!mounted) return;
      context.go('/lobby');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
      setState(() => _isCreating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    const statusUrl = 'https://downdetector.com/status/firebase/';
    final hasStatusUrl = message.contains(statusUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: hasStatusUrl
            ? SnackBarAction(
                label: 'Copier lien',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: statusUrl));
                },
              )
            : null,
      ),
    );
  }

  Future<void> _handleBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/multiplayer/create-selection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientTop, AppColors.gradientBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _handleBack,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'CRÉER UN SALON PRIVÉ',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final isCompactLandscape = constraints.maxHeight < 400 &&
                        constraints.maxWidth > constraints.maxHeight;

                    // Layout compact pour petit ecran en paysage
                    if (isCompactLandscape) {
                      return SingleChildScrollView(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            child: Card(
                              color: Colors.white.withValues(alpha: 0.95),
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 4),
                                    // Bouton creer
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('create_private_button'),
                                        onPressed:
                                            _isCreating ? null : _createRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade700,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isCreating
                                            ? const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.add_circle,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'CRÉER LE SALON',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    // Layout standard
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(isMobile ? 20 : 40),
                            child: Card(
                              color: Colors.white.withValues(alpha: 0.95),
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 500),
                                padding: EdgeInsets.all(isMobile ? 24 : 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: isMobile ? 60 : 80,
                                      color: Colors.blue.shade700,
                                    ),
                                    SizedBox(height: isMobile ? 16 : 24),
                                    Text(
                                      'Salon Privé',
                                      style: TextStyle(
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 8 : 12),
                                    Text(
                                      'Un code sera généré pour inviter tes amis',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('create_private_button'),
                                        onPressed:
                                            _isCreating ? null : _createRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade700,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            vertical: isMobile ? 14 : 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isCreating
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.add_circle),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'CRÉER LE SALON',
                                                    style: TextStyle(
                                                      fontSize:
                                                          isMobile ? 14 : 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
    );
  }
}
