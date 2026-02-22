import 'package:flutter/material.dart';
import '../../../../../utils/ui_constants.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../services/social/social_hub_repository.dart';

class JoinPrivateRoomScreen extends StatefulWidget {
  const JoinPrivateRoomScreen({super.key});

  @override
  State<JoinPrivateRoomScreen> createState() => _JoinPrivateRoomScreenState();
}

class _JoinPrivateRoomScreenState extends State<JoinPrivateRoomScreen> {
  String _playerName = 'Joueur';
  final _codeController = TextEditingController();
  bool _isJoining = false;
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
    if (profileName.isNotEmpty && _playerName != profileName) {
      setState(() {
        _playerName = profileName;
      });
    }
  }

  Future<String> _resolvePlayerName() async {
    final profile = await _socialRepository.getProfile();
    final profileName = profile?.displayName.trim() ?? '';
    if (profileName.isNotEmpty) {
      if (_playerName != profileName && mounted) {
        setState(() {
          _playerName = profileName;
        });
      }
      return profileName;
    }
    return _playerName;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();

    if (code.length != 6) {
      _showError('Le code doit contenir 6 caractères');
      return;
    }

    setState(() => _isJoining = true);

    try {
      final provider = context.read<MultiplayerGameProvider>();
      final playerName = await _resolvePlayerName();
      await provider.joinRoom(
        roomCode: code,
        playerName: playerName,
      );

      if (!mounted) return;
      context.go('/lobby');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
      setState(() => _isJoining = false);
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
      context.go('/multiplayer/join-selection');
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
                      'REJOINDRE UN SALON PRIVÉ',
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
                                    Text(
                                      'Entre le code à 6 caractères partagé par l\'hôte',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Row avec code + identité du compte connecté
                                    Row(
                                      children: [
                                        // Champ code
                                        Expanded(
                                          child: TextField(
                                            controller: _codeController,
                                            enabled: !_isJoining,
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            maxLength: 6,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 4,
                                            ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                  RegExp(r'[A-Za-z0-9]')),
                                              UpperCaseTextFormatter(),
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Code du salon',
                                              labelStyle: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 12),
                                              counterText: '',
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12),
                                              filled: true,
                                              fillColor: Colors.grey.shade100,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.orange.shade700,
                                                    width: 2),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Identité connectée (lecture seule)
                                        Expanded(
                                          child: Container(
                                            height: 48,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.person,
                                                  size: 18,
                                                  color: Colors.orange.shade700,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _playerName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Bouton rejoindre
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('join_private_button'),
                                        onPressed:
                                            _isJoining ? null : _joinRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange.shade700,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isJoining
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
                                                  Icon(Icons.login, size: 18),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'REJOINDRE',
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
                                      Icons.vpn_key,
                                      size: isMobile ? 60 : 80,
                                      color: Colors.orange.shade700,
                                    ),
                                    SizedBox(height: isMobile ? 16 : 24),
                                    Text(
                                      'Rejoindre un Salon',
                                      style: TextStyle(
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 8 : 12),
                                    Text(
                                      'Entre le code à 6 caractères partagé par l\'hôte',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    TextField(
                                      controller: _codeController,
                                      enabled: !_isJoining,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      maxLength: 6,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 8,
                                      ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[A-Za-z0-9]')),
                                        UpperCaseTextFormatter(),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Code du salon',
                                        labelStyle: const TextStyle(
                                            color: Colors.black87),
                                        hintText: 'ABC123',
                                        hintStyle: TextStyle(
                                          color: Colors.black26,
                                          letterSpacing: 8,
                                          fontSize: isMobile ? 24 : 28,
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                              color: Colors.orange.shade700,
                                              width: 2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 16 : 20),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person,
                                              color: Colors.orange.shade700),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _playerName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        key: const Key('join_private_button'),
                                        onPressed:
                                            _isJoining ? null : _joinRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange.shade700,
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
                                        child: _isJoining
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
                                                  const Icon(Icons.login),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'REJOINDRE',
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
