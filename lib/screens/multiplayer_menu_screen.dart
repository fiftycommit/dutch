import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import 'multiplayer_lobby_screen.dart';

class MultiplayerMenuScreen extends StatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  State<MultiplayerMenuScreen> createState() => _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends State<MultiplayerMenuScreen> {
  final _nameController = TextEditingController(text: 'Joueur');
  final _roomCodeController = TextEditingController();
  GameMode _gameMode = GameMode.quick;
  bool _fillBots = true;
  int _minPlayers = 2;

  @override
  void dispose() {
    _nameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Multijoueur en ligne',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Nom du joueur
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  const Text(
                                    'Votre nom',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  TextField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      hintText: 'Entrez votre nom',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person),
                                    ),
                                    textCapitalization: TextCapitalization.words,
                                    maxLength: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Configuration de la room
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Configuration',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Mode de jeu',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Rapide'),
                                        selected: _gameMode == GameMode.quick,
                                        onSelected: (_) {
                                          setState(() {
                                            _gameMode = GameMode.quick;
                                          });
                                        },
                                      ),
                                      ChoiceChip(
                                        label: const Text('Tournoi'),
                                        selected: _gameMode == GameMode.tournament,
                                        onSelected: (_) {
                                          setState(() {
                                            _gameMode = GameMode.tournament;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Remplir avec des bots',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Switch(
                                        value: _fillBots,
                                        onChanged: (value) {
                                          setState(() {
                                            _fillBots = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Minimum de joueurs',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            onPressed: _minPlayers > 2
                                                ? () {
                                                    setState(() {
                                                      _minPlayers--;
                                                    });
                                                  }
                                                : null,
                                            icon: const Icon(Icons.remove),
                                          ),
                                          Text(
                                            '$_minPlayers',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: _minPlayers < 4
                                                ? () {
                                                    setState(() {
                                                      _minPlayers++;
                                                    });
                                                  }
                                                : null,
                                            icon: const Icon(Icons.add),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _fillBots
                                        ? 'Les bots complètent jusqu’à 4 joueurs'
                                        : 'Uniquement des joueurs humains',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Créer une partie
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            child: InkWell(
                              onTap: () => _createRoom(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(30),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.add_circle,
                                        size: 50,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'Créer une partie',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Invite tes amis avec un code',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Rejoindre une partie
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(30),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.login,
                                      size: 50,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Rejoindre une partie',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _roomCodeController,
                                    decoration: const InputDecoration(
                                      hintText: 'Code de la partie (ex: ABC123)',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.vpn_key),
                                    ),
                                    textCapitalization: TextCapitalization.characters,
                                    maxLength: 6,
                                    onSubmitted: (_) => _joinRoom(context),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _joinRoom(context),
                                      icon: const Icon(Icons.arrow_forward),
                                      label: const Text('Rejoindre'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.all(15),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    final navigator = Navigator.of(context);

    try {
      await provider.createRoom(
        settings: GameSettings(
          gameMode: _gameMode,
          luckDifficulty: Difficulty.medium,
          botDifficulty: Difficulty.medium,
          minPlayers: _minPlayers,
          maxPlayers: 4,
          fillBots: _fillBots,
        ),
        playerName: name,
      );

      if (!mounted || provider.roomCode == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const MultiplayerLobbyScreen(),
        ),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _joinRoom(BuildContext context) async {
    final name = _nameController.text.trim();
    final code = _roomCodeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    if (code.length != 6) {
      _showError('Le code doit contenir 6 caractères');
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    final navigator = Navigator.of(context);

    try {
      await provider.joinRoom(
        roomCode: code,
        playerName: name,
      );

      if (!mounted || provider.roomCode == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const MultiplayerLobbyScreen(),
        ),
      );
    } catch (e) {
      _showError(e.toString());
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
}
