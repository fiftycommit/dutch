import 'package:flutter/material.dart';
import '../../../../../utils/ui_constants.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../services/social/social_hub_repository.dart';

class CreatePublicRoomScreen extends StatefulWidget {
  const CreatePublicRoomScreen({super.key});

  @override
  State<CreatePublicRoomScreen> createState() => _CreatePublicRoomScreenState();
}

class _CreatePublicRoomScreenState extends State<CreatePublicRoomScreen> {
  String _playerName = 'Joueur';
  final _roomNameController = TextEditingController();
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
    if (profileName.isNotEmpty) _playerName = profileName;
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

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() => _isCreating = true);

    try {
      final provider = context.read<MultiplayerGameProvider>();
      final playerName = await _resolvePlayerName();
      final roomName = _roomNameController.text.trim();
      await provider.createPublicRoom(
        playerName: playerName,
        roomName: roomName.isEmpty ? null : roomName,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
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
                      'CRÉER UN SALON PUBLIC',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
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
                                    TextField(
                                      controller: _roomNameController,
                                      enabled: !_isCreating,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      maxLength: 30,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Nom du salon (optionnel)',
                                        labelStyle: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 12),
                                        counterText: '',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 12),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        prefixIcon: const Icon(Icons.label,
                                            color: Colors.blue, size: 18),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Colors.blue, width: 2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Bouton creer
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('create_public_button'),
                                        onPressed:
                                            _isCreating ? null : _createRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
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
                                                    'CRÉER ET OUVRIR LE SALON',
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
                                      Icons.public,
                                      size: isMobile ? 60 : 80,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(height: isMobile ? 16 : 24),
                                    Text(
                                      'Salon Public',
                                      style: TextStyle(
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 8 : 12),
                                    Text(
                                      'Créez un salon et attendez que d\'autres joueurs vous rejoignent',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    TextField(
                                      controller: _roomNameController,
                                      enabled: !_isCreating,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      maxLength: 30,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Nom du salon (optionnel)',
                                        labelStyle: const TextStyle(
                                            color: Colors.black87),
                                        hintText: 'Ex: Partie entre amis',
                                        hintStyle: const TextStyle(
                                            color: Colors.black54),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        prefixIcon: const Icon(Icons.label,
                                            color: Colors.blue),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                              color: Colors.blue, width: 2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('create_public_button'),
                                        onPressed:
                                            _isCreating ? null : _createRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
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
                                                    'CRÉER ET OUVRIR LE SALON',
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
