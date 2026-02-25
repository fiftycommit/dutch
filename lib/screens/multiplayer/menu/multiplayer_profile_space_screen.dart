import 'dart:async';

import 'package:dutch_game/providers/auth_provider.dart' as app_auth;
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/social/friends_api_service.dart';
import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_game/utils/ui_constants.dart';
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

  String get _email => fb_auth.FirebaseAuth.instance.currentUser?.email ?? '';

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
      backgroundColor:
          isError ? MultiplayerColors.danger : MultiplayerColors.success,
    ));
  }

  Future<void> _handleBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) context.go('/multiplayer');
  }

  // ── Dialogs de modification ────────────────────────────────────────────────

  /// Ré-authentification Firebase (nécessaire avant toute modification sensible).
  /// Détecte le provider et utilise la bonne méthode (Google popup ou email/mdp).
  Future<bool> _reauthenticate({String? password}) async {
    final authProvider = context.read<app_auth.AuthProvider>();
    final result = await authProvider.reauthenticate(password: password);
    return result.success;
  }

  /// Vérifie si l'utilisateur a un mot de passe lié
  bool _hasPasswordProvider() {
    final authProvider = context.read<app_auth.AuthProvider>();
    return authProvider.getLinkedProviders().contains('password');
  }

  Future<void> _openEditPseudoDialog() async {
    final ctrl = TextEditingController(text: _pseudo);
    final pwdCtrl = TextEditingController();
    String? fieldError;
    String? pwdError;
    bool saving = false;
    final needsPwd = _hasPasswordProvider();

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
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(context,
                    label: 'Nouveau pseudo', error: fieldError),
              ),
              if (needsPwd) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  style: TextStyle(
                      color: MultiplayerColors.of(context).textPrimary),
                  decoration: _dlgInput(context,
                      label: 'Mot de passe actuel', error: pwdError),
                ),
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
                      final val = ctrl.text.trim();
                      if (val.isEmpty || val.length > 24) {
                        setLocal(
                            () => fieldError = 'Pseudo invalide (1-24 car.)');
                        return;
                      }
                      if (needsPwd && pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(
                          password: needsPwd ? pwdCtrl.text : null);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = needsPwd
                              ? 'Mot de passe incorrect.'
                              : 'Ré-authentification échouée.';
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
    final needsPwd = _hasPasswordProvider();
    final reserved =
        await _socialRepository.getReservedUsernames(exceptUsername: _username);

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
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(
                  context,
                  label: 'Nouveau nom d\'utilisateur',
                  error: fieldError,
                  prefixText: '@',
                ),
              ),
              if (needsPwd) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  style: TextStyle(
                      color: MultiplayerColors.of(context).textPrimary),
                  decoration: _dlgInput(context,
                      label: 'Mot de passe actuel', error: pwdError),
                ),
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
                      final norm =
                          SocialHubRepository.normalizeUsername(ctrl.text);
                      if (!SocialHubRepository.isValidUsernameFormat(norm)) {
                        setLocal(() =>
                            fieldError = '3-20 car. lettres/chiffres, . _ -');
                        return;
                      }
                      if (reserved.contains(norm)) {
                        setLocal(() => fieldError = 'Ce nom existe déjà.');
                        return;
                      }
                      if (needsPwd && pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(
                          password: needsPwd ? pwdCtrl.text : null);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = needsPwd
                              ? 'Mot de passe incorrect.'
                              : 'Ré-authentification échouée.';
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
    final needsPwd = _hasPasswordProvider();

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
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(context,
                    label: 'Nouvelle adresse email', error: fieldError),
              ),
              if (needsPwd) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  style: TextStyle(
                      color: MultiplayerColors.of(context).textPrimary),
                  decoration: _dlgInput(context,
                      label: 'Mot de passe actuel', error: pwdError),
                ),
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
                      final newEmail = ctrl.text.trim();
                      if (newEmail.isEmpty || !newEmail.contains('@')) {
                        setLocal(() => fieldError = 'Email invalide.');
                        return;
                      }
                      if (needsPwd && pwdCtrl.text.isEmpty) {
                        setLocal(() => pwdError = 'Mot de passe requis.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        fieldError = null;
                        pwdError = null;
                      });
                      final ok = await _reauthenticate(
                          password: needsPwd ? pwdCtrl.text : null);
                      if (!ctx.mounted) return;
                      if (!ok) {
                        setLocal(() {
                          saving = false;
                          pwdError = needsPwd
                              ? 'Mot de passe incorrect.'
                              : 'Ré-authentification échouée.';
                        });
                        return;
                      }
                      try {
                        final user = fb_auth.FirebaseAuth.instance.currentUser!;
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
              _warnBanner(
                  'Choisis un mot de passe fort (8+ caractères recommandé).'),
              const SizedBox(height: 14),
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(
                  context,
                  label: 'Mot de passe actuel',
                  suffixIcon: _eyeIcon(obscureCurrent,
                      () => setLocal(() => obscureCurrent = !obscureCurrent)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(
                  context,
                  label: 'Nouveau mot de passe',
                  suffixIcon: _eyeIcon(obscureNew,
                      () => setLocal(() => obscureNew = !obscureNew)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(
                  context,
                  label: 'Confirmer',
                  suffixIcon: _eyeIcon(obscureConfirm,
                      () => setLocal(() => obscureConfirm = !obscureConfirm)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: TextStyle(
                        color: MultiplayerColors.of(context).danger, fontSize: 12)),
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
                      final ok = await _reauthenticate(password: cur);
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

  // ── Link / Unlink providers ────────────────────────────────────────────────

  Future<void> _linkGoogle() async {
    final auth = context.read<app_auth.AuthProvider>();
    final result = await auth.linkGoogle();
    if (!mounted) return;
    if (result.success) {
      _showSnackBar('Compte Google lié !');
      setState(() {});
    } else {
      _showSnackBar(result.error ?? 'Erreur', isError: true);
    }
  }

  Future<void> _linkEmailPassword() async {
    final emailCtrl = TextEditingController(text: _email);
    final pwdCtrl = TextEditingController();
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Ajouter email / mot de passe'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _warnBanner(
                  'Ajoute un mot de passe pour te connecter sans Google.'),
              const SizedBox(height: 14),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration: _dlgInput(context, label: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                style:
                    TextStyle(color: MultiplayerColors.of(context).textPrimary),
                decoration:
                    _dlgInput(context, label: 'Mot de passe (min. 6 car.)'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: TextStyle(
                        color: MultiplayerColors.of(context).danger, fontSize: 12)),
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
                      final em = emailCtrl.text.trim();
                      final pw = pwdCtrl.text;
                      if (em.isEmpty || !em.contains('@')) {
                        setLocal(() => error = 'Email invalide.');
                        return;
                      }
                      if (pw.length < 6) {
                        setLocal(() =>
                            error = 'Mot de passe trop court (min. 6 car.).');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        error = null;
                      });
                      final auth = context.read<app_auth.AuthProvider>();
                      final result = await auth.linkEmailPassword(em, pw);
                      if (!ctx.mounted) return;
                      if (!result.success) {
                        setLocal(() {
                          saving = false;
                          error = result.error;
                        });
                        return;
                      }
                      Navigator.of(ctx).pop();
                      _showSnackBar('Email / mot de passe ajouté !');
                      setState(() {});
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Ajouter'),
            ),
          ],
        );
      }),
    );
    emailCtrl.dispose();
    pwdCtrl.dispose();
  }

  Future<void> _unlinkProvider(String providerId) async {
    final providerName =
        providerId == 'google.com' ? 'Google' : 'Email / Mot de passe';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Délier $providerName ?'),
        content: Text(
            'Tu ne pourras plus te connecter avec $providerName après cette action.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: MultiplayerColors.of(context).danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Délier'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = context.read<app_auth.AuthProvider>();
    final result = await auth.unlinkProvider(providerId);
    if (!mounted) return;
    if (result.success) {
      _showSnackBar('$providerName délié.');
      setState(() {});
    } else {
      _showSnackBar(result.error ?? 'Erreur', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themed = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );

    return Theme(
      data: themed,
      child: SelectionContainer.disabled(
          child: Scaffold(
        body: Container(
          color: MultiplayerColors.of(context).background,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: MultiplayerColors.primary))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _InfosTab(
                              pseudo: _pseudo,
                              username: _username,
                              email: _email,
                              linkedProviders: context
                                  .read<app_auth.AuthProvider>()
                                  .getLinkedProviders(),
                              onEditPseudo: _openEditPseudoDialog,
                              onEditUsername: _openEditUsernameDialog,
                              onEditEmail: _openEditEmailDialog,
                              onChangePassword: _openChangePasswordDialog,
                              onLinkGoogle: _linkGoogle,
                              onLinkEmailPassword: _linkEmailPassword,
                              onUnlinkProvider: _unlinkProvider,
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
      )),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MultiplayerColors.of(context).primary,
            MultiplayerColors.of(context).primary.withValues(alpha: 0.8),
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
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
    required this.linkedProviders,
    required this.onEditPseudo,
    required this.onEditUsername,
    required this.onEditEmail,
    required this.onChangePassword,
    required this.onLinkGoogle,
    required this.onLinkEmailPassword,
    required this.onUnlinkProvider,
  });

  final String pseudo;
  final String username;
  final String email;
  final List<String> linkedProviders;
  final VoidCallback onEditPseudo;
  final VoidCallback onEditUsername;
  final VoidCallback onEditEmail;
  final VoidCallback onChangePassword;
  final VoidCallback onLinkGoogle;
  final VoidCallback onLinkEmailPassword;
  final void Function(String providerId) onUnlinkProvider;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cs = MultiplayerColors.of(context);
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
                      cs.primary,
                      cs.primary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  pseudo.isNotEmpty
                      ? pseudo.characters.first.toUpperCase()
                      : '?',
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
                style: TextStyle(
                  color: cs.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(
                username.isNotEmpty ? '@$username' : '—',
                style: TextStyle(
                  color: cs.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Liste style annuaire
        _sectionLabel(context, 'Compte'),
        const SizedBox(height: 8),
        _InfoCard(children: [
          _InfoRow(
            icon: Icons.person_outline_rounded,
            iconColor: MultiplayerColors.primary,
            label: 'Pseudo',
            value: pseudo.isNotEmpty ? pseudo : '—',
            onTap: onEditPseudo,
          ),
          const _RowDivider(),
          _InfoRow(
            icon: Icons.alternate_email_rounded,
            iconColor: cs.info,
            label: 'Nom d\'utilisateur',
            value: username.isNotEmpty ? '@$username' : '—',
            onTap: onEditUsername,
          ),
          const _RowDivider(),
          _InfoRow(
            icon: Icons.email_outlined,
            iconColor: cs.success,
            label: 'Mail',
            value: email.isNotEmpty ? email : '—',
            onTap: onEditEmail,
          ),
        ]),

        const SizedBox(height: 20),
        _sectionLabel(context, 'Sécurité'),
        const SizedBox(height: 8),
        _InfoCard(children: [
          // Google provider
          _ProviderRow(
            icon: Icons.g_mobiledata_rounded,
            iconColor: cs.danger,
            label: 'Google',
            isLinked: linkedProviders.contains('google.com'),
            canUnlink: linkedProviders.length > 1,
            onLink: onLinkGoogle,
            onUnlink: () => onUnlinkProvider('google.com'),
          ),
          const _RowDivider(),
          // Email/password provider
          _ProviderRow(
            icon: Icons.email_outlined,
            iconColor: cs.info,
            label: 'Email / Mot de passe',
            isLinked: linkedProviders.contains('password'),
            canUnlink: linkedProviders.length > 1,
            onLink: onLinkEmailPassword,
            onUnlink: () => onUnlinkProvider('password'),
          ),
          if (linkedProviders.contains('password')) ...[
            const _RowDivider(),
            _InfoRow(
              icon: Icons.lock_outline_rounded,
              iconColor: MultiplayerColors.primary,
              label: 'Changer mot de passe',
              value: '••••••••',
              onTap: onChangePassword,
            ),
          ],
        ]),

        const SizedBox(height: 20),
        _sectionLabel(context, 'Apparence'),
        const SizedBox(height: 8),
        _ThemePicker(
          current: settings.appTheme,
          onChanged: settings.setAppTheme,
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = MultiplayerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: cs.textSecondary,
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
    final cs = MultiplayerColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.separator),
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
    final cs = MultiplayerColors.of(context);
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
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: cs.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: cs.separator, size: 18),
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
    return Divider(
      height: 1,
      thickness: 1,
      indent: 48,
      endIndent: 0,
      color: MultiplayerColors.of(context).separator,
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isLinked,
    required this.canUnlink,
    required this.onLink,
    required this.onUnlink,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isLinked;
  final bool canUnlink;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final cs = MultiplayerColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: cs.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          if (isLinked) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MultiplayerColors.of(context).success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Lié',
                style: TextStyle(
                    color: MultiplayerColors.of(context).success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
            if (canUnlink) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onUnlink,
                child: Icon(Icons.link_off_rounded,
                    color: cs.textSecondary, size: 18),
              ),
            ],
          ] else
            TextButton(
              onPressed: onLink,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Ajouter',
                  style: TextStyle(
                      color: MultiplayerColors.of(context).info,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
        ],
      ),
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
  late bool _needsPwd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<app_auth.AuthProvider>();
    _needsPwd = auth.getLinkedProviders().contains('password');
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete() async {
    if (_needsPwd && _pwdCtrl.text.isEmpty) {
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
            style: FilledButton.styleFrom(
                backgroundColor: MultiplayerColors.of(context).danger),
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
    final result = await authProvider.deleteAccount(
        password: _needsPwd ? _pwdCtrl.text : null);
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _deleting = false;
        _error = result.error ?? 'Suppression impossible.';
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
        Builder(builder: (context) {
          final cs = MultiplayerColors.of(context);
          return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.danger.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.danger.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: cs.danger, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zone dangereuse',
                      style: TextStyle(
                        color: cs.danger,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'La suppression est irréversible. Toutes tes données disparaîtront définitivement.',
                      style: TextStyle(color: cs.danger, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        }),
        const SizedBox(height: 20),
        _InfoCard(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _needsPwd
                      ? 'Confirme avec ton mot de passe'
                      : 'Confirme la suppression',
                  style: TextStyle(
                    color: MultiplayerColors.of(context).textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (_needsPwd) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pwdCtrl,
                    obscureText: _obscure,
                    style: TextStyle(
                        color: MultiplayerColors.of(context).textPrimary),
                    decoration: _dlgInput(
                      context,
                      label: 'Mot de passe actuel',
                      error: _error,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: MultiplayerColors.of(context).textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    'Tu seras redirigé vers Google pour confirmer ton identité.',
                    style: TextStyle(color: MultiplayerColors.of(context).textSecondary, fontSize: 13),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                          color: MultiplayerColors.of(context).danger, fontSize: 12),
                    ),
                  ],
                ],
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
                      backgroundColor: MultiplayerColors.of(context).danger,
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
    final cs = MultiplayerColors.of(context);
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_outlined, size: 56, color: cs.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Aucun ami pour l\'instant.',
              style: TextStyle(color: cs.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Va dans "Mes Amis" pour en ajouter.',
              style: TextStyle(color: cs.textSecondary, fontSize: 13),
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
              style: TextStyle(
                color: cs.textSecondary,
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
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.separator),
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
              backgroundColor: cs.surfaceHigh,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
            title: Text(
              friend.displayName,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.textPrimary),
            ),
            subtitle: Text(
              '@${friend.username}',
              style: TextStyle(color: cs.textSecondary, fontSize: 13),
            ),
            trailing: friend.isOnline
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cs.success,
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

// ─── Theme Picker ─────────────────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.current, required this.onChanged});

  final AppTheme current;
  final ValueChanged<AppTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = MultiplayerColors.of(context);
    const options = [
      (AppTheme.light, Icons.wb_sunny_outlined, 'Clair'),
      (AppTheme.dark, Icons.nights_stay_outlined, 'Sombre'),
      (AppTheme.green, Icons.eco_outlined, 'Vert'),
      (AppTheme.system, Icons.phone_iphone_outlined, 'Système'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.separator),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: options.map((opt) {
          final (theme, icon, label) = opt;
          final selected = current == theme;
          // Pour "Vert", la couleur de sélection est verte
          final selectionColor =
              theme == AppTheme.green ? MultiplayerColors.green.primary : cs.primary;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(theme),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? selectionColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? Colors.white : cs.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : cs.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// InputDecoration pour les dialogs — s'adapte au mode clair/sombre.
InputDecoration _dlgInput(
  BuildContext context, {
  required String label,
  String? error,
  String? prefixText,
  Widget? suffixIcon,
}) {
  final cs = MultiplayerColors.of(context);
  final labelStyle = TextStyle(
    color: cs.textSecondary,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  return InputDecoration(
    labelText: label,
    labelStyle: labelStyle,
    floatingLabelStyle:
        TextStyle(color: cs.textPrimary, fontWeight: FontWeight.w700),
    errorText: error,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: cs.surfaceHigh,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.separator),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.danger, width: 1.6),
    ),
  );
}

Widget _warnBanner(String text) {
  return Builder(builder: (context) {
    final cs = MultiplayerColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.textBody,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  });
}

Widget _eyeIcon(bool obscure, VoidCallback onTap) {
  return Builder(builder: (context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscure ? Icons.visibility_off : Icons.visibility,
        color: MultiplayerColors.of(context).textSecondary,
        size: 20,
      ),
    );
  });
}
