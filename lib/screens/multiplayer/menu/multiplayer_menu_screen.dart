import 'dart:async';

import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/screens/multiplayer/menu/multiplayer_profile_space_screen.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class MultiplayerMenuScreen extends StatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  State<MultiplayerMenuScreen> createState() => _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends State<MultiplayerMenuScreen> {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  late final FriendsApiService _friendsApi;

  SocialProfile? _profile;
  List<FriendInfo> _friends = <FriendInfo>[];
  List<FriendRequestInfo> _incomingRequests = <FriendRequestInfo>[];
  List<FriendRequestInfo> _outgoingRequests = <FriendRequestInfo>[];
  List<BlockedUserInfo> _blockedUsers = <BlockedUserInfo>[];

  List<SavedRoom> _myRooms = <SavedRoom>[];
  List<Map<String, dynamic>> _activeRooms = <Map<String, dynamic>>[];
  bool _loadingRooms = false;
  bool _showingProfileGate = false;

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    _friendsApi = FriendsApiService(authProvider.authService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    // Vérifier l'authentification
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isInitialized) {
      await authProvider.init();
    }

    if (!mounted) return;

    if (!authProvider.isLoggedIn) {
      // Rediriger vers login
      context.go('/login');
      return;
    }

    // Passer le token Firebase au service multiplayer
    final multiProvider = context.read<MultiplayerGameProvider>();
    final freshToken = await authProvider.getFreshToken();
    multiProvider.setAuthToken(freshToken);
    await multiProvider.init();

    await Future.wait<void>(<Future<void>>[
      _loadSocialData(),
      _loadMyRooms(),
    ]);
  }

  Future<void> _loadSocialData() async {
    final authProvider = context.read<AuthProvider>();

    if (authProvider.isLoggedIn) {
      // Charger depuis le serveur
      final friends = await _friendsApi.getFriends();
      final requests = await _friendsApi.getRequests();
      final blocked = await _friendsApi.getBlockedUsers();

      if (!mounted) return;

      setState(() {
        _profile = SocialProfile(
          displayName: authProvider.user!.displayName,
          username: authProvider.user!.username,
          roomInviteNotificationsEnabled: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _friends = friends;
        _incomingRequests = requests.incoming;
        _outgoingRequests = requests.outgoing;
        _blockedUsers = blocked;
      });
    } else {
      // Fallback local (ne devrait plus arriver avec le redirect)
      final profile = await _socialRepository.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
      });
    }
  }

  Future<void> _loadMyRooms() async {
    setState(() {
      _loadingRooms = true;
    });

    final provider = context.read<MultiplayerGameProvider>();
    final savedRooms = await provider.getMyRooms();

    List<Map<String, dynamic>> activeRooms = <Map<String, dynamic>>[];
    if (savedRooms.isNotEmpty) {
      final roomCodes = savedRooms.map((room) => room.roomCode).toList();
      activeRooms = await provider.checkActiveRooms(roomCodes) ??
          <Map<String, dynamic>>[];
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _myRooms = savedRooms;
      _activeRooms = activeRooms;
      _loadingRooms = false;
    });
  }

  String get _displayName => _profile?.displayName ?? 'Joueur';

  String get _username => _profile?.username ?? 'profil-incomplet';

  Future<bool> _ensureProfileReady() async {
    if (_profile != null) {
      return true;
    }
    await _openProfileDialog(forceCompletion: true);
    return _profile != null;
  }

  Future<void> _openProfileSpace() async {
    if (!await _ensureProfileReady()) {
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MultiplayerProfileSpaceScreen(),
      ),
    );

    if (!mounted) {
      return;
    }
    await Future.wait<void>(<Future<void>>[
      _loadSocialData(),
      _loadMyRooms(),
    ]);
  }

  Future<void> _openProfileDialog({
    required bool forceCompletion,
  }) async {
    if (_showingProfileGate) {
      return;
    }
    _showingProfileGate = true;

    final existingProfile = _profile;
    final nameController = TextEditingController(
      text: existingProfile?.displayName ?? '',
    );
    final usernameController = TextEditingController(
      text: existingProfile?.username ?? '',
    );
    final reservedUsernames = await _socialRepository.getReservedUsernames(
      exceptUsername: existingProfile?.username,
    );

    String? pseudoError;
    String? usernameError;
    bool inviteNotificationsEnabled =
        existingProfile?.roomInviteNotificationsEnabled ?? false;
    bool saving = false;
    Timer? validationDebounce;

    await showDialog<void>(
      context: context,
      barrierDismissible: !forceCompletion,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            String? validatePseudo({required bool checkRequired}) {
              final rawPseudo = nameController.text.trim();
              if (checkRequired && rawPseudo.isEmpty) {
                return 'Le pseudo est requis.';
              }
              if (rawPseudo.length > 24) {
                return 'Maximum 24 caracteres.';
              }
              return null;
            }

            String? validateUsername({required bool checkRequired}) {
              final rawUsername = usernameController.text;
              final normalizedUsername =
                  SocialHubRepository.normalizeUsername(rawUsername);

              if (checkRequired && normalizedUsername.isEmpty) {
                return 'Le nom d utilisateur est requis.';
              }
              if (normalizedUsername.isEmpty) {
                return null;
              }
              if (!SocialHubRepository.containsOnlyAllowedUsernameChars(
                rawUsername,
              )) {
                return 'Caracteres autorises: lettres/chiffres, ., _ et - (accents autorises)';
              }
              if (normalizedUsername.length < 3) {
                return 'Minimum 3 caracteres.';
              }
              if (normalizedUsername.length > 20) {
                return 'Maximum 20 caracteres.';
              }
              if (reservedUsernames.contains(normalizedUsername)) {
                return 'Ce nom d utilisateur existe deja sur cet appareil.';
              }
              return null;
            }

            void runLiveValidation() {
              validationDebounce?.cancel();
              validationDebounce = Timer(const Duration(milliseconds: 80), () {
                if (!dialogContext.mounted) {
                  return;
                }
                setLocalState(() {
                  pseudoError = validatePseudo(checkRequired: false);
                  usernameError = validateUsername(checkRequired: false);
                });
              });
            }

            Future<void> onSave() async {
              if (saving) {
                return;
              }

              final rawName = nameController.text.trim();
              final rawUsername = usernameController.text.trim();
              final normalizedUsername =
                  SocialHubRepository.normalizeUsername(rawUsername);
              final nextPseudoError = validatePseudo(checkRequired: true);
              final nextUsernameError = validateUsername(checkRequired: true);
              if (nextPseudoError != null || nextUsernameError != null) {
                setLocalState(() {
                  pseudoError = nextPseudoError;
                  usernameError = nextUsernameError;
                });
                return;
              }

              setLocalState(() {
                saving = true;
                pseudoError = null;
                usernameError = null;
              });

              final now = DateTime.now();
              final nextProfile = SocialProfile(
                displayName: rawName,
                username: normalizedUsername,
                roomInviteNotificationsEnabled: inviteNotificationsEnabled,
                createdAt: existingProfile?.createdAt ?? now,
                updatedAt: now,
              );
              await _socialRepository.saveProfile(nextProfile);

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (!mounted) {
                return;
              }
              await _loadSocialData();
            }

            return PopScope(
              canPop: !forceCompletion,
              child: AlertDialog(
                backgroundColor: const Color(0xFFF6F4FB),
                title: Text(
                  forceCompletion ? 'Complete ton profil' : 'Mon profil',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
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
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 24,
                          onChanged: (_) => runLiveValidation(),
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ton pseudo',
                            hintStyle:
                                const TextStyle(color: Color(0xFF6B7280)),
                            errorText: pseudoError,
                            filled: true,
                            fillColor: Colors.white,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: pseudoError == null
                                    ? const Color(0xFFD1D5DB)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                width: 1.4,
                                color: pseudoError == null
                                    ? const Color(0xFF4F46E5)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
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
                                controller: usernameController,
                                textCapitalization: TextCapitalization.none,
                                maxLength: 20,
                                onChanged: (_) => runLiveValidation(),
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'pegga.pig',
                                  hintStyle:
                                      const TextStyle(color: Color(0xFF6B7280)),
                                  errorText: usernameError,
                                  filled: true,
                                  fillColor: Colors.white,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: usernameError == null
                                          ? const Color(0xFFD1D5DB)
                                          : const Color(0xFFB91C1C),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      width: 1.4,
                                      color: usernameError == null
                                          ? const Color(0xFF4F46E5)
                                          : const Color(0xFFB91C1C),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: inviteNotificationsEnabled,
                          onChanged: (value) {
                            setLocalState(() {
                              inviteNotificationsEnabled = value;
                            });
                          },
                          title: const Text(
                            'Notifications d invitation de salon',
                            style: TextStyle(color: Color(0xFF111827)),
                          ),
                          subtitle: const Text(
                            'Base locale activee. Push cross-device a brancher cote compte.',
                            style: TextStyle(color: Color(0xFF374151)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  if (!forceCompletion)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop();
                            },
                      child: const Text('Fermer'),
                    ),
                  FilledButton(
                    onPressed: saving ? null : onSave,
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    validationDebounce?.cancel();
    _showingProfileGate = false;
  }

  Future<void> _inviteFriendsToRoom(String roomCode) async {
    if (!await _ensureProfileReady()) {
      return;
    }

    if (_friends.isEmpty) {
      _showSnackBar('Ajoute des amis avant d envoyer des invitations.');
      return;
    }

    final selected = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Inviter des amis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _friends.map((friend) {
                          final checked = selected.contains(friend.username);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selected.add(friend.username);
                                } else {
                                  selected.remove(friend.username);
                                }
                              });
                            },
                            title: Text(friend.displayName),
                            subtitle: Text('@${friend.username}'),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                  },
                            child: const Text('Inviter'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selected.isEmpty) {
      return;
    }

    final invited = selected.map((entry) => '@$entry').join(', ');
    _showSnackBar(
      'Invitations preparees pour la room $roomCode: $invited. Livraison push cross-device a brancher cote comptes.',
    );
  }

  Map<String, dynamic>? _activeRoomInfo(String roomCode) {
    for (final room in _activeRooms) {
      if ((room['roomCode'] as String?) == roomCode) {
        return room;
      }
    }
    return null;
  }

  Future<void> _rejoinRoom(String roomCode) async {
    if (!await _ensureProfileReady()) {
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    try {
      await provider.joinRoom(
        roomCode: roomCode,
        playerName: _displayName,
      );
      if (!mounted || provider.roomCode == null) {
        return;
      }
      context.go('/lobby');
    } catch (error) {
      _showSnackBar(error.toString(), isError: true);
    }
  }

  Future<void> _removeSavedRoom(String roomCode) async {
    final provider = context.read<MultiplayerGameProvider>();
    await provider.removeRoom(roomCode);
    await _loadMyRooms();
    _showSnackBar('Room $roomCode retiree de Mes salons.');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientBottom,
      body: Stack(
        children: <Widget>[
          Container(
            decoration: AppDecorations.pageBackground,
            child: const SizedBox.expand(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: <Widget>[
                  _buildHeader(context),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 980;
                        if (isDesktop) {
                          return Row(
                            children: <Widget>[
                              Expanded(
                                flex: 11,
                                child: Column(
                                  children: <Widget>[
                                    Expanded(
                                      child: _buildActionTile(
                                        icon: Icons.add_home_work_rounded,
                                        title: 'Creer un salon',
                                        subtitle:
                                            'Lance un salon prive ou public et invite ton groupe.',
                                        accent: AppColors.primary,
                                        onTap: () async {
                                          if (!await _ensureProfileReady()) {
                                            return;
                                          }
                                          if (!context.mounted) {
                                            return;
                                          }
                                          context.go(
                                              '/multiplayer/create-selection');
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Expanded(
                                      child: _buildActionTile(
                                        icon: Icons.door_front_door_outlined,
                                        title: 'Rejoindre un salon',
                                        subtitle:
                                            'Code prive, matchmaking public, ou reprise d un salon.',
                                        accent: AppColors.primaryDark,
                                        onTap: () async {
                                          if (!await _ensureProfileReady()) {
                                            return;
                                          }
                                          if (!context.mounted) {
                                            return;
                                          }
                                          context.go(
                                              '/multiplayer/join-selection');
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 10,
                                child: Column(
                                  children: <Widget>[
                                    _buildProfileCard(),
                                    const SizedBox(height: 14),
                                    Expanded(child: _buildMyRoomsCard()),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        return ListView(
                          children: <Widget>[
                            SizedBox(
                              height: 168,
                              child: _buildActionTile(
                                icon: Icons.add_home_work_rounded,
                                title: 'Creer un salon',
                                subtitle:
                                    'Lance un salon prive ou public et invite ton groupe.',
                                accent: AppColors.primary,
                                onTap: () async {
                                  if (!await _ensureProfileReady()) {
                                    return;
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  context.go('/multiplayer/create-selection');
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 168,
                              child: _buildActionTile(
                                icon: Icons.door_front_door_outlined,
                                title: 'Rejoindre un salon',
                                subtitle:
                                    'Code prive, matchmaking public, ou reprise d un salon.',
                                accent: AppColors.primaryDark,
                                onTap: () async {
                                  if (!await _ensureProfileReady()) {
                                    return;
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  context.go('/multiplayer/join-selection');
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildProfileCard(),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 420,
                              child: _buildMyRoomsCard(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final pendingCount = _incomingRequests.length + _outgoingRequests.length;
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/'),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Multijoueur',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Rye',
              fontSize: 34,
              letterSpacing: 0.4,
            ),
          ),
        ),
        _pill(
          icon: Icons.person_outline,
          label: '@$_username',
        ),
        const SizedBox(width: 8),
        _pill(
          icon: Icons.group_outlined,
          label: '${_friends.length} amis',
        ),
        if (pendingCount > 0) ...<Widget>[
          const SizedBox(width: 8),
          _pill(
            icon: Icons.mark_email_unread_outlined,
            label: '$pendingCount demandes',
            color: const Color(0xFF0F766E),
          ),
        ],
      ],
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    Color color = const Color(0x1FFFFFFF),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required Future<void> Function() onTap,
  }) {
    return _glassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      accent.withValues(alpha: 0.94),
                      accent.withValues(alpha: 0.62),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.38),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const Spacer(),
              const Row(
                children: <Widget>[
                  Text(
                    'Ouvrir',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final profile = _profile;
    return _glassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openProfileSpace,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.account_circle,
                      color: Colors.white, size: 26),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Mon profil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openProfileSpace,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Ouvrir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                profile == null ? 'Profil non complete' : profile.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '@${profile?.username ?? 'a-completer'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _statChip(Icons.group, '${_friends.length} amis'),
                  _statChip(
                      Icons.mail_outline, '${_incomingRequests.length} recues'),
                  _statChip(Icons.send_outlined,
                      '${_outgoingRequests.length} envoyees'),
                  _statChip(
                      Icons.block_outlined, '${_blockedUsers.length} bloques'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Ouvre ton espace profil pour modifier ton pseudo, ton nom d utilisateur, gerer les demandes et voir tes salons hote.',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white70),
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

  Widget _buildMyRoomsCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.meeting_room_outlined, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mes salons',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loadingRooms ? null : _loadMyRooms,
                  icon:
                      const Icon(Icons.refresh_rounded, color: Colors.white70),
                  tooltip: 'Rafraichir',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Salons en attente / arriere-plan. Tu peux rejoindre sans les supprimer de ta liste.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loadingRooms
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.2))
                  : _myRooms.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun salon enregistre.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _myRooms.length,
                          itemBuilder: (context, index) {
                            final room = _myRooms[index];
                            final activeInfo = _activeRoomInfo(room.roomCode);
                            final status =
                                activeInfo?['status'] as String? ?? 'offline';
                            final playerCount =
                                activeInfo?['playerCount'] as int?;

                            final isActive = status != 'offline';
                            final statusLabel = switch (status) {
                              'waiting' => 'En attente',
                              'playing' => 'En cours',
                              'ended' => 'Termine',
                              'closing' => 'Fermeture',
                              _ => 'Hors ligne',
                            };

                            final statusColor = isActive
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF9CA3AF);

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: <Widget>[
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.14),
                                    child: Icon(
                                      room.isHost ? Icons.star : Icons.group,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Text(
                                              room.roomCode,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                    alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: statusColor.withValues(
                                                      alpha: 0.6),
                                                ),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          room.isHost
                                              ? 'Hote • ${playerCount ?? 0} joueur(s)'
                                              : 'Participant • ${playerCount ?? 0} joueur(s)',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: isActive
                                        ? () => _rejoinRoom(room.roomCode)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const Text('Rejoindre'),
                                  ),
                                  PopupMenuButton<String>(
                                    iconColor: Colors.white70,
                                    onSelected: (action) {
                                      if (action == 'remove_saved') {
                                        _removeSavedRoom(room.roomCode);
                                      } else if (action == 'invite_friends') {
                                        _inviteFriendsToRoom(room.roomCode);
                                      }
                                    },
                                    itemBuilder: (context) =>
                                        <PopupMenuEntry<String>>[
                                      const PopupMenuItem(
                                        value: 'invite_friends',
                                        child: Text('Inviter des amis'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove_saved',
                                        child: Text('Retirer de Mes salons'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 9),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
