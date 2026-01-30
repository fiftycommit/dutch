import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';

class CreatePublicRoomScreen extends StatefulWidget {
  const CreatePublicRoomScreen({super.key});

  @override
  State<CreatePublicRoomScreen> createState() => _CreatePublicRoomScreenState();
}

class _CreatePublicRoomScreenState extends State<CreatePublicRoomScreen> {
  final _nameController = TextEditingController(text: 'Joueur');
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final provider = context.read<MultiplayerGameProvider>();
      await provider.createPublicRoom(playerName: name);

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
                      'CRÉER UNE PARTIE',
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
                                      Icons.public,
                                      size: isMobile ? 60 : 80,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(height: isMobile ? 16 : 24),
                                    Text(
                                      'Partie Publique',
                                      style: TextStyle(
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 8 : 12),
                                    Text(
                                      'Créez une room et attendez que d\'autres joueurs vous rejoignent',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    TextField(
                                      controller: _nameController,
                                      enabled: !_isCreating,
                                      textCapitalization: TextCapitalization.words,
                                      maxLength: 20,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Votre nom',
                                        labelStyle: const TextStyle(color: Colors.black87),
                                        hintText: 'Entrez votre nom',
                                        hintStyle: const TextStyle(color: Colors.black54),
                                        filled: true,
                                        fillColor: Colors.grey.shade100,
                                        prefixIcon: const Icon(Icons.person, color: Colors.blue),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 24 : 32),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _isCreating ? null : _createRoom,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            vertical: isMobile ? 14 : 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isCreating
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
                                                  const Icon(Icons.add_circle),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'CRÉER ET OUVRIR LE SALON',
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
