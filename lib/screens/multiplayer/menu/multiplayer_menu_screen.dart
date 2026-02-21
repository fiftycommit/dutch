import 'dart:async';

import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/screens/multiplayer/menu/multiplayer_profile_space_screen.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class MultiplayerMenuScreen extends StatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  State<MultiplayerMenuScreen> createState() => _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends State<MultiplayerMenuScreen> {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  late final FriendsApiService _friendsApi;
  final LayerLink _userMenuAnchor = LayerLink();

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
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isLarge = width >= 1100;
    final isLandscapeMobile =
        !isLarge && media.orientation == Orientation.landscape && width >= 700;
    final compactHeader = width < 980;

    final themed = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            Container(
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
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isLarge ? 14 : 12,
                  isLarge ? 12 : 10,
                  isLarge ? 14 : 12,
                  12,
                ),
                child: Column(
                  children: <Widget>[
                    _buildHeader(compact: compactHeader),
                    SizedBox(height: isLarge ? 14 : 12),
                    Expanded(
                      child: isLarge
                          ? _buildDesktopSplitLayout()
                          : isLandscapeMobile
                              ? _buildMobileLandscapeLayout()
                              : _buildMobilePortraitLayout(),
                    ),
                  ],
                ),
              ),
            ),
            if (_showUserMenu) ...<Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (!mounted) return;
                    setState(() => _showUserMenu = false);
                  },
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: CompositedTransformFollower(
                    link: _userMenuAnchor,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomRight,
                    followerAnchor: Alignment.topRight,
                    offset: const Offset(0, 10),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _buildUserMenuPanel(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateSelection() async {
    if (!await _ensureProfileReady()) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.push('/multiplayer/create-selection');
  }

  Future<void> _openJoinSelection() async {
    if (!await _ensureProfileReady()) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.push('/multiplayer/join-selection');
  }

  Widget _buildHeader({required bool compact}) {
    final pendingCount = _incomingRequests.length + _outgoingRequests.length;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _backButton(),
              const SizedBox(width: 12),
              _title(),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _buildUserPill(),
                const SizedBox(width: 8),
                _pillButton(
                  icon: Icons.group_outlined,
                  label: '${_friends.length} amis',
                  onTap: () {
                    unawaited(
                      _openProfileSpaceWithTab(MultiplayerProfileTab.friends),
                    );
                  },
                ),
                if (pendingCount > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  _pillButton(
                    icon: Icons.mark_email_unread_outlined,
                    label: '$pendingCount demandes',
                    onTap: () {
                      unawaited(
                        _openProfileSpaceWithTab(MultiplayerProfileTab.friends),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
            child: Row(children: <Widget>[
          _backButton(),
          const SizedBox(width: 12),
          _title()
        ])),
        const SizedBox(width: 10),
        _buildUserPill(),
        const SizedBox(width: 8),
        _pillButton(
          icon: Icons.group_outlined,
          label: '${_friends.length} amis',
          onTap: () {
            unawaited(_openProfileSpaceWithTab(MultiplayerProfileTab.friends));
          },
        ),
        if (pendingCount > 0) ...<Widget>[
          const SizedBox(width: 8),
          _pillButton(
            icon: Icons.mark_email_unread_outlined,
            label: '$pendingCount demandes',
            onTap: () {
              unawaited(
                  _openProfileSpaceWithTab(MultiplayerProfileTab.friends));
            },
          ),
        ],
      ],
    );
  }

  Widget _backButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _handleBackToHome,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.arrow_back, size: 24, color: Color(0xFF334155)),
        ),
      ),
    );
  }

  Widget _title() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          colors: <Color>[
            Color(0xFF4F46E5),
            Color(0xFF7C3AED),
            Color(0xFF2563EB)
          ],
        ).createShader(bounds);
      },
      child: const Text(
        'Multijoueur',
        style: TextStyle(
          color: Colors.white,
          fontSize: 46,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildUserPill() {
    return CompositedTransformTarget(
      link: _userMenuAnchor,
      child: _pillButton(
        icon: Icons.person_outline,
        label: '@$_username',
        withChevron: true,
        chevronUp: _showUserMenu,
        onTap: () {
          setState(() => _showUserMenu = !_showUserMenu);
        },
      ),
    );
  }

  Widget _buildUserMenuPanel() {
    return AnimatedOpacity(
      opacity: _showUserMenu ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: AnimatedScale(
        scale: _showUserMenu ? 1 : 0.96,
        alignment: Alignment.topRight,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 248,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
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
                          fontSize: 32,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        '@$_username',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
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
                  color: const Color(0xFFDC2626),
                  onTap: _logout,
                ),
              ],
            ),
          ),
        ),
      ),
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool withChevron = false,
    bool chevronUp = false,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: const Color(0xFF334155)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              if (withChevron) ...<Widget>[
                const SizedBox(width: 6),
                Icon(
                  chevronUp ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: const Color(0xFF334155),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required Future<void> Function() onTap,
    bool compact = false,
    bool centerVertically = false,
  }) {
    final iconSize = compact ? 24.0 : 28.0;
    final iconBox = compact ? 52.0 : 58.0;
    final titleSize = compact ? 16.0 : 20.0;
    final subtitleSize = compact ? 14.0 : 16.0;
    final actionSize = compact ? 14.0 : 16.0;

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: iconBox,
          height: iconBox,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
            gradient: LinearGradient(
              colors: <Color>[
                accent.withValues(alpha: 0.95),
                accent.withValues(alpha: 0.72),
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.25),
                blurRadius: compact ? 10 : 14,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
        SizedBox(width: compact ? 12 : 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF334155),
                  fontSize: titleSize,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: const Color(0xFF475569),
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              Row(
                children: <Widget>[
                  Text(
                    'Ouvrir',
                    style: TextStyle(
                      color: const Color(0xFF4F46E5),
                      fontWeight: FontWeight.w500,
                      fontSize: actionSize,
                    ),
                  ),
                  SizedBox(width: compact ? 5 : 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: const Color(0xFF4F46E5),
                    size: compact ? 17 : 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: compact ? 12 : 16,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          onTap: () async => onTap(),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: centerVertically
                ? SizedBox.expand(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: rowContent,
                    ),
                  )
                : rowContent,
          ),
        ),
      ),
    );
  }

  Widget _buildMyRoomsCard({
    required String helperText,
    required String emptyLabel,
    bool compact = false,
  }) {
    final headerSize = compact ? 14.0 : 20.0;
    final helperSize = compact ? 12.0 : 13.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: compact ? 12 : 16,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 10 : 14,
            compact ? 12 : 16, compact ? 8 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.meeting_room_outlined,
                  color: const Color(0xFF4F46E5),
                  size: compact ? 18 : 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mes salons',
                    style: TextStyle(
                      color: const Color(0xFF334155),
                      fontSize: headerSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loadingRooms ? null : _loadMyRooms,
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: compact ? 20 : 22,
                    color: const Color(0xFF4F46E5),
                  ),
                  tooltip: 'Rafraichir',
                ),
              ],
            ),
            Text(
              helperText,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontSize: helperSize,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loadingRooms
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF4F46E5),
                      ),
                    )
                  : _myRooms.isEmpty
                      ? Center(
                          child: Text(
                            emptyLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF64748B),
                              fontSize: compact ? 12 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _myRooms.length,
                          itemBuilder: (context, index) => _buildRoomTile(
                            room: _myRooms[index],
                            compact: compact,
                          ),
                          separatorBuilder: (_, __) =>
                              SizedBox(height: compact ? 7 : 9),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTile({
    required SavedRoom room,
    required bool compact,
  }) {
    final activeInfo = _activeRoomInfo(room.roomCode);
    final status = activeInfo?['status'] as String? ?? 'offline';
    final playerCount = activeInfo?['playerCount'] as int?;

    final isActive = status != 'offline';
    final statusLabel = switch (status) {
      'waiting' => 'En attente',
      'playing' => 'En cours',
      'ended' => 'Terminé',
      'closing' => 'Fermeture',
      _ => 'Hors ligne',
    };
    final statusColor =
        isActive ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: compact ? 16 : 20,
            backgroundColor: const Color(0x14F59E0B),
            child: Icon(
              room.isHost ? Icons.star : Icons.group,
              size: compact ? 16 : 20,
              color: const Color(0xFFB45309),
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      room.roomCode,
                      style: TextStyle(
                        color: const Color(0xFF334155),
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 12 : 13,
                        letterSpacing: compact ? 1.5 : 2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: compact ? 10 : 11,
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
                  style: TextStyle(
                    color: const Color(0xFF64748B),
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          FilledButton(
            onPressed: isActive ? () => _rejoinRoom(room.roomCode) : null,
            style: FilledButton.styleFrom(
              visualDensity:
                  compact ? VisualDensity.compact : VisualDensity.standard,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 8 : 10,
              ),
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Rejoindre',
              style: TextStyle(fontSize: compact ? 11 : 12),
            ),
          ),
          PopupMenuButton<String>(
            iconColor: const Color(0xFF64748B),
            onSelected: (action) {
              if (action == 'remove_saved') {
                _removeSavedRoom(room.roomCode);
              } else if (action == 'invite_friends') {
                _inviteFriendsToRoom(room.roomCode);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
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
  }

  Widget _buildMobilePortraitLayout() {
    return ListView(
      children: <Widget>[
        _buildMenuActionCard(
          icon: Icons.home_outlined,
          title: 'Créer un salon',
          subtitle: 'Lance un salon privé ou public et invite ton groupe.',
          accent: const Color(0xFFF59E0B),
          onTap: _openCreateSelection,
        ),
        const SizedBox(height: 12),
        _buildMenuActionCard(
          icon: Icons.lock_open_rounded,
          title: 'Rejoindre un salon',
          subtitle:
              'Saisis un code privé ou rejoins une partie publique disponible.',
          accent: const Color(0xFFF97316),
          onTap: _openJoinSelection,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 430,
          child: _buildMyRoomsCard(
            helperText:
                'Salons en attente / arrière-plan. Tu peux rejoindre sans les supprimer de la liste.',
            emptyLabel: 'Aucun salon enregistré.',
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLandscapeLayout() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              Expanded(
                child: _buildMenuActionCard(
                  icon: Icons.home_outlined,
                  title: 'Créer un salon',
                  subtitle: 'Lance un salon privé ou public.',
                  accent: const Color(0xFFF59E0B),
                  compact: true,
                  centerVertically: true,
                  onTap: _openCreateSelection,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _buildMenuActionCard(
                  icon: Icons.lock_open_rounded,
                  title: 'Rejoindre un salon',
                  subtitle: 'Code privé ou partie publique.',
                  accent: const Color(0xFFF97316),
                  compact: true,
                  centerVertically: true,
                  onTap: _openJoinSelection,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMyRoomsCard(
            helperText:
                'Salons en attente. Tu peux rejoindre sans les supprimer.',
            emptyLabel: 'Aucun salon',
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSplitLayout() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              Expanded(
                child: _buildMenuActionCard(
                  icon: Icons.home_outlined,
                  title: 'Créer un salon',
                  subtitle: 'Lance un salon privé ou public.',
                  accent: const Color(0xFFF59E0B),
                  centerVertically: true,
                  onTap: _openCreateSelection,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _buildMenuActionCard(
                  icon: Icons.lock_open_rounded,
                  title: 'Rejoindre un salon',
                  subtitle: 'Code privé ou partie publique.',
                  accent: const Color(0xFFF97316),
                  centerVertically: true,
                  onTap: _openJoinSelection,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildMyRoomsCard(
            helperText:
                'Salons en attente. Tu peux rejoindre sans les supprimer.',
            emptyLabel: 'Aucun salon',
          ),
        ),
      ],
    );
  }
}
