import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

enum MultiplayerProfileTab { profile, friends, blocked }

class MultiplayerProfileSpaceScreen extends StatefulWidget {
  const MultiplayerProfileSpaceScreen({
    super.key,
    this.initialTab = MultiplayerProfileTab.profile,
  });

  final MultiplayerProfileTab initialTab;

  @override
  State<MultiplayerProfileSpaceScreen> createState() =>
      _MultiplayerProfileSpaceScreenState();
}

class _MultiplayerProfileSpaceScreenState
    extends State<MultiplayerProfileSpaceScreen> {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  late final FriendsApiService _friendsApi;
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

  // Maps username → server IDs for API calls
  final Map<String, String> _requestIdByUsername = {};
  final Map<String, String> _userIdByUsername = {};

  Set<String> _reservedUsernames = <String>{};

  bool _loading = true;
  bool _savingProfile = false;
  bool _deletingAccount = false;
  bool _editingProfile = false;
  String? _pseudoError;
  String? _usernameError;
  late MultiplayerProfileTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    final authProvider = context.read<AuthProvider>();
    _friendsApi = FriendsApiService(authProvider.authService);
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
    final authProvider = context.read<AuthProvider>();

    // Charger le profil depuis l'auth provider
    SocialProfile? profile;
    List<FriendEntry> friends = [];
    List<FriendRequestEntry> incoming = [];
    List<FriendRequestEntry> outgoing = [];
    List<String> blocked = [];

    if (authProvider.isLoggedIn) {
      // Profil depuis le serveur
      profile = SocialProfile(
        displayName: authProvider.user!.displayName,
        username: authProvider.user!.username,
        roomInviteNotificationsEnabled: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Amis depuis le serveur
      final serverFriends = await _friendsApi.getFriends();
      friends = serverFriends
          .map((f) => FriendEntry(
                username: f.username,
                displayName: f.displayName,
                addedAt: DateTime.tryParse(f.addedAt) ?? DateTime.now(),
              ))
          .toList();

      final requests = await _friendsApi.getRequests();
      incoming = requests.incoming.map((r) {
        _requestIdByUsername[r.username] = r.requestId;
        _userIdByUsername[r.username] = r.userId;
        return FriendRequestEntry(
          username: r.username,
          displayName: r.displayName,
          requestedAt: DateTime.tryParse(r.requestedAt) ?? DateTime.now(),
          direction: FriendRequestDirection.incoming,
        );
      }).toList();
      outgoing = requests.outgoing.map((r) {
        _requestIdByUsername[r.username] = r.requestId;
        return FriendRequestEntry(
          username: r.username,
          displayName: r.displayName,
          requestedAt: DateTime.tryParse(r.requestedAt) ?? DateTime.now(),
          direction: FriendRequestDirection.outgoing,
        );
      }).toList();

      final serverBlocked = await _friendsApi.getBlockedUsers();
      for (final b in serverBlocked) {
        _userIdByUsername[b.username] = b.userId;
      }
      blocked = serverBlocked.map((b) => b.username).toList();

      // Also store friend userIds
      for (final f in serverFriends) {
        _userIdByUsername[f.username] = f.userId;
      }
    } else {
      // Fallback local
      profile = await _socialRepository.getProfile();
      friends = await _socialRepository.getFriends();
      incoming = await _socialRepository.getFriendRequests(
        direction: FriendRequestDirection.incoming,
      );
      outgoing = await _socialRepository.getFriendRequests(
        direction: FriendRequestDirection.outgoing,
      );
      blocked = await _socialRepository.getBlockedUsers();
    }

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

    final authProvider = context.read<AuthProvider>();
    final newDisplayName = _pseudoController.text.trim();

    if (authProvider.isLoggedIn) {
      // Mettre à jour via l'API serveur
      final result = await authProvider.updateProfile(newDisplayName);
      if (!mounted) return;

      if (!result.success) {
        setState(() => _savingProfile = false);
        _showSnackBar(result.error ?? 'Erreur de mise a jour');
        return;
      }
    }

    // Aussi sauvegarder localement pour la rétrocompatibilité
    final now = DateTime.now();
    final updated = SocialProfile(
      displayName: newDisplayName,
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
      _editingProfile = false;
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

              final authProvider = context.read<AuthProvider>();
              if (authProvider.isLoggedIn) {
                // Envoyer via l'API serveur
                final result =
                    await _friendsApi.sendRequest(normalizedUsername);
                if (!result.success) {
                  setLocalState(() {
                    busy = false;
                    error = result.error ?? 'Erreur d\'envoi';
                  });
                  return;
                }
              } else {
                // Fallback local
                await _socialRepository.addFriendRequest(
                  username: normalizedUsername,
                  displayName: normalizedUsername,
                  direction: FriendRequestDirection.outgoing,
                );
              }

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
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn) {
      final requestId = _requestIdByUsername[username];
      if (requestId != null) {
        await _friendsApi.acceptRequest(requestId);
      }
    } else {
      await _socialRepository.acceptIncomingRequest(username);
    }
    await _loadData();
    if (!mounted) return;
    _showSnackBar('@$username ajoute aux amis.');
  }

  Future<void> _declineIncomingRequest(String username) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn) {
      final requestId = _requestIdByUsername[username];
      if (requestId != null) {
        await _friendsApi.rejectRequest(requestId);
      }
    } else {
      await _socialRepository.removeFriendRequest(
        username: username,
        direction: FriendRequestDirection.incoming,
      );
    }
    await _loadData();
    if (!mounted) return;
    _showSnackBar('Demande de @$username refusee.');
  }

  Future<void> _unblockUser(String username) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn) {
      final userId = _userIdByUsername[username];
      if (userId != null) {
        await _friendsApi.unblockUser(userId);
      }
    } else {
      await _socialRepository.unblockUser(username);
    }
    await _loadData();
    if (!mounted) return;
    _showSnackBar('@$username debloque.');
  }

  Future<void> _openDeleteAccountDialog() async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoggedIn) {
      _showSnackBar('Action reservee aux comptes connectes.');
      return;
    }

    final passwordController = TextEditingController();
    String? error;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final password = passwordController.text;
              if (password.isEmpty) {
                setLocalState(() {
                  error = 'Mot de passe requis.';
                });
                return;
              }

              setLocalState(() {
                submitting = true;
                error = null;
              });
              if (mounted) {
                setState(() {
                  _deletingAccount = true;
                });
              }

              final result = await authProvider.deleteAccount(password);
              if (!mounted) return;

              if (!result.success) {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                    error = result.error ?? 'Suppression impossible';
                  });
                }
                setState(() {
                  _deletingAccount = false;
                });
                return;
              }

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }

              await _socialRepository.clearLocalData();

              setState(() {
                _deletingAccount = false;
              });
              _showSnackBar('Compte supprime.');
              if (mounted) {
                context.go('/');
              }
            }

            return AlertDialog(
              title: const Text('Supprimer mon compte'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Cette action est definitive. Toutes tes donnees de compte seront supprimees.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe actuel',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                  child: submitting
                      ? const Text('Suppression...')
                      : const Text('Supprimer'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.dispose();
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

  Future<void> _handleBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/multiplayer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;
    final themed = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );
    return Scaffold(
      body: Theme(
        data: themed,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFEEF2FF),
                Color(0xFFF3E8FF),
                Color(0xFFEFF6FF),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final spec = _ProfileLayoutSpec.from(context, constraints);
                return Column(
                  children: <Widget>[
                    _buildTopHeader(spec),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF6366F1),
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.all(spec.contentPadding),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 170),
                                child: KeyedSubtree(
                                  key: ValueKey<MultiplayerProfileTab>(
                                    _activeTab,
                                  ),
                                  child: _buildTabContent(isLoggedIn, spec),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(_ProfileLayoutSpec spec) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        spec.headerHorizontalPadding,
        spec.headerTopPadding,
        spec.headerHorizontalPadding,
        spec.headerBottomPadding,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFFFBBF24).withValues(alpha: 0.98),
            const Color(0xFFF97316).withValues(alpha: 0.98),
          ],
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(spec.backRadius),
                  onTap: _handleBack,
                  child: Padding(
                    padding: EdgeInsets.all(spec.backPadding),
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: spec.backIconSize,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Mon Profil',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: spec.titleSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: spec.backSlotWidth),
            ],
          ),
          SizedBox(height: spec.tabsTopGap),
          Row(
            children: <Widget>[
              Expanded(
                child: _tabButton(
                  icon: Icons.person_outline,
                  label: 'Profil',
                  tab: MultiplayerProfileTab.profile,
                  spec: spec,
                ),
              ),
              Expanded(
                child: _tabButton(
                  icon: Icons.group_outlined,
                  label: 'Amis',
                  tab: MultiplayerProfileTab.friends,
                  spec: spec,
                ),
              ),
              Expanded(
                child: _tabButton(
                  icon: Icons.block_outlined,
                  label: 'Bloqués',
                  tab: MultiplayerProfileTab.blocked,
                  spec: spec,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required IconData icon,
    required String label,
    required MultiplayerProfileTab tab,
    required _ProfileLayoutSpec spec,
  }) {
    final selected = _activeTab == tab;
    return InkWell(
      onTap: () {
        if (!mounted) return;
        setState(() => _activeTab = tab);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(vertical: spec.tabVerticalPadding),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Colors.white : Colors.transparent,
              width: spec.tabIndicatorWidth,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: spec.tabIconSize,
              color:
                  selected ? Colors.white : Colors.white.withValues(alpha: 0.7),
            ),
            SizedBox(height: spec.tabLabelGap),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: spec.tabLabelSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isLoggedIn, _ProfileLayoutSpec spec) {
    return switch (_activeTab) {
      MultiplayerProfileTab.profile => _buildProfileTab(isLoggedIn, spec),
      MultiplayerProfileTab.friends => _buildFriendsTab(spec),
      MultiplayerProfileTab.blocked => _buildBlockedTab(spec),
    };
  }

  Widget _buildProfileTab(bool isLoggedIn, _ProfileLayoutSpec spec) {
    return SingleChildScrollView(
      key: const ValueKey<String>('profile_tab_scroll'),
      child: Column(
        children: <Widget>[
          _buildProfileIdentityCard(spec),
          SizedBox(height: spec.sectionGap),
          _buildSecurityCard(isLoggedIn, spec),
          if (_hostRooms.isNotEmpty) ...<Widget>[
            SizedBox(height: spec.sectionGap),
            _buildHostRoomsCard(spec),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileIdentityCard(_ProfileLayoutSpec spec) {
    final pseudo = _pseudoController.text.trim();
    final username = _usernameController.text.trim();
    final avatarLabel =
        (pseudo.isEmpty ? 'J' : pseudo.characters.first).toUpperCase();

    return _surfaceCard(
      spec: spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: spec.avatarSize,
                height: spec.avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[
                      const Color(0xFFFBBF24).withValues(alpha: 0.98),
                      const Color(0xFFF97316).withValues(alpha: 0.98),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  avatarLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: spec.avatarTextSize,
                  ),
                ),
              ),
              SizedBox(width: spec.identityGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      pseudo.isEmpty ? 'Pseudo' : pseudo,
                      style: TextStyle(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w800,
                        fontSize: spec.identityTitleSize,
                      ),
                    ),
                    Text(
                      '@${username.isEmpty ? 'username' : username}',
                      style: TextStyle(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                        fontSize: spec.identitySubtitleSize,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _savingProfile
                    ? null
                    : () {
                        setState(() {
                          _editingProfile = !_editingProfile;
                          if (!_editingProfile) {
                            _pseudoError = null;
                            _usernameError = null;
                          }
                        });
                      },
                icon: Icon(
                  _editingProfile ? Icons.close_rounded : Icons.edit_rounded,
                  color: const Color(0xFF4F46E5),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE4E4F0),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: !_editingProfile
                ? const SizedBox(
                    key: ValueKey<String>('profile_edit_closed'),
                    height: 0,
                  )
                : Padding(
                    key: const ValueKey<String>('profile_edit_open'),
                    padding: EdgeInsets.only(top: spec.editTopGap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _fieldLabel('Pseudo', spec),
                        SizedBox(height: spec.labelGap),
                        TextField(
                          controller: _pseudoController,
                          onChanged: (_) => _validateLive(),
                          textCapitalization: TextCapitalization.words,
                          maxLength: 24,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _profileInputDecoration(
                            hintText: 'Ton pseudo',
                            errorText: _pseudoError,
                            spec: spec,
                          ),
                        ),
                        SizedBox(height: spec.fieldBlockGap),
                        _fieldLabel('Nom d\'utilisateur', spec),
                        SizedBox(height: spec.labelGap),
                        Row(
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
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
                                decoration: _profileInputDecoration(
                                  hintText: 'pegga.pig',
                                  errorText: _usernameError,
                                  spec: spec,
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
                          title: Text(
                            'Notifications d\'invitation',
                            style: TextStyle(
                              color: const Color(0xFF1E293B),
                              fontWeight: FontWeight.w700,
                              fontSize: spec.smallTextSize,
                            ),
                          ),
                          subtitle: Text(
                            'Activer les invitations de salon.',
                            style: TextStyle(
                              color: const Color(0xFF64748B),
                              fontSize: spec.tinyTextSize,
                            ),
                          ),
                        ),
                        SizedBox(height: spec.buttonsTopGap),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _savingProfile
                                    ? null
                                    : () {
                                        setState(() {
                                          _editingProfile = false;
                                          _pseudoError = null;
                                          _usernameError = null;
                                        });
                                      },
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    vertical: spec.buttonVerticalPadding,
                                  ),
                                ),
                                child: Text(
                                  'Annuler',
                                  style:
                                      TextStyle(fontSize: spec.smallTextSize),
                                ),
                              ),
                            ),
                            SizedBox(width: spec.actionsGap),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(spec.buttonRadius),
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      const Color(0xFFFBBF24)
                                          .withValues(alpha: 0.98),
                                      const Color(0xFFF97316)
                                          .withValues(alpha: 0.98),
                                    ],
                                  ),
                                ),
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _savingProfile ? null : _saveProfile,
                                  icon: _savingProfile
                                      ? SizedBox(
                                          width: spec.loaderSize,
                                          height: spec.loaderSize,
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(
                                    _savingProfile
                                        ? 'Enregistrement...'
                                        : 'Enregistrer',
                                    style: TextStyle(
                                      fontSize: spec.smallTextSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                    foregroundColor: Colors.black,
                                    padding: EdgeInsets.symmetric(
                                      vertical: spec.buttonVerticalPadding,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        spec.buttonRadius,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(bool isLoggedIn, _ProfileLayoutSpec spec) {
    return _surfaceCard(
      spec: spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Sécurité',
            style: TextStyle(
              color: const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
              fontSize: spec.sectionTitleSize,
            ),
          ),
          SizedBox(height: spec.securityGap),
          if (!isLoggedIn)
            Text(
              'Connecte-toi pour accéder aux actions de sécurité.',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: spec.smallTextSize,
              ),
            )
          else ...<Widget>[
            _securityActionTile(
              spec: spec,
              icon: Icons.lock_outline_rounded,
              title: 'Changer le mot de passe',
              onTap: () => context.go('/change-password'),
            ),
            SizedBox(height: spec.securityItemGap),
            _dangerActionTile(
              spec: spec,
              icon: Icons.person_remove_alt_1_rounded,
              title: 'Supprimer mon compte',
              subtitle: 'Action irréversible',
              onTap: _deletingAccount ? null : _openDeleteAccountDialog,
            ),
            if (_deletingAccount) ...<Widget>[
              SizedBox(height: spec.securityItemGap),
              const LinearProgressIndicator(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHostRoomsCard(_ProfileLayoutSpec spec) {
    return _surfaceCard(
      spec: spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Salons où je suis hôte',
            style: TextStyle(
              color: const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
              fontSize: spec.sectionTitleSize,
            ),
          ),
          SizedBox(height: spec.securityGap),
          ..._hostRooms.map((room) {
            final statusLabel = _statusLabelForRoom(room.roomCode);
            return Container(
              margin: EdgeInsets.only(bottom: spec.listItemGap),
              padding: EdgeInsets.all(spec.listItemPadding),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(spec.innerRadius),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                  SizedBox(width: spec.identityGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          room.roomCode,
                          style: TextStyle(
                            color: const Color(0xFF111827),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            fontSize: spec.smallTextSize,
                          ),
                        ),
                        Text(
                          'Ajouté le ${_formatDate(room.joinedAt)}',
                          style: TextStyle(
                            color: const Color(0xFF64748B),
                            fontSize: spec.tinyTextSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(label: Text(statusLabel)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFriendsTab(_ProfileLayoutSpec spec) {
    final hasData = _friends.isNotEmpty ||
        _incomingRequests.isNotEmpty ||
        _outgoingRequests.isNotEmpty;

    return SingleChildScrollView(
      key: const ValueKey<String>('friends_tab_scroll'),
      child: _surfaceCard(
        spec: spec,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!hasData)
              _buildEmptyFriendsState(spec)
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Amis et demandes',
                    style: TextStyle(
                      color: const Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                      fontSize: spec.sectionTitleSize,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _openAddFriendDialog,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                    ),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(
                      'Ajouter',
                      style: TextStyle(fontSize: spec.smallTextSize),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spec.securityGap),
              Text(
                '${_friends.length} ami(s) • ${_incomingRequests.length} demande(s) reçue(s)',
                style: TextStyle(
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                  fontSize: spec.smallTextSize,
                ),
              ),
              SizedBox(height: spec.securityGap),
              if (_friends.isNotEmpty) ...<Widget>[
                _subTitle('Mes amis', spec),
                SizedBox(height: spec.labelGap),
                ..._friends.map((friend) => _friendTile(friend, spec)),
                SizedBox(height: spec.fieldBlockGap),
              ],
              _subTitle('Demandes reçues', spec),
              SizedBox(height: spec.labelGap),
              if (_incomingRequests.isEmpty)
                Text(
                  'Aucune demande reçue pour le moment.',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
                    fontSize: spec.smallTextSize,
                  ),
                )
              else
                ..._incomingRequests
                    .map((request) => _incomingRequestTile(request, spec)),
              if (_outgoingRequests.isNotEmpty) ...<Widget>[
                SizedBox(height: spec.fieldBlockGap),
                _subTitle('Demandes envoyées', spec),
                SizedBox(height: spec.labelGap),
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
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFriendsState(_ProfileLayoutSpec spec) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spec.emptyVerticalPadding),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.group_add_outlined,
            size: spec.emptyIconSize,
            color: const Color(0xFF4F46E5),
          ),
          SizedBox(height: spec.labelGap),
          Text(
            'Aucun ami pour le moment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF334155),
              fontWeight: FontWeight.w700,
              fontSize: spec.sectionTitleSize,
            ),
          ),
          SizedBox(height: spec.labelGap),
          Text(
            'Ajoutez-en avec le bouton + !',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: spec.smallTextSize,
            ),
          ),
          SizedBox(height: spec.buttonsTopGap),
          FloatingActionButton(
            heroTag: 'add_friend_fab',
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            onPressed: _openAddFriendDialog,
            child: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
    );
  }

  Widget _friendTile(FriendEntry friend, _ProfileLayoutSpec spec) {
    return Container(
      margin: EdgeInsets.only(bottom: spec.listItemGap),
      padding: EdgeInsets.all(spec.listItemPadding),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(spec.innerRadius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.person_outline, color: Color(0xFF475569)),
          SizedBox(width: spec.identityGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  friend.displayName,
                  style: TextStyle(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: spec.smallTextSize,
                  ),
                ),
                Text(
                  '@${friend.username}',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
                    fontSize: spec.tinyTextSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _incomingRequestTile(
      FriendRequestEntry request, _ProfileLayoutSpec spec) {
    return Container(
      margin: EdgeInsets.only(bottom: spec.listItemGap),
      padding: EdgeInsets.all(spec.listItemPadding),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(spec.innerRadius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  request.displayName,
                  style: TextStyle(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: spec.smallTextSize,
                  ),
                ),
                Text(
                  '@${request.username}',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
                    fontSize: spec.tinyTextSize,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _declineIncomingRequest(request.username),
            child: Text(
              'Refuser',
              style: TextStyle(fontSize: spec.tinyTextSize),
            ),
          ),
          FilledButton(
            onPressed: () => _acceptIncomingRequest(request.username),
            child: Text(
              'Accepter',
              style: TextStyle(fontSize: spec.tinyTextSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedTab(_ProfileLayoutSpec spec) {
    return SingleChildScrollView(
      key: const ValueKey<String>('blocked_tab_scroll'),
      child: _surfaceCard(
        spec: spec,
        child: _blockedUsers.isEmpty
            ? Padding(
                padding:
                    EdgeInsets.symmetric(vertical: spec.emptyVerticalPadding),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.block_outlined,
                      size: spec.emptyIconSize,
                      color: const Color(0xFF94A3B8),
                    ),
                    SizedBox(height: spec.labelGap),
                    Text(
                      'Aucun utilisateur bloqué.',
                      style: TextStyle(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                        fontSize: spec.sectionTitleSize,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Personnes bloquées',
                    style: TextStyle(
                      color: const Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                      fontSize: spec.sectionTitleSize,
                    ),
                  ),
                  SizedBox(height: spec.securityGap),
                  ..._blockedUsers.map((username) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '@$username',
                        style: TextStyle(
                          color: const Color(0xFF1E293B),
                          fontWeight: FontWeight.w700,
                          fontSize: spec.smallTextSize,
                        ),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => _unblockUser(username),
                        child: Text(
                          'Débloquer',
                          style: TextStyle(fontSize: spec.tinyTextSize),
                        ),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }

  Widget _surfaceCard({
    required _ProfileLayoutSpec spec,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(spec.cardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(spec.cardPadding),
      child: child,
    );
  }

  Widget _securityActionTile({
    required _ProfileLayoutSpec spec,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFE4EBF4),
      borderRadius: BorderRadius.circular(spec.innerRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(spec.innerRadius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spec.tileHorizontalPadding,
            vertical: spec.tileVerticalPadding,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon,
                  color: const Color(0xFF334155), size: spec.tileIconSize),
              SizedBox(width: spec.identityGap),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: spec.smallTextSize,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF334155)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dangerActionTile({
    required _ProfileLayoutSpec spec,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: const Color(0xFFFDEAEA),
      borderRadius: BorderRadius.circular(spec.innerRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(spec.innerRadius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spec.tileHorizontalPadding,
            vertical: spec.tileVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon,
                  color: const Color(0xFFDC2626), size: spec.tileIconSize),
              SizedBox(width: spec.identityGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        fontSize: spec.smallTextSize,
                      ),
                    ),
                    SizedBox(height: spec.labelGap / 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: const Color(0xFFEF4444),
                        fontSize: spec.tinyTextSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label, _ProfileLayoutSpec spec) {
    return Text(
      label,
      style: TextStyle(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        fontSize: spec.smallTextSize,
      ),
    );
  }

  Widget _subTitle(String label, _ProfileLayoutSpec spec) {
    return Text(
      label,
      style: TextStyle(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        fontSize: spec.smallTextSize,
      ),
    );
  }

  InputDecoration _profileInputDecoration({
    required String hintText,
    required String? errorText,
    required _ProfileLayoutSpec spec,
  }) {
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: spec.tileHorizontalPadding,
        vertical: spec.tileVerticalPadding,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.innerRadius),
        borderSide: BorderSide(
          color: errorText == null
              ? const Color(0xFFD1D5DB)
              : const Color(0xFFB91C1C),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.innerRadius),
        borderSide: BorderSide(
          color: errorText == null
              ? const Color(0xFF4F46E5)
              : const Color(0xFFB91C1C),
          width: 1.4,
        ),
      ),
    );
  }
}

class _ProfileLayoutSpec {
  const _ProfileLayoutSpec({
    required this.headerHorizontalPadding,
    required this.headerTopPadding,
    required this.headerBottomPadding,
    required this.backPadding,
    required this.backRadius,
    required this.backIconSize,
    required this.backSlotWidth,
    required this.titleSize,
    required this.tabsTopGap,
    required this.tabVerticalPadding,
    required this.tabIndicatorWidth,
    required this.tabIconSize,
    required this.tabLabelGap,
    required this.tabLabelSize,
    required this.contentPadding,
    required this.maxContentWidth,
    required this.cardRadius,
    required this.cardPadding,
    required this.sectionGap,
    required this.sectionTitleSize,
    required this.avatarSize,
    required this.avatarTextSize,
    required this.identityGap,
    required this.identityTitleSize,
    required this.identitySubtitleSize,
    required this.editTopGap,
    required this.fieldBlockGap,
    required this.labelGap,
    required this.smallTextSize,
    required this.tinyTextSize,
    required this.buttonsTopGap,
    required this.actionsGap,
    required this.buttonVerticalPadding,
    required this.buttonRadius,
    required this.loaderSize,
    required this.securityGap,
    required this.securityItemGap,
    required this.innerRadius,
    required this.tileHorizontalPadding,
    required this.tileVerticalPadding,
    required this.tileIconSize,
    required this.listItemGap,
    required this.listItemPadding,
    required this.emptyVerticalPadding,
    required this.emptyIconSize,
  });

  final double headerHorizontalPadding;
  final double headerTopPadding;
  final double headerBottomPadding;
  final double backPadding;
  final double backRadius;
  final double backIconSize;
  final double backSlotWidth;
  final double titleSize;
  final double tabsTopGap;
  final double tabVerticalPadding;
  final double tabIndicatorWidth;
  final double tabIconSize;
  final double tabLabelGap;
  final double tabLabelSize;
  final double contentPadding;
  final double maxContentWidth;
  final double cardRadius;
  final double cardPadding;
  final double sectionGap;
  final double sectionTitleSize;
  final double avatarSize;
  final double avatarTextSize;
  final double identityGap;
  final double identityTitleSize;
  final double identitySubtitleSize;
  final double editTopGap;
  final double fieldBlockGap;
  final double labelGap;
  final double smallTextSize;
  final double tinyTextSize;
  final double buttonsTopGap;
  final double actionsGap;
  final double buttonVerticalPadding;
  final double buttonRadius;
  final double loaderSize;
  final double securityGap;
  final double securityItemGap;
  final double innerRadius;
  final double tileHorizontalPadding;
  final double tileVerticalPadding;
  final double tileIconSize;
  final double listItemGap;
  final double listItemPadding;
  final double emptyVerticalPadding;
  final double emptyIconSize;

  factory _ProfileLayoutSpec.from(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final media = MediaQuery.of(context);
    final width = constraints.maxWidth;
    final isLandscapeCompact =
        media.orientation == Orientation.landscape && width < 1024;
    final isLarge = width >= 1024;

    return _ProfileLayoutSpec(
      headerHorizontalPadding: isLandscapeCompact ? 10 : 14,
      headerTopPadding: isLandscapeCompact ? 8 : 10,
      headerBottomPadding: isLandscapeCompact ? 8 : 10,
      backPadding: isLandscapeCompact ? 6 : 8,
      backRadius: isLandscapeCompact ? 12 : 14,
      backIconSize: isLandscapeCompact ? 22 : 24,
      backSlotWidth: isLandscapeCompact ? 36 : 40,
      titleSize: isLandscapeCompact ? 26 : 34,
      tabsTopGap: isLandscapeCompact ? 6 : 8,
      tabVerticalPadding: isLandscapeCompact ? 6 : 8,
      tabIndicatorWidth: 2.2,
      tabIconSize: isLandscapeCompact ? 18 : 20,
      tabLabelGap: 2,
      tabLabelSize: isLandscapeCompact ? 12 : 14,
      contentPadding: isLandscapeCompact ? 10 : 14,
      maxContentWidth: isLarge ? 960 : 760,
      cardRadius: isLandscapeCompact ? 14 : 18,
      cardPadding: isLandscapeCompact ? 12 : 16,
      sectionGap: isLandscapeCompact ? 10 : 12,
      sectionTitleSize: isLandscapeCompact ? 18 : 20,
      avatarSize: isLandscapeCompact ? 56 : 64,
      avatarTextSize: isLandscapeCompact ? 24 : 28,
      identityGap: isLandscapeCompact ? 10 : 12,
      identityTitleSize: isLandscapeCompact ? 28 : 34,
      identitySubtitleSize: isLandscapeCompact ? 15 : 18,
      editTopGap: isLandscapeCompact ? 10 : 12,
      fieldBlockGap: isLandscapeCompact ? 10 : 12,
      labelGap: isLandscapeCompact ? 4 : 6,
      smallTextSize: isLandscapeCompact ? 13 : 14,
      tinyTextSize: isLandscapeCompact ? 11 : 12,
      buttonsTopGap: isLandscapeCompact ? 10 : 12,
      actionsGap: isLandscapeCompact ? 8 : 10,
      buttonVerticalPadding: isLandscapeCompact ? 10 : 12,
      buttonRadius: isLandscapeCompact ? 12 : 14,
      loaderSize: 16,
      securityGap: isLandscapeCompact ? 10 : 12,
      securityItemGap: isLandscapeCompact ? 8 : 10,
      innerRadius: isLandscapeCompact ? 10 : 12,
      tileHorizontalPadding: isLandscapeCompact ? 10 : 12,
      tileVerticalPadding: isLandscapeCompact ? 10 : 12,
      tileIconSize: isLandscapeCompact ? 18 : 20,
      listItemGap: isLandscapeCompact ? 6 : 8,
      listItemPadding: isLandscapeCompact ? 8 : 10,
      emptyVerticalPadding: isLandscapeCompact ? 46 : 56,
      emptyIconSize: isLandscapeCompact ? 50 : 60,
    );
  }
}
