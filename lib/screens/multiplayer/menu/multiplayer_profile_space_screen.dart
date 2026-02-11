import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MultiplayerProfileSpaceScreen extends StatefulWidget {
  const MultiplayerProfileSpaceScreen({super.key});

  @override
  State<MultiplayerProfileSpaceScreen> createState() =>
      _MultiplayerProfileSpaceScreenState();
}

class _MultiplayerProfileSpaceScreenState
    extends State<MultiplayerProfileSpaceScreen> {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  final TextEditingController _pseudoController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  SocialProfile? _profile;
  List<FriendEntry> _friends = <FriendEntry>[];
  List<FriendRequestEntry> _incomingRequests = <FriendRequestEntry>[];
  List<FriendRequestEntry> _outgoingRequests = <FriendRequestEntry>[];
  List<String> _blockedUsers = <String>[];
  List<SavedRoom> _hostRooms = <SavedRoom>[];
  Map<String, Map<String, dynamic>> _activeHostRoomsByCode =
      <String, Map<String, dynamic>>{};

  Set<String> _reservedUsernames = <String>{};

  bool _loading = true;
  bool _savingProfile = false;
  String? _pseudoError;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pseudoController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    final provider = context.read<MultiplayerGameProvider>();
    final profile = await _socialRepository.getProfile();
    final friends = await _socialRepository.getFriends();
    final incoming = await _socialRepository.getFriendRequests(
      direction: FriendRequestDirection.incoming,
    );
    final outgoing = await _socialRepository.getFriendRequests(
      direction: FriendRequestDirection.outgoing,
    );
    final blocked = await _socialRepository.getBlockedUsers();

    final allRooms = await provider.getMyRooms();
    final hostRooms = allRooms.where((room) => room.isHost).toList();
    final hostCodes = hostRooms.map((room) => room.roomCode).toList();
    final activeRooms = hostCodes.isEmpty
        ? <Map<String, dynamic>>[]
        : await provider.checkActiveRooms(hostCodes) ??
            <Map<String, dynamic>>[];

    final activeByCode = <String, Map<String, dynamic>>{
      for (final room in activeRooms)
        ((room['roomCode'] as String?) ?? '').toUpperCase():
            Map<String, dynamic>.from(room),
    };

    final reservedUsernames = await _socialRepository.getReservedUsernames(
      exceptUsername: profile?.username,
    );

    if (!mounted) {
      return;
    }

    _pseudoController.text = profile?.displayName ?? '';
    _usernameController.text = profile?.username ?? '';

    setState(() {
      _profile = profile;
      _friends = friends;
      _incomingRequests = incoming;
      _outgoingRequests = outgoing;
      _blockedUsers = blocked;
      _hostRooms = hostRooms;
      _activeHostRoomsByCode = activeByCode;
      _reservedUsernames = reservedUsernames;
      _pseudoError = null;
      _usernameError = null;
      _loading = false;
    });
  }

  String? _validatePseudo({required bool checkRequired}) {
    final value = _pseudoController.text.trim();
    if (checkRequired && value.isEmpty) {
      return 'Le pseudo est requis.';
    }
    if (value.length > 24) {
      return 'Maximum 24 caracteres.';
    }
    return null;
  }

  String? _validateUsername({required bool checkRequired}) {
    final rawValue = _usernameController.text;
    final normalized = SocialHubRepository.normalizeUsername(rawValue);

    if (checkRequired && normalized.isEmpty) {
      return 'Le nom d utilisateur est requis.';
    }
    if (normalized.isEmpty) {
      return null;
    }
    if (!SocialHubRepository.containsOnlyAllowedUsernameChars(rawValue)) {
      return 'Caracteres autorises: lettres/chiffres, ., _ et - (accents autorises)';
    }
    if (normalized.length < 3) {
      return 'Minimum 3 caracteres.';
    }
    if (normalized.length > 20) {
      return 'Maximum 20 caracteres.';
    }
    if (_reservedUsernames.contains(normalized)) {
      return 'Ce nom d utilisateur existe deja sur cet appareil.';
    }
    return null;
  }

  void _validateLive() {
    setState(() {
      _pseudoError = _validatePseudo(checkRequired: false);
      _usernameError = _validateUsername(checkRequired: false);
    });
  }

  Future<void> _saveProfile() async {
    final pseudoError = _validatePseudo(checkRequired: true);
    final usernameError = _validateUsername(checkRequired: true);
    if (pseudoError != null || usernameError != null) {
      setState(() {
        _pseudoError = pseudoError;
        _usernameError = usernameError;
      });
      return;
    }

    setState(() {
      _savingProfile = true;
      _pseudoError = null;
      _usernameError = null;
    });

    final now = DateTime.now();
    final updated = SocialProfile(
      displayName: _pseudoController.text.trim(),
      username: SocialHubRepository.normalizeUsername(_usernameController.text),
      roomInviteNotificationsEnabled:
          _profile?.roomInviteNotificationsEnabled ?? false,
      createdAt: _profile?.createdAt ?? now,
      updatedAt: now,
    );
    await _socialRepository.saveProfile(updated);
    await _loadData();

    if (!mounted) {
      return;
    }
    setState(() {
      _savingProfile = false;
    });
    _showSnackBar('Profil mis a jour.');
  }

  Future<void> _toggleInviteNotifications(bool value) async {
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final updated = profile.copyWith(
      roomInviteNotificationsEnabled: value,
      updatedAt: DateTime.now(),
    );
    await _socialRepository.saveProfile(updated);
    await _loadData();
  }

  Future<void> _openAddFriendDialog() async {
    final usernameController = TextEditingController();
    String? error;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> submit() async {
              if (busy) {
                return;
              }
              final rawUsername = usernameController.text;
              final normalizedUsername =
                  SocialHubRepository.normalizeUsername(rawUsername);
              if (normalizedUsername.isEmpty) {
                setLocalState(() {
                  error = 'Le nom d utilisateur est requis.';
                });
                return;
              }

              if (!SocialHubRepository.isValidUsernameFormat(
                normalizedUsername,
              )) {
                setLocalState(() {
                  error =
                      'Nom d utilisateur invalide (3-20 caracteres, lettres/chiffres, ., _, -)';
                });
                return;
              }
              if (normalizedUsername == _profile?.username) {
                setLocalState(() {
                  error = 'Tu ne peux pas t ajouter toi-meme.';
                });
                return;
              }

              setLocalState(() {
                busy = true;
                error = null;
              });

              await _socialRepository.addFriendRequest(
                username: normalizedUsername,
                displayName: normalizedUsername,
                direction: FriendRequestDirection.outgoing,
              );

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              await _loadData();
              if (!mounted) {
                return;
              }
              _showSnackBar('Demande envoyee a @$normalizedUsername');
            }

            return AlertDialog(
              backgroundColor: const Color(0xFFF6F4FB),
              title: const Text(
                'Ajouter un ami',
                style: TextStyle(color: Color(0xFF111827)),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Nom d utilisateur',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: usernameController,
                      textCapitalization: TextCapitalization.none,
                      maxLength: 20,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'pegga.pig',
                        prefixText: '@',
                        errorText: error,
                        filled: true,
                        fillColor: Colors.white,
                        labelStyle: const TextStyle(color: Color(0xFF374151)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF4F46E5),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Annuler'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : submit,
                  child: const Text('Demander en ami'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _acceptIncomingRequest(String username) async {
    await _socialRepository.acceptIncomingRequest(username);
    await _loadData();
    if (!mounted) {
      return;
    }
    _showSnackBar('@$username ajoute aux amis.');
  }

  Future<void> _declineIncomingRequest(String username) async {
    await _socialRepository.removeFriendRequest(
      username: username,
      direction: FriendRequestDirection.incoming,
    );
    await _loadData();
    if (!mounted) {
      return;
    }
    _showSnackBar('Demande de @$username refusee.');
  }

  Future<void> _unblockUser(String username) async {
    await _socialRepository.unblockUser(username);
    await _loadData();
    if (!mounted) {
      return;
    }
    _showSnackBar('@$username debloque.');
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _statusLabelForRoom(String roomCode) {
    final roomData = _activeHostRoomsByCode[roomCode];
    final status = roomData?['status'] as String? ?? 'offline';
    return switch (status) {
      'waiting' => 'En attente',
      'playing' => 'En cours',
      'ended' => 'Terminee',
      'closing' => 'Fermeture',
      _ => 'Hors ligne',
    };
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1223),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1223),
        foregroundColor: Colors.white,
        title: const Text(
          'Mon profil',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rafraichir',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _sectionCard(
                  icon: Icons.badge_outlined,
                  title: 'Profil',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Pseudo',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _pseudoController,
                        onChanged: (_) => _validateLive(),
                        textCapitalization: TextCapitalization.words,
                        maxLength: 24,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ton pseudo',
                          errorText: _pseudoError,
                          filled: true,
                          fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _pseudoError == null
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFFB91C1C),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _pseudoError == null
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFFB91C1C),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Nom d utilisateur',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: const Text(
                              '@',
                              style: TextStyle(
                                color: Color(0xFF111827),
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              onChanged: (_) => _validateLive(),
                              textCapitalization: TextCapitalization.none,
                              maxLength: 20,
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'pegga.pig',
                                errorText: _usernameError,
                                filled: true,
                                fillColor: Colors.white,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: _usernameError == null
                                        ? const Color(0xFFD1D5DB)
                                        : const Color(0xFFB91C1C),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: _usernameError == null
                                        ? const Color(0xFF4F46E5)
                                        : const Color(0xFFB91C1C),
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value:
                            _profile?.roomInviteNotificationsEnabled ?? false,
                        onChanged: _toggleInviteNotifications,
                        title: const Text(
                          'Notifications d invitation',
                          style: TextStyle(color: Color(0xFF111827)),
                        ),
                        subtitle: const Text(
                          'Push cross-device a brancher cote compte.',
                          style: TextStyle(color: Color(0xFF374151)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _savingProfile ? null : _saveProfile,
                          icon: const Icon(Icons.save_outlined),
                          label: _savingProfile
                              ? const Text('Enregistrement...')
                              : const Text('Enregistrer'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Amis et demandes',
                  trailing: FilledButton.icon(
                    onPressed: _openAddFriendDialog,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Ajouter'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${_friends.length} ami(s) • ${_incomingRequests.length} demande(s) recue(s)',
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_incomingRequests.isEmpty)
                        const Text(
                          'Aucune demande recue pour le moment.',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        )
                      else
                        ..._incomingRequests.map((request) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        request.displayName,
                                        style: const TextStyle(
                                          color: Color(0xFF111827),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '@${request.username}',
                                        style: const TextStyle(
                                          color: Color(0xFF4B5563),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _declineIncomingRequest(
                                    request.username,
                                  ),
                                  child: const Text('Refuser'),
                                ),
                                FilledButton(
                                  onPressed: () => _acceptIncomingRequest(
                                    request.username,
                                  ),
                                  child: const Text('Accepter'),
                                ),
                              ],
                            ),
                          );
                        }),
                      if (_outgoingRequests.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        const Text(
                          'Demandes envoyees',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _outgoingRequests
                              .map(
                                (request) => Chip(
                                  label: Text('@${request.username}'),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  icon: Icons.block_outlined,
                  title: 'Personnes bloquees',
                  child: _blockedUsers.isEmpty
                      ? const Text(
                          'Aucune personne bloquee.',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        )
                      : Column(
                          children: _blockedUsers.map((username) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '@$username',
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: OutlinedButton(
                                onPressed: () => _unblockUser(username),
                                child: const Text('Debloquer'),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  icon: Icons.meeting_room_outlined,
                  title: 'Salons ou je suis hote',
                  child: _hostRooms.isEmpty
                      ? const Text(
                          'Aucun salon hote enregistre.',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        )
                      : Column(
                          children: _hostRooms.map((room) {
                            final statusLabel =
                                _statusLabelForRoom(room.roomCode);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          room.roomCode,
                                          style: const TextStyle(
                                            color: Color(0xFF111827),
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.3,
                                          ),
                                        ),
                                        Text(
                                          'Ajoute le ${_formatDate(room.joinedAt)}',
                                          style: const TextStyle(
                                            color: Color(0xFF4B5563),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Chip(label: Text(statusLabel)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFF111827)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
