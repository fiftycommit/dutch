import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';

class JoinPrivateRoomScreen extends StatefulWidget {
  const JoinPrivateRoomScreen({super.key});

  @override
  State<JoinPrivateRoomScreen> createState() => _JoinPrivateRoomScreenState();
}

class _JoinPrivateRoomScreenState extends State<JoinPrivateRoomScreen> {
  final _nameController = TextEditingController(text: 'Joueur');
  final _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();
    
    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }
    
    if (code.length != 6) {
      _showError('Le code doit contenir 6 caractères');
      return;
    }

    setState(() => _isJoining = true);

    try {
      final provider = context.read<MultiplayerGameProvider>();
      await provider.joinRoom(
        roomCode: code,
        playerName: name,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0d2818),
              Color(0xFF1a472a),
            ],
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
                      onPressed: () => context.go('/multiplayer/mode-selection'),
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
                                constraints: const BoxConstraints(maxWidth: 500),
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
                                      textCapitalization: TextCapitalization.characters,
                                      maxLength: 6,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 8,
                                      ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                                        UpperCaseTextFormatter(),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Code du salon',
                                        labelStyle: const TextStyle(color: Colors.black87),
                                        hintText: 'ABC123',
                                        hintStyle: TextStyle(
                                          color: Colors.black26,
                                          letterSpacing: 8,
                                          fontSize: isMobile ? 24 : 28,
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: BorderSide(color: Colors.orange.shade700, width: 2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 16 : 20),
                                    TextField(
                                      controller: _nameController,
                                      enabled: !_isJoining,
                                      textCapitalization: TextCapitalization.words,
                                      maxLength: 20,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Ton pseudo',
                                        labelStyle: const TextStyle(color: Colors.black87),
                                        hintText: 'Entrez votre nom',
                                        hintStyle: const TextStyle(color: Colors.black54),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        prefixIcon: Icon(Icons.person, color: Colors.orange.shade700),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: BorderSide(color: Colors.orange.shade700, width: 2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _isJoining ? null : _joinRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange.shade700,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            vertical: isMobile ? 14 : 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isJoining
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.login),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'REJOINDRE',
                                                    style: TextStyle(
                                                      fontSize: isMobile ? 14 : 16,
                                                      fontWeight: FontWeight.bold,
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
