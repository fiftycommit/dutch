import 'dart:async';

import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/widgets/card_rain_background.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/screens/multiplayer/menu/multiplayer_profile_space_screen.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:dutch_game/core/service_locator.dart';
import 'package:dutch_game/core/interfaces/i_haptic_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class MultiplayerMenuScreen extends StatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  State<MultiplayerMenuScreen> createState() => _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends State<MultiplayerMenuScreen>
    with SingleTickerProviderStateMixin {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  late final FriendsApiService _friendsApi;
  final GlobalKey _userPillKey = GlobalKey();

  MultiplayerColorScheme get _cs => MultiplayerColors.of(context);
  late final AnimationController _incomingRequestPulseController;

  SocialProfile? _profile;
  List<FriendInfo> _friends = <FriendInfo>[];
  List<FriendRequestInfo> _incomingRequests = <FriendRequestInfo>[];

  List<SavedRoom> _myRooms = <SavedRoom>[];
  List<Map<String, dynamic>> _activeRooms = <Map<String, dynamic>>[];
  bool _loadingRooms = false;
  bool _roomsLoadedOnce = false;
  bool _showingProfileGate = false;
  bool _showUserMenu = false;

  @override
  void initState() {
    super.initState();
    _incomingRequestPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    final authProvider = context.read<AuthProvider>();
    _friendsApi = FriendsApiService(authProvider.authService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Écouter les auto-joins (ami qui nous ajoute) pour rafraîchir "Mes salons"
      context.read<MultiplayerGameProvider>().onRoomAutoJoined = (roomCode) {
        if (mounted) unawaited(_loadMyRooms());
      };
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

    // Hydrater le profil UI immédiatement depuis l'état auth (pas de réseau)
    setState(() {
      _profile = _buildProfileFromAuth(authProvider);
    });

    // Passer le token Firebase au service multiplayer
    final multiProvider = context.read<MultiplayerGameProvider>();
    final freshToken = await authProvider.getFreshToken();
    multiProvider.setAuthToken(freshToken);
    await Future.wait<void>(<Future<void>>[
      multiProvider.init(),
      _loadSocialData(),
      _loadMyRooms(),
    ]);

    // Si on arrive depuis une notification "Invitation salon", rejoindre directement
    if (!mounted) return;
    final joinRoomCode =
        GoRouterState.of(context).uri.queryParameters['joinRoom'];
    if (joinRoomCode != null && joinRoomCode.isNotEmpty) {
      final playerName = _profile?.displayName.trim().isNotEmpty == true
          ? _profile!.displayName
          : 'Joueur';
      try {
        await multiProvider.joinRoom(
            roomCode: joinRoomCode, playerName: playerName);
        if (mounted) context.push('/lobby');
      } catch (_) {
        // Silencieux — le salon peut être plein ou expiré
      }
    }
  }

  Future<void> _loadSocialData() async {
    final authProvider = context.read<AuthProvider>();

    if (!authProvider.isLoggedIn) {
      // Fallback local (ne devrait plus arriver avec le redirect)
      final profile = await _socialRepository.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _friends = <FriendInfo>[];
        _incomingRequests = <FriendRequestInfo>[];
      });
      _syncIncomingRequestPulse();
      return;
    }

    // Consomme le prefetch lancé au login, ou fait un appel normal
    final summary = await _friendsApi.getSummaryOrPrefetched();

    if (!mounted) return;

    setState(() {
      _friends = summary.friends;
      _incomingRequests = summary.incoming;
    });
    _syncIncomingRequestPulse();
  }

  void _syncIncomingRequestPulse() {
    final hasIncoming = _incomingRequests.isNotEmpty;
    if (hasIncoming) {
      if (!_incomingRequestPulseController.isAnimating) {
        _incomingRequestPulseController.repeat(reverse: true);
      }
      return;
    }
    _incomingRequestPulseController.stop();
    _incomingRequestPulseController.value = 0;
  }

  SocialProfile _buildProfileFromAuth(AuthProvider authProvider) {
    final now = DateTime.now();
    final user = authProvider.user;
    final current = _profile;
    final displayName = user?.displayName.trim().isNotEmpty == true
        ? user!.displayName.trim()
        : (current?.displayName.isNotEmpty == true
            ? current!.displayName
            : 'Joueur');
    final username = user?.username.trim().isNotEmpty == true
        ? user!.username.trim()
        : (current?.username.isNotEmpty == true ? current!.username : 'joueur');

    return SocialProfile(
      displayName: displayName,
      username: username,
      roomInviteNotificationsEnabled:
          current?.roomInviteNotificationsEnabled ?? true,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _loadMyRooms() async {
    // Spinner uniquement lors d'un refresh manuel, pas au premier chargement
    if (_roomsLoadedOnce) {
      setState(() {
        _loadingRooms = true;
      });
    }

    final provider = context.read<MultiplayerGameProvider>();
    final myActiveRooms = await provider.getMyActiveRooms();

    List<Map<String, dynamic>> activeRooms = <Map<String, dynamic>>[];
    List<SavedRoom> visibleRooms = <SavedRoom>[];

    if (myActiveRooms != null) {
      final activeByCode = <String, Map<String, dynamic>>{};
      for (final room in myActiveRooms) {
        final code = ((room['roomCode'] as String?) ?? '').toUpperCase();
        if (code.isEmpty) continue;
        final status = (room['status'] as String?)?.toLowerCase();
        if (status == 'offline') continue;
        activeByCode[code] = Map<String, dynamic>.from(room);
      }

      activeRooms = activeByCode.values.toList();
      visibleRooms = activeRooms
          .map(
            (room) => SavedRoom(
              roomCode: ((room['roomCode'] as String?) ?? '').toUpperCase(),
              isHost: room['isHost'] == true,
              joinedAt: DateTime.now(),
            ),
          )
          .where((room) => room.roomCode.isNotEmpty)
          .toList();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _myRooms = visibleRooms;
      _activeRooms = activeRooms;
      _loadingRooms = false;
      _roomsLoadedOnce = true;
    });
  }

  String get _displayName => _profile?.displayName ?? 'Joueur';

  String get _username => _profile?.username ?? 'profil-incomplet';

  Future<bool> _ensureProfileReady() async {
    if (_profile != null) {
      return true;
    }

    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn) {
      if (!mounted) return false;
      setState(() {
        _profile = _buildProfileFromAuth(authProvider);
      });
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

    try {
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
                validationDebounce =
                    Timer(const Duration(milliseconds: 80), () {
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

              final dlgCs = MultiplayerColors.of(context);
              return PopScope(
                canPop: !forceCompletion,
                child: AlertDialog(
                  backgroundColor: dlgCs.surface,
                  title: Text(
                    forceCompletion ? 'Complete ton profil' : 'Mon profil',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: dlgCs.textPrimary,
                    ),
                  ),
                  content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Pseudo',
                            style: TextStyle(
                              color: dlgCs.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameController,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 24,
                            onChanged: (_) => runLiveValidation(),
                            style: TextStyle(
                              color: dlgCs.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ton pseudo',
                              hintStyle: TextStyle(color: dlgCs.textSecondary),
                              errorText: pseudoError,
                              filled: true,
                              fillColor: dlgCs.surfaceHigh,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: pseudoError == null
                                      ? dlgCs.separator
                                      : dlgCs.danger,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  width: 1.4,
                                  color: pseudoError == null
                                      ? dlgCs.primary
                                      : dlgCs.danger,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nom d utilisateur',
                            style: TextStyle(
                              color: dlgCs.textPrimary,
                              fontWeight: FontWeight.bold,
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
                                child: Text(
                                  '@',
                                  style: TextStyle(
                                    color: dlgCs.textPrimary,
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
                                  style: TextStyle(
                                    color: dlgCs.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'pegga.pig',
                                    hintStyle:
                                        TextStyle(color: dlgCs.textSecondary),
                                    errorText: usernameError,
                                    filled: true,
                                    fillColor: dlgCs.surfaceHigh,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: usernameError == null
                                            ? dlgCs.separator
                                            : dlgCs.danger,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        width: 1.4,
                                        color: usernameError == null
                                            ? dlgCs.primary
                                            : dlgCs.danger,
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
                            title: Text(
                              'Notifications d invitation de salon',
                              style: TextStyle(color: dlgCs.textPrimary),
                            ),
                            subtitle: Text(
                              'Base locale activee. Push cross-device a brancher cote compte.',
                              style: TextStyle(color: dlgCs.textSecondary),
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
                      onPressed: saving
                          ? null
                          : () {
                              ServiceLocator()
                                  .get<IHapticService>()
                                  .buttonTap();
                              onSave();
                            },
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
    } finally {
      _showingProfileGate = false;
    }
  }

  Future<void> _inviteFriendsToRoom(String roomCode) async {
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
                        fontWeight: FontWeight.bold,
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
                                    ServiceLocator()
                                        .get<IHapticService>()
                                        .buttonTap();
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
    final normalized = roomCode.toUpperCase();
    for (final room in _activeRooms) {
      final activeCode = ((room['roomCode'] as String?) ?? '').toUpperCase();
      if (activeCode == normalized) {
        return room;
      }
    }
    return null;
  }

  Future<void> _rejoinRoom(String roomCode) async {
    final provider = context.read<MultiplayerGameProvider>();
    final normalizedTarget = roomCode.toUpperCase();
    final currentCode = provider.roomCode?.toUpperCase();
    if (currentCode == normalizedTarget &&
        (provider.isInLobby || provider.isPlaying)) {
      if (!mounted) return;
      context.go('/lobby');
      return;
    }

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
    try {
      await provider.removeRoom(roomCode);
      await _loadMyRooms();
      _showSnackBar('Room $roomCode retiree de Mes salons.');
    } catch (error) {
      _showSnackBar(error.toString(), isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    const statusUrl = 'https://downdetector.com/status/firebase/';
    final hasStatusUrl = message.contains(statusUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? MultiplayerColors.danger : MultiplayerColors.success,
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

  Future<void> _handleBackToHome() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _incomingRequestPulseController.dispose();
    super.dispose();
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
            Positioned.fill(
              child: Container(decoration: AppDecorations.pageBackground),
            ),
            if (context.watch<SettingsProvider>().cardRainEnabled &&
                context.watch<SettingsProvider>().animationsEnabled)
              const Positioned.fill(child: CardRainBackground()),
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
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateSelection() async {
    if (!context.mounted) {
      return;
    }
    await context.push('/multiplayer/create-selection');
  }

  Future<void> _openJoinSelection() async {
    if (!context.mounted) {
      return;
    }
    await context.push('/multiplayer/join-selection');
  }

  Widget _buildHeader({required bool compact}) {
    final pendingCount = _incomingRequests.length;
    final incomingCount = _incomingRequests.length;
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
                _buildFriendsCountPill(incomingCount: incomingCount),
                if (pendingCount > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  _pillButton(
                    icon: Icons.mark_email_unread_outlined,
                    label:
                        '$pendingCount demande${pendingCount > 1 ? 's' : ''}',
                    onTap: () async {
                      await context.push('/friends?tab=1');
                      if (mounted) {
                        await Future.wait<void>(
                            [_loadSocialData(), _loadMyRooms()]);
                      }
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
        _buildFriendsCountPill(incomingCount: incomingCount),
        if (pendingCount > 0) ...<Widget>[
          const SizedBox(width: 8),
          _pillButton(
            icon: Icons.mark_email_unread_outlined,
            label: '$pendingCount demande${pendingCount > 1 ? 's' : ''}',
            onTap: () async {
              await context.push('/friends?tab=1');
              if (mounted) {
                await Future.wait<void>([_loadSocialData(), _loadMyRooms()]);
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildFriendsCountPill({required int incomingCount}) {
    final pill = _pillButton(
      icon: Icons.group_outlined,
      label: '${_friends.length} amis',
      onTap: () async {
        await context.push('/friends');
        if (mounted) {
          await Future.wait<void>([_loadSocialData(), _loadMyRooms()]);
        }
      },
    );
    if (incomingCount <= 0) {
      return pill;
    }
    return AnimatedBuilder(
      animation: _incomingRequestPulseController,
      builder: (context, child) {
        final pulse = _incomingRequestPulseController.value;
        final scale = 1 + (pulse * 0.04);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: 0.78 + (pulse * 0.22),
            child: child,
          ),
        );
      },
      child: pill,
    );
  }

  Widget _backButton() {
    return Material(
      color: _cs.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _handleBackToHome,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.arrow_back, size: 24, color: _cs.textPrimary),
        ),
      ),
    );
  }

  Widget _title() {
    final width = MediaQuery.of(context).size.width;
    final titleSize = width < 480 ? 22.0 : (width < 980 ? 30.0 : 42.0);
    return Text(
      'Multijoueur',
      style: TextStyle(
        color: _cs.textPrimary,
        fontSize: titleSize,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildUserPill() {
    return KeyedSubtree(
      key: _userPillKey,
      child: _pillButton(
        icon: Icons.person_outline,
        label: '@$_username',
        withChevron: true,
        chevronUp: _showUserMenu,
        onTap: () {
          unawaited(_openUserMenu());
        },
      ),
    );
  }

  Future<void> _openUserMenu() async {
    if (_showUserMenu) {
      setState(() => _showUserMenu = false);
      return;
    }

    final currentContext = _userPillKey.currentContext;
    if (currentContext == null) {
      return;
    }

    final buttonBox = currentContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) {
      return;
    }

    final origin = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final position = RelativeRect.fromLTRB(
      origin.dx + buttonBox.size.width - 192,
      origin.dy + buttonBox.size.height + 8,
      overlayBox.size.width - origin.dx - buttonBox.size.width,
      overlayBox.size.height - origin.dy,
    );

    setState(() => _showUserMenu = true);

    final selected = await showMenu<String>(
      context: context,
      position: position,
      elevation: 0,
      color: _cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _cs.separator, width: 1),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          height: 58,
          child: SizedBox(
            width: 192,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  _displayName,
                  style: TextStyle(
                    color: _cs.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '@$_username',
                  style: TextStyle(
                    color: _cs.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'profile',
          height: 44,
          child: _UserMenuItem(
            icon: Icons.account_circle_outlined,
            label: 'Mon Profil',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'friends',
          height: 44,
          child: _UserMenuItem(
            icon: Icons.group_outlined,
            label: 'Mes Amis',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          height: 44,
          child: _UserMenuItem(
            icon: Icons.logout_rounded,
            label: 'Déconnexion',
            color: Color(0xFFDC2626),
          ),
        ),
      ],
    );

    if (!mounted) return;
    setState(() => _showUserMenu = false);

    switch (selected) {
      case 'profile':
        await _openProfileSpaceWithTab(MultiplayerProfileTab.profile);
        break;
      case 'friends':
        await context.push('/friends');
        if (mounted) {
          await Future.wait<void>([_loadSocialData(), _loadMyRooms()]);
        }
        break;
      case 'logout':
        await _logout();
        break;
      default:
        break;
    }
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool withChevron = false,
    bool chevronUp = false,
  }) {
    return Material(
      color: _cs.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: _cs.textBody),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: _cs.textBody,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (withChevron) ...<Widget>[
                const SizedBox(width: 6),
                Icon(
                  chevronUp ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: _cs.textBody,
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
    final iconSize = compact ? 20.0 : 26.0;
    final iconBox = compact ? 42.0 : 58.0;
    final titleSize = compact ? 13.5 : 18.0;
    final subtitleSize = compact ? 10.5 : 14.0;
    final actionSize = compact ? 11.0 : 14.0;

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
                  color: _cs.textPrimary,
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: _cs.textSecondary,
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              Row(
                children: <Widget>[
                  Text(
                    'Ouvrir',
                    style: TextStyle(
                      color: MultiplayerColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: actionSize,
                    ),
                  ),
                  SizedBox(width: compact ? 5 : 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: MultiplayerColors.primary,
                    size: compact ? 15 : 18,
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
        color: _cs.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: _cs.separator),
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
            padding: EdgeInsets.all(compact ? 12 : 20),
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
    final headerSize = compact ? 12.5 : 18.0;
    final helperSize = compact ? 10.5 : 12.0;
    return Container(
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: _cs.separator),
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
                  color: MultiplayerColors.primary,
                  size: compact ? 18 : 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mes salons',
                    style: TextStyle(
                      color: _cs.textPrimary,
                      fontSize: headerSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loadingRooms ? null : _loadMyRooms,
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: compact ? 18 : 22,
                    color: MultiplayerColors.primary,
                  ),
                  tooltip: 'Rafraichir',
                ),
              ],
            ),
            Text(
              helperText,
              style: TextStyle(
                color: _cs.textSecondary,
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
                        color: MultiplayerColors.primary,
                      ),
                    )
                  : _myRooms.isEmpty
                      ? Center(
                          child: Text(
                            emptyLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _cs.textSecondary,
                              fontSize: compact ? 11 : 13,
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
    final status = (() {
      final raw = (activeInfo?['status'] as String?)?.toLowerCase();
      if (raw == null || raw.isEmpty) {
        return activeInfo == null ? 'offline' : 'waiting';
      }
      return raw;
    })();
    final playerCount = activeInfo?['playerCount'] as int?;

    final isActive = status != 'offline';
    final statusLabel = switch (status) {
      'waiting' => 'En attente',
      'playing' => 'En cours',
      'ended' => 'Terminé',
      'closing' => 'Fermeture',
      _ => 'Hors ligne',
    };
    final statusColor = isActive ? _cs.success : _cs.textSecondary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: _cs.separator),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: compact ? 16 : 20,
            backgroundColor: MultiplayerColors.primary.withValues(alpha: 0.1),
            child: Icon(
              room.isHost ? Icons.star : Icons.group,
              size: compact ? 16 : 20,
              color: MultiplayerColors.primary,
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
                        color: _cs.textPrimary,
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
                          fontWeight: FontWeight.bold,
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
                    color: _cs.textSecondary,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          FilledButton(
            onPressed: isActive
                ? () {
                    ServiceLocator().get<IHapticService>().buttonTap();
                    _rejoinRoom(room.roomCode);
                  }
                : null,
            style: FilledButton.styleFrom(
              visualDensity:
                  compact ? VisualDensity.compact : VisualDensity.standard,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 8 : 10,
              ),
              backgroundColor: MultiplayerColors.primary,
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
            iconColor: _cs.textSecondary,
            onSelected: (action) {
              if (action == 'remove_saved') {
                _removeSavedRoom(room.roomCode);
              } else if (action == 'invite_friends') {
                _inviteFriendsToRoom(room.roomCode);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              if (room.isHost)
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
    return Column(
      children: <Widget>[
        _buildMenuActionCard(
          icon: Icons.home_outlined,
          title: 'Créer un salon',
          subtitle: 'Lance un salon privé ou public et invite ton groupe.',
          accent: MultiplayerColors.createAccent,
          compact: true,
          onTap: _openCreateSelection,
        ),
        const SizedBox(height: 12),
        _buildMenuActionCard(
          icon: Icons.lock_open_rounded,
          title: 'Rejoindre un salon',
          subtitle:
              'Saisis un code privé ou rejoins une partie publique disponible.',
          accent: MultiplayerColors.joinAccent,
          compact: true,
          onTap: _openJoinSelection,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _buildMyRoomsCard(
            helperText:
                'Salons actifs où tu es membre. Les salons fermés disparaissent automatiquement.',
            emptyLabel: 'Aucun salon actif.',
            compact: true,
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
                  accent: MultiplayerColors.createAccent,
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
                  accent: MultiplayerColors.joinAccent,
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
                'Salons actifs où tu es membre. Les salons fermés disparaissent automatiquement.',
            emptyLabel: 'Aucun salon actif.',
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
                  accent: MultiplayerColors.createAccent,
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
                  accent: MultiplayerColors.joinAccent,
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
                'Salons actifs où tu es membre. Les salons fermés disparaissent automatiquement.',
            emptyLabel: 'Aucun salon actif.',
          ),
        ),
      ],
    );
  }
}

class _UserMenuItem extends StatelessWidget {
  const _UserMenuItem({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? MultiplayerColors.of(context).textPrimary;
    return Row(
      children: <Widget>[
        Icon(icon, color: effectiveColor, size: 16),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: effectiveColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
