import 'dart:async';

import 'package:dutch_game/screens/multiplayer/ui/multiplayer_motion.dart';
import 'package:dutch_game/screens/multiplayer/ui/multiplayer_ui_tokens.dart';
import 'package:dutch_game/screens/multiplayer/ui/multiplayer_ui_widgets.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/screens/multiplayer/menu/multiplayer_profile_space_screen.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
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

  List<SavedRoom> _myRooms = <SavedRoom>[];
  List<Map<String, dynamic>> _activeRooms = <Map<String, dynamic>>[];
  bool _loadingRooms = false;
  bool _showingProfileGate = false;
  bool _showUserMenu = false;

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
    var authProvider = context.read<AuthProvider>();
    if (!authProvider.isInitialized) {
      await authProvider.init();
    }

    if (!mounted) return;

    if (!authProvider.isLoggedIn) {
      final loggedIn = await context.push<bool>('/login');
      if (!mounted) return;
      if (loggedIn != true) {
        final didPop = await Navigator.of(context).maybePop();
        if (!didPop && mounted) {
          context.go('/');
        }
        return;
      }
      authProvider = context.read<AuthProvider>();
      if (!authProvider.isLoggedIn) {
        final didPop = await Navigator.of(context).maybePop();
        if (!didPop && mounted) {
          context.go('/');
        }
        return;
      }
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

  Future<void> _openProfileSpaceWithTab(MultiplayerProfileTab tab) async {
    if (!await _ensureProfileReady()) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _showUserMenu = false);

    final route = defaultTargetPlatform == TargetPlatform.iOS
        ? CupertinoPageRoute<void>(
            builder: (_) => MultiplayerProfileSpaceScreen(initialTab: tab),
          )
        : MaterialPageRoute<void>(
            builder: (_) => MultiplayerProfileSpaceScreen(initialTab: tab),
          );
    await Navigator.of(context).push<void>(route);

    if (!mounted) {
      return;
    }
    await Future.wait<void>(<Future<void>>[
      _loadSocialData(),
      _loadMyRooms(),
    ]);
  }

  Future<void> _logout() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.logout();
    if (!mounted) return;
    setState(() {
      _showUserMenu = false;
    });
    final didPop = await Navigator.of(context).maybePop(true);
    if (!didPop && mounted) {
      context.go('/');
    }
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

  Future<void> _handleBackToHome() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = MultiplayerUiTokens.motionEnabled(context);
    final orientation = MediaQuery.of(context).orientation;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Container(
            decoration: MultiplayerUiTokens.pageBg,
            child: const SizedBox.expand(),
          ),
          if (_showUserMenu)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (!mounted) return;
                  setState(() => _showUserMenu = false);
                },
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: <Widget>[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 780;
                      return _buildHeader(compact: compact);
                    },
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useTwoColumns = constraints.maxWidth >= 980 ||
                            (orientation == Orientation.landscape &&
                                constraints.maxWidth >= 700);

                        if (useTwoColumns) {
                          return Row(
                            children: <Widget>[
                              Expanded(
                                flex: 10,
                                child: Column(
                                  children: <Widget>[
                                    Expanded(
                                      child: fadeInUp(
                                        delay: motionEnabled
                                            ? staggerIndexDelay(0)
                                            : Duration.zero,
                                        child: _buildActionTile(
                                          icon: Icons.home_outlined,
                                          title: 'Créer un salon',
                                          subtitle:
                                              'Lance un salon privé ou public.',
                                          accent: AppColors.primary,
                                          onTap: () async {
                                            if (!await _ensureProfileReady()) {
                                              return;
                                            }
                                            if (!context.mounted) {
                                              return;
                                            }
                                            await context.push(
                                              '/multiplayer/create-selection',
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Expanded(
                                      child: fadeInUp(
                                        delay: motionEnabled
                                            ? staggerIndexDelay(1)
                                            : Duration.zero,
                                        child: _buildActionTile(
                                          icon: Icons.lock_open_rounded,
                                          title: 'Rejoindre un salon',
                                          subtitle:
                                              'Code privé, matchmaking public, ou reprise.',
                                          accent: AppColors.primaryDark,
                                          onTap: () async {
                                            if (!await _ensureProfileReady()) {
                                              return;
                                            }
                                            if (!context.mounted) {
                                              return;
                                            }
                                            await context.push(
                                              '/multiplayer/join-selection',
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 9,
                                child: fadeInUp(
                                  delay: motionEnabled
                                      ? staggerIndexDelay(2)
                                      : Duration.zero,
                                  child: _buildMyRoomsCard(),
                                ),
                              ),
                            ],
                          );
                        }

                        return ListView(
                          children: <Widget>[
                            fadeInUp(
                              delay: motionEnabled
                                  ? staggerIndexDelay(0)
                                  : Duration.zero,
                              child: _buildActionTile(
                                icon: Icons.home_outlined,
                                title: 'Créer un salon',
                                subtitle: 'Lance un salon privé ou public.',
                                accent: AppColors.primary,
                                onTap: () async {
                                  if (!await _ensureProfileReady()) {
                                    return;
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  await context.push(
                                    '/multiplayer/create-selection',
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            fadeInUp(
                              delay: motionEnabled
                                  ? staggerIndexDelay(1)
                                  : Duration.zero,
                              child: _buildActionTile(
                                icon: Icons.lock_open_rounded,
                                title: 'Rejoindre un salon',
                                subtitle:
                                    'Code privé, matchmaking public, ou reprise.',
                                accent: AppColors.primaryDark,
                                onTap: () async {
                                  if (!await _ensureProfileReady()) {
                                    return;
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  await context.push(
                                    '/multiplayer/join-selection',
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            fadeInUp(
                              delay: motionEnabled
                                  ? staggerIndexDelay(2)
                                  : Duration.zero,
                              child: SizedBox(
                                height: 440,
                                child: _buildMyRoomsCard(),
                              ),
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

  Widget _buildHeader({required bool compact}) {
    final pendingCount = _incomingRequests.length + _outgoingRequests.length;
    final pills = <Widget>[
      _buildUserPill(),
      MpPill(
        icon: Icons.group_outlined,
        label: '${_friends.length} amis',
        onTap: () => _openProfileSpaceWithTab(MultiplayerProfileTab.friends),
      ),
      if (pendingCount > 0)
        MpPill(
          icon: Icons.mark_email_unread_outlined,
          label: '$pendingCount demandes',
          onTap: () => _openProfileSpaceWithTab(MultiplayerProfileTab.friends),
        ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MpHeader(
            title: 'Multijoueur',
            onBack: _handleBackToHome,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ...pills.expand((w) sync* {
                  yield w;
                  yield const SizedBox(width: 8);
                }),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: MpHeader(
            title: 'Multijoueur',
            onBack: _handleBackToHome,
          ),
        ),
        const SizedBox(width: 10),
        ...pills.expand((w) sync* {
          yield w;
          yield const SizedBox(width: 8);
        }),
      ],
    );
  }

  Widget _buildUserPill() {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        MpPill(
          icon: Icons.person_outline,
          label: '@$_username',
          onTap: () {
            setState(() => _showUserMenu = !_showUserMenu);
          },
        ),
        Positioned(
          top: 50,
          right: 0,
          child: dropdownScaleFade(
            visible: _showUserMenu,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFFECEFF6),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 0.3,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _displayName,
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            '@$_username',
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _menuAction(
                      icon: Icons.account_circle_outlined,
                      label: 'Mon Profil',
                      onTap: () => _openProfileSpaceWithTab(
                        MultiplayerProfileTab.profile,
                      ),
                    ),
                    _menuAction(
                      icon: Icons.group_outlined,
                      label: 'Mes Amis',
                      onTap: () => _openProfileSpaceWithTab(
                        MultiplayerProfileTab.friends,
                      ),
                    ),
                    _menuAction(
                      icon: Icons.logout_rounded,
                      label: 'Déconnexion',
                      color: const Color(0xFFB91C1C),
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuAction({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
    Color color = const Color(0xFF1F2937),
  }) {
    return InkWell(
      onTap: () async {
        await onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
    return MpActionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accent: accent,
      onTap: onTap,
    );
  }

  Widget _buildMyRoomsCard() {
    return MpSectionCard(
      icon: Icons.meeting_room_outlined,
      title: 'Mes salons',
      trailing: IconButton(
        onPressed: _loadingRooms ? null : _loadMyRooms,
        icon: const Icon(
          Icons.refresh_rounded,
          color: MultiplayerUiTokens.onSurfacePrimary,
        ),
        tooltip: 'Rafraichir',
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Salons en attente. Tu peux les rejoindre sans les supprimer de ta liste.',
            style: TextStyle(
              color: MultiplayerUiTokens.onSurfaceSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loadingRooms
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  )
                : _myRooms.isEmpty
                    ? const MpEmptyState(
                        icon: Icons.meeting_room_outlined,
                        title: 'Aucun salon',
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
                            'ended' => 'Terminé',
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
                              color: Colors.white.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.2),
                                  child: Icon(
                                    room.isHost ? Icons.star : Icons.group,
                                    color: const Color(0xFFB45309),
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
                                              color: MultiplayerUiTokens
                                                  .onSurfacePrimary,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
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
                                                  alpha: 0.6,
                                                ),
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
                                            ? 'Hôte • ${playerCount ?? 0} joueur(s)'
                                            : 'Participant • ${playerCount ?? 0} joueur(s)',
                                        style: const TextStyle(
                                          color: MultiplayerUiTokens
                                              .onSurfaceSecondary,
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
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Rejoindre'),
                                ),
                                PopupMenuButton<String>(
                                  iconColor:
                                      MultiplayerUiTokens.onSurfaceSecondary,
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
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                      ),
          ),
        ],
      ),
    );
  }
}
