import 'dart:async';

import 'package:dutch_game/providers/auth_provider.dart' as app_auth;
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
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
    extends State<MultiplayerProfileSpaceScreen>
    with SingleTickerProviderStateMixin {
  final SocialHubRepository _socialRepository = SocialHubRepository();
  late final FriendsApiService _friendsApi;
  late final TabController _tabController;

  SocialProfile? _profile;
  List<FriendInfo> _friends = [];
  bool _loading = true;

  String get _email =>
      fb_auth.FirebaseAuth.instance.currentUser?.email ?? '';

  String get _pseudo => _profile?.displayName ?? '';
  String get _username => _profile?.username ?? '';

  @override
  void initState() {
    super.initState();
    // Tab index : 0=Infos, 1=Supprimer, 2=Amis
    _tabController = TabController(length: 3, vsync: this);
    final authProvider = context.read<app_auth.AuthProvider>();
    _friendsApi = FriendsApiService(authProvider.authService);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final authProvider = context.read<app_auth.AuthProvider>();
    SocialProfile? profile;
    List<FriendInfo> friends = [];

    if (authProvider.isLoggedIn) {
      profile = SocialProfile(
        displayName: authProvider.user!.displayName,
        username: authProvider.user!.username,
        roomInviteNotificationsEnabled: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      friends = await _friendsApi.getFriends();
    } else {
      profile = await _socialRepository.getProfile();
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _friends = friends;
      _loading = false;
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Future<void> _handleBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) context.go('/multiplayer');
  }

  // ── Dialogs de modification ────────────────────────────────────────────────

  /// Ré-authentification Firebase (nécessaire avant toute modification sensible).
  Future<bool> _reauthenticate(String password) async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return false;
    try {
      final credential = fb_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _openEditPseudoDialog() async {
    final ctrl = TextEditingController(text: _pseudo);
    final pwdCtrl = TextEditingController();
    String? fieldError;
    String? pwdError;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Modifier le pseudo'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _warnBanner('Ton pseudo est visible par les autres joueurs.'),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(label: 'Nouveau pseudo', error: fieldError),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration:
                    _dlgInput(label: 'Mot de passe actuel', error: pwdError),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final val = ctrl.text.trim();
                      if (val.isEmpty || val.length > 24) {
                        setLocal(() => fieldError = 'Pseudo invalide (1-24 car.)');
                        return;
                      }
                      if (pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(pwdCtrl.text);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = 'Mot de passe incorrect.';
                        });
                        return;
                      }
                      final authProvider =
                          context.read<app_auth.AuthProvider>();
                      final result = await authProvider.updateProfile(val);
                      if (!ctx.mounted) return;
                      if (!result.success) {
                        setLocal(() {
                          saving = false;
                          fieldError = result.error ?? 'Erreur.';
                        });
                        return;
                      }
                      Navigator.of(ctx).pop();
                      _showSnackBar('Pseudo mis à jour.');
                      unawaited(_loadData());
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
    pwdCtrl.dispose();
  }

  Future<void> _openEditUsernameDialog() async {
    final ctrl = TextEditingController(text: _username);
    final pwdCtrl = TextEditingController();
    String? fieldError;
    String? pwdError;
    bool saving = false;
    final reserved = await _socialRepository.getReservedUsernames(
        exceptUsername: _username);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Modifier le nom d\'utilisateur'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _warnBanner(
                  'Ton nom d\'utilisateur est unique. Les autres te trouvent avec.'),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 20,
                textCapitalization: TextCapitalization.none,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(
                  label: 'Nouveau nom d\'utilisateur',
                  error: fieldError,
                  prefixText: '@',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration:
                    _dlgInput(label: 'Mot de passe actuel', error: pwdError),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final norm = SocialHubRepository.normalizeUsername(
                          ctrl.text);
                      if (!SocialHubRepository.isValidUsernameFormat(norm)) {
                        setLocal(() => fieldError =
                            '3-20 car. lettres/chiffres, . _ -');
                        return;
                      }
                      if (reserved.contains(norm)) {
                        setLocal(() =>
                            fieldError = 'Ce nom existe déjà.');
                        return;
                      }
                      if (pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(pwdCtrl.text);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = 'Mot de passe incorrect.';
                        });
                        return;
                      }
                      final now = DateTime.now();
                      final updated = SocialProfile(
                        displayName: _pseudo,
                        username: norm,
                        roomInviteNotificationsEnabled:
                            _profile?.roomInviteNotificationsEnabled ?? false,
                        createdAt: _profile?.createdAt ?? now,
                        updatedAt: now,
                      );
                      await _socialRepository.saveProfile(updated);
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      _showSnackBar('Nom d\'utilisateur mis à jour.');
                      unawaited(_loadData());
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
    pwdCtrl.dispose();
  }

  Future<void> _openEditEmailDialog() async {
    final ctrl = TextEditingController(text: _email);
    final pwdCtrl = TextEditingController();
    String? fieldError;
    String? pwdError;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Modifier l\'email'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _warnBanner(
                  'Tu recevras un email de vérification sur la nouvelle adresse.'),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(
                    label: 'Nouvelle adresse email', error: fieldError),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration:
                    _dlgInput(label: 'Mot de passe actuel', error: pwdError),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final newEmail = ctrl.text.trim();
                      if (newEmail.isEmpty || !newEmail.contains('@')) {
                        setLocal(
                            () => fieldError = 'Email invalide.');
                        return;
                      }
                      if (pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(pwdCtrl.text);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = 'Mot de passe incorrect.';
                        });
                        return;
                      }
                      try {
                        final user =
                            fb_auth.FirebaseAuth.instance.currentUser!;
                        await user.verifyBeforeUpdateEmail(newEmail);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        _showSnackBar(
                            'Email de vérification envoyé à $newEmail.');
                        unawaited(_loadData());
                      } on fb_auth.FirebaseAuthException catch (e) {
                        if (!ctx.mounted) return;
                        setLocal(() {
                          saving = false;
                          fieldError = e.message ?? 'Erreur Firebase.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
    pwdCtrl.dispose();
  }

  Future<void> _openChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    bool saving = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Changer le mot de passe'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _warnBanner('Choisis un mot de passe fort (8+ caractères recommandé).'),
              const SizedBox(height: 14),
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(
                  label: 'Mot de passe actuel',
                  suffixIcon: _eyeIcon(obscureCurrent,
                      () => setLocal(() => obscureCurrent = !obscureCurrent)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(
                  label: 'Nouveau mot de passe',
                  suffixIcon: _eyeIcon(
                      obscureNew, () => setLocal(() => obscureNew = !obscureNew)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                style: const TextStyle(color: Color(0xFF111827)),
                decoration: _dlgInput(
                  label: 'Confirmer',
                  suffixIcon: _eyeIcon(obscureConfirm,
                      () => setLocal(() => obscureConfirm = !obscureConfirm)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 12)),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final cur = currentCtrl.text;
                      final nw = newCtrl.text;
                      final conf = confirmCtrl.text;
                      if (cur.isEmpty || nw.isEmpty || conf.isEmpty) {
                        setLocal(() => error = 'Tous les champs sont requis.');
                        return;
                      }
                      if (nw.length < 6) {
                        setLocal(() => error =
                            'Le nouveau mot de passe doit faire au moins 6 caractères.');
                        return;
                      }
                      if (nw != conf) {
                        setLocal(() =>
                            error = 'Les mots de passe ne correspondent pas.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        error = null;
                      });
                      final ok = await _reauthenticate(cur);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          error = 'Mot de passe actuel incorrect.';
                        });
                        return;
                      }
                      try {
                        await fb_auth.FirebaseAuth.instance.currentUser!
                            .updatePassword(nw);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        _showSnackBar('Mot de passe mis à jour.');
                      } on fb_auth.FirebaseAuthException catch (e) {
                        if (!ctx.mounted) return;
                        setLocal(() {
                          saving = false;
                          error = e.message ?? 'Erreur Firebase.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Mettre à jour'),
            ),
          ],
        );
      }),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themed = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEEF2FF),
                Color(0xFFF3E8FF),
                Color(0xFFEFF6FF),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF6366F1)))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _InfosTab(
                              pseudo: _pseudo,
                              username: _username,
                              email: _email,
                              onEditPseudo: _openEditPseudoDialog,
                              onEditUsername: _openEditUsernameDialog,
                              onEditEmail: _openEditEmailDialog,
                              onChangePassword: _openChangePasswordDialog,
                            ),
                            _DeleteAccountTab(
                              onShowSnackBar: _showSnackBar,
                              onDeleted: () {
                                if (mounted) context.go('/');
                              },
                            ),
                            _FriendsListTab(friends: _friends),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFBBF24).withValues(alpha: 0.98),
            const Color(0xFFF97316).withValues(alpha: 0.98),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _handleBack,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child:
                        Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                ),
              ),
              const Expanded(
                child: Text(
                  'Mon Profil',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
            indicatorColor: Colors.white,
            indicatorWeight: 2.5,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(
                iconMargin: EdgeInsets.only(bottom: 2),
                icon: Icon(Icons.person_outline, size: 20),
                text: 'Infos',
              ),
              Tab(
                iconMargin: EdgeInsets.only(bottom: 2),
                icon: Icon(Icons.delete_outline_rounded, size: 20),
                text: 'Supprimer',
              ),
              Tab(
                iconMargin: EdgeInsets.only(bottom: 2),
                icon: Icon(Icons.group_outlined, size: 20),
                text: 'Amis',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Onglet Infos (style annuaire) ────────────────────────────────────────────

class _InfosTab extends StatelessWidget {
  const _InfosTab({
    required this.pseudo,
    required this.username,
    required this.email,
    required this.onEditPseudo,
    required this.onEditUsername,
    required this.onEditEmail,
    required this.onChangePassword,
  });

  final String pseudo;
  final String username;
  final String email;
  final VoidCallback onEditPseudo;
  final VoidCallback onEditUsername;
  final VoidCallback onEditEmail;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // Avatar + nom en haut
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFBBF24).withValues(alpha: 0.98),
                      const Color(0xFFF97316).withValues(alpha: 0.98),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  pseudo.isNotEmpty ? pseudo.characters.first.toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 32,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pseudo.isNotEmpty ? pseudo : '—',
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(
                username.isNotEmpty ? '@$username' : '—',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Liste style annuaire
        _sectionLabel('Compte'),
        const SizedBox(height: 8),
        _InfoCard(children: [
          _InfoRow(
            icon: Icons.person_outline_rounded,
            iconColor: const Color(0xFF4F46E5),
            label: 'Pseudo',
            value: pseudo.isNotEmpty ? pseudo : '—',
            onTap: onEditPseudo,
          ),
          const _RowDivider(),
          _InfoRow(
            icon: Icons.alternate_email_rounded,
            iconColor: const Color(0xFF0EA5E9),
            label: 'Nom d\'utilisateur',
            value: username.isNotEmpty ? '@$username' : '—',
            onTap: onEditUsername,
          ),
          const _RowDivider(),
          _InfoRow(
            icon: Icons.email_outlined,
            iconColor: const Color(0xFF10B981),
            label: 'Mail',
            value: email.isNotEmpty ? email : '—',
            onTap: onEditEmail,
          ),
        ]),

        const SizedBox(height: 20),
        _sectionLabel('Sécurité'),
        const SizedBox(height: 8),
        _InfoCard(children: [
          _InfoRow(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Mot de passe',
            value: '••••••••',
            onTap: onChangePassword,
          ),
        ]),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icône dans un carré coloré de taille fixe
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFCBD5E1), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 48,
      endIndent: 0,
      color: Color(0xFFF1F5F9),
    );
  }
}

// ─── Onglet Supprimer le compte ───────────────────────────────────────────────

class _DeleteAccountTab extends StatefulWidget {
  const _DeleteAccountTab({
    required this.onShowSnackBar,
    required this.onDeleted,
  });

  final void Function(String, {bool isError}) onShowSnackBar;
  final VoidCallback onDeleted;

  @override
  State<_DeleteAccountTab> createState() => _DeleteAccountTabState();
}

class _DeleteAccountTabState extends State<_DeleteAccountTab> {
  final _pwdCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete() async {
    final pwd = _pwdCtrl.text;
    if (pwd.isEmpty) {
      setState(() => _error = 'Mot de passe requis pour confirmer.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
          'Cette action est définitive. Toutes tes données (profil, amis, parties) seront effacées et ton compte ne pourra pas être récupéré.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oui, supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    final authProvider = context.read<app_auth.AuthProvider>();
    final result = await authProvider.deleteAccount(pwd);
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _deleting = false;
        _error = result.error ?? 'Suppression impossible. Vérifie ton mot de passe.';
      });
      return;
    }

    widget.onShowSnackBar('Compte supprimé.');
    widget.onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626), size: 26),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zone dangereuse',
                      style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'La suppression est irréversible. Toutes tes données disparaîtront définitivement.',
                      style:
                          TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _InfoCard(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirme avec ton mot de passe',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: Color(0xFF111827)),
                  decoration: _dlgInput(
                    label: 'Mot de passe actuel',
                    error: _error,
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _deleting ? null : _confirmAndDelete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.delete_forever_rounded),
                    label: Text(
                      _deleting ? 'Suppression...' : 'Supprimer mon compte',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB91C1C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

// ─── Onglet Amis ──────────────────────────────────────────────────────────────

class _FriendsListTab extends StatelessWidget {
  const _FriendsListTab({required this.friends});

  final List<FriendInfo> friends;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_outlined,
                size: 56, color: Color(0xFF94A3B8)),
            SizedBox(height: 12),
            Text(
              'Aucun ami pour l\'instant.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              'Va dans "Mes Amis" pour en ajouter.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: friends.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${friends.length} AMI${friends.length > 1 ? 'S' : ''}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          );
        }
        final friend = friends[index - 1];
        final initial = friend.displayName.isNotEmpty
            ? friend.displayName.characters.first.toUpperCase()
            : '?';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFEEF2FF),
              child: Text(
                initial,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
            title: Text(
              friend.displayName,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: Text(
              '@${friend.username}',
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 13),
            ),
            trailing: friend.isOnline
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// InputDecoration pour les dialogs : label et texte saisi en noir.
InputDecoration _dlgInput({
  required String label,
  String? error,
  String? prefixText,
  Widget? suffixIcon,
}) {
  const labelStyle = TextStyle(
    color: Color(0xFF374151),
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  return InputDecoration(
    labelText: label,
    labelStyle: labelStyle,
    floatingLabelStyle:
        const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w700),
    errorText: error,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
    ),
  );
}

Widget _warnBanner(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFCD34D)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('⚠️', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

IconButton _eyeIcon(bool obscure, VoidCallback onTap) {
  return IconButton(
    onPressed: onTap,
    icon: Icon(
      obscure ? Icons.visibility_off : Icons.visibility,
      color: const Color(0xFF94A3B8),
      size: 20,
    ),
  );
}

