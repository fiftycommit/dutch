import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../providers/auth_provider.dart';

// ─── Palette CSS ──────────────────────────────────────────────────────────────
const _kRed = Color(0xFFFF4B2B);
const _kRed2 = Color(0xFFFF416C);
const _kBg = Color(0xFFF6F5F7);
const _kInput = Color(0xFFEEEEEE);
const _kText = Color(0xFF333333);
const _kSpan = Color(0xFF888888);

// ─── LoginScreen ──────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  final bool startWithRegister;
  const LoginScreen({super.key, this.startWithRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  final _identifierCtrl = TextEditingController();
  final _loginPwCtrl = TextEditingController();
  bool _obscureLoginPw = true;

  final _usernameCtrl = TextEditingController();
  final _pseudoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _regPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _obscureRegPw = true;
  bool _obscureConfirmPw = true;
  bool? _usernameAvailable;
  bool _checkingUsername = false;

  String? _errorMessage;
  bool _shakeForm = false;
  Timer? _shakeResetTimer;
  Timer? _usernameCheckTimer;

  static final _usernameRx = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');
  static final _emailRx = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.startWithRegister) _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _identifierCtrl.dispose();
    _loginPwCtrl.dispose();
    _usernameCtrl.dispose();
    _pseudoCtrl.dispose();
    _emailCtrl.dispose();
    _regPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _shakeResetTimer?.cancel();
    _usernameCheckTimer?.cancel();
    super.dispose();
  }

  bool get _isSignUp => _anim.value >= 0.5;

  void _switchToSignUp() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _errorMessage = null);
    _ctrl.forward();
  }

  void _switchToSignIn() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _errorMessage = null);
    _ctrl.reverse();
  }

  void _setError(String msg) {
    setState(() {
      _errorMessage = msg;
      _shakeForm = true;
    });
    _shakeResetTimer?.cancel();
    _shakeResetTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _shakeForm = false);
    });
  }

  Future<void> _completeAuthSuccess() async {
    final didPop = await Navigator.of(context).maybePop(true);
    if (!didPop && mounted) context.go('/multiplayer');
  }

  Future<void> _handleBack() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) context.go('/');
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _errorMessage = null);
    final auth = context.read<AuthProvider>();
    final result = await auth.loginWithGoogle();
    if (!mounted) return;

    if (!result.success) {
      if (result.error != 'Connexion annulée') {
        _setError(result.error ?? 'Erreur Google');
      }
      return;
    }

    if (result.needsUsernameSetup) {
      // Nouveau compte Google : demander/confirmer le username
      final chosenUsername = await _showUsernamePickerDialog(
        suggested: result.suggestedUsername ?? '',
        displayName: result.user?.displayName ?? '',
      );
      if (!mounted) return;
      if (chosenUsername == null) {
        // L'utilisateur a annulé — on déconnecte Firebase
        await auth.signOut();
        return;
      }
      // Mettre à jour le username dans le provider puis naviguer
      auth.setUsername(chosenUsername);
    }

    await _completeAuthSuccess();
  }

  /// Dialog de choix du username après connexion Google
  Future<String?> _showUsernamePickerDialog({
    required String suggested,
    required String displayName,
  }) async {
    final ctrl = TextEditingController(text: suggested);
    String? error;
    bool checking = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> validate() async {
            final val = ctrl.text.trim();
            if (val.length < 3) {
              setState(() => error = 'Minimum 3 caractères');
              return;
            }
            if (!RegExp(r'^[a-zA-Z0-9._-]{3,20}$').hasMatch(val)) {
              setState(() =>
                  error = 'Lettres, chiffres, . _ - uniquement (3-20 car.)');
              return;
            }
            setState(() {
              checking = true;
              error = null;
            });
            final auth = context.read<AuthProvider>();
            final available = await auth.checkUsernameAvailable(val);
            if (!ctx.mounted) return;
            if (!available) {
              setState(() {
                checking = false;
                error = 'Ce nom d\'utilisateur est déjà pris';
              });
              return;
            }
            Navigator.of(ctx).pop(val);
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Choisir un nom d\'utilisateur',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF333333))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bienvenue, $displayName !',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF666666))),
                const SizedBox(height: 4),
                const Text('Vous pouvez garder ce nom ou en choisir un autre.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  onSubmitted: (_) => validate(),
                  decoration: InputDecoration(
                    hintText: 'nom_utilisateur',
                    prefixText: '@',
                    errorText: error,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFFF4B2B), width: 2),
                    ),
                  ),
                  onChanged: (_) => setState(() => error = null),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Annuler',
                    style: TextStyle(color: Color(0xFF999999))),
              ),
              ElevatedButton(
                onPressed: checking ? null : validate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B2B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Confirmer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _login() async {
    final id = _identifierCtrl.text.trim();
    final pw = _loginPwCtrl.text;
    if (id.isEmpty) {
      _setError('Email ou pseudo requis');
      return;
    }
    if (pw.isEmpty) {
      _setError('Mot de passe requis');
      return;
    }
    setState(() => _errorMessage = null);
    final auth = context.read<AuthProvider>();
    final result = await auth.login(id, pw);
    if (!mounted) return;
    result.success
        ? await _completeAuthSuccess()
        : _setError(result.error ?? 'Erreur de connexion');
  }

  void _onUsernameChanged(String value) {
    _usernameCheckTimer?.cancel();
    if (!_usernameRx.hasMatch(value.trim())) {
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameCheckTimer = Timer(const Duration(milliseconds: 450), () async {
      final ok = await context
          .read<AuthProvider>()
          .authService
          .checkUsernameAvailable(value.trim());
      if (!mounted || _usernameCtrl.text.trim() != value.trim()) return;
      setState(() {
        _usernameAvailable = ok;
        _checkingUsername = false;
      });
    });
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final pseudo = _pseudoCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pw = _regPwCtrl.text;
    final confirm = _confirmPwCtrl.text;

    if ([username, pseudo, email, pw, confirm].any((s) => s.isEmpty)) {
      _setError('Tous les champs sont obligatoires');
      return;
    }
    if (!_usernameRx.hasMatch(username)) {
      _setError("Nom d'utilisateur invalide (3-20 car., lettres/chiffres/._-)");
      return;
    }
    if (_usernameAvailable == false) {
      _setError("Ce nom d'utilisateur est déjà pris");
      return;
    }
    if (pseudo.length > 24) {
      _setError('Pseudo : 24 caractères max');
      return;
    }
    if (!_emailRx.hasMatch(email)) {
      _setError('Adresse e-mail invalide');
      return;
    }
    if (pw.length < 6) {
      _setError('Mot de passe : 6 caractères minimum');
      return;
    }
    if (pw != confirm) {
      _setError('Les mots de passe ne correspondent pas');
      return;
    }
    setState(() => _errorMessage = null);
    final result = await context
        .read<AuthProvider>()
        .register(username, pseudo, email, pw);
    if (!mounted) return;
    result.success
        ? await _completeAuthSuccess()
        : _setError(result.error ?? "Erreur d'inscription");
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 700;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.montserratTextTheme(Theme.of(context).textTheme),
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
              child: isWide ? _buildDesktop(media) : _buildMobile(media)),
        ),
      ),
    );
  }

  // ─── Desktop ───────────────────────────────────────────────────────────────

  Widget _buildDesktop(MediaQueryData media) {
    final auth = context.watch<AuthProvider>();
    // .container { width: 768px; max-width: 100%; min-height: 480px }
    final w = math.min(media.size.width - 32.0, 768.0);
    final h = math.max(math.min(media.size.height - 80.0, 560.0), 480.0);

    return Stack(
      children: [
        Positioned(top: 8, left: 12, child: _BackBtn(onTap: _handleBack)),
        Center(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              final half = w / 2;

              return Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 28,
                        offset: Offset(0, 14)),
                    BoxShadow(
                        color: Color(0x38000000),
                        blurRadius: 10,
                        offset: Offset(0, 10)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      // ── .sign-in-container ──
                      // left:0, width:50% → active: translateX(100%) = left:half
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: t * half,
                        width: half,
                        child: IgnorePointer(
                          ignoring: t > 0.5,
                          child: _FormSignIn(
                            identifierCtrl: _identifierCtrl,
                            passwordCtrl: _loginPwCtrl,
                            obscurePassword: _obscureLoginPw,
                            onTogglePassword: () => setState(
                                () => _obscureLoginPw = !_obscureLoginPw),
                            errorMessage: _isSignUp ? null : _errorMessage,
                            shakeForm: _shakeForm && !_isSignUp,
                            isLoading: auth.isLoading,
                            onLogin: _login,
                            onForgotPassword: () =>
                                context.push('/forgot-password'),
                            onGoogleTap: _loginWithGoogle,
                          ),
                        ),
                      ),

                      // ── .sign-up-container ──
                      // left:0, width:50%, opacity:0 → active: translateX(100%) + opacity:1
                      // @keyframes show : opacity 0→1 à partir de 50%
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: t * half,
                        width: half,
                        child: IgnorePointer(
                          ignoring: t <= 0.5,
                          child: Opacity(
                            opacity: (t * 2 - 1).clamp(0.0, 1.0),
                            child: _FormSignUp(
                              usernameCtrl: _usernameCtrl,
                              pseudoCtrl: _pseudoCtrl,
                              emailCtrl: _emailCtrl,
                              passwordCtrl: _regPwCtrl,
                              confirmCtrl: _confirmPwCtrl,
                              obscurePassword: _obscureRegPw,
                              obscureConfirm: _obscureConfirmPw,
                              onTogglePassword: () => setState(
                                  () => _obscureRegPw = !_obscureRegPw),
                              onToggleConfirm: () => setState(
                                  () => _obscureConfirmPw = !_obscureConfirmPw),
                              usernameAvailable: _usernameAvailable,
                              checkingUsername: _checkingUsername,
                              onUsernameChanged: _onUsernameChanged,
                              errorMessage: _isSignUp ? _errorMessage : null,
                              shakeForm: _shakeForm && _isSignUp,
                              isLoading: auth.isLoading,
                              onRegister: _register,
                              onGoogleTap: _loginWithGoogle,
                            ),
                          ),
                        ),
                      ),

                      // ── .overlay-container ──
                      // left:50%, width:50% → active: translateX(-100%) = left:0
                      // Contient le dégradé + les deux panneaux overlay-left/right
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: half * (1 - t),
                        width: half,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [_kRed, _kRed2],
                            ),
                          ),
                          // Les deux panneaux overlay superposés
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // overlay-right : visible à t=0 ("Bienvenue!")
                              // translateX(0) → translateX(+20%) quand actif
                              IgnorePointer(
                                ignoring: t > 0.5,
                                child: Opacity(
                                  opacity: (1 - t * 2).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(t * half * 0.2, 0),
                                    child: _OverlayPanel(
                                      title: 'Bienvenue !',
                                      body:
                                          "Entrez vos informations personnelles et commencez l'aventure avec nous",
                                      buttonLabel: "S'INSCRIRE",
                                      onTap: _switchToSignUp,
                                    ),
                                  ),
                                ),
                              ),

                              // overlay-left : visible à t=1 ("Bon retour!")
                              // translateX(-20%) → translateX(0) quand actif
                              IgnorePointer(
                                ignoring: t <= 0.5,
                                child: Opacity(
                                  opacity: (t * 2 - 1).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset((t - 1) * half * 0.2, 0),
                                    child: _OverlayPanel(
                                      title: 'Bon retour !',
                                      body:
                                          'Pour rester connecté, veuillez vous identifier avec vos informations personnelles',
                                      buttonLabel: 'SE CONNECTER',
                                      onTap: _switchToSignIn,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Mobile ────────────────────────────────────────────────────────────────

  Widget _buildMobile(MediaQueryData media) {
    final auth = context.watch<AuthProvider>();

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final showSignUp = _anim.value >= 0.5;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_kRed, _kRed2],
                ),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _BackBtn(onTap: _handleBack, light: true),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    showSignUp ? 'Bienvenue !' : 'Bon retour !',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 16),
                    child: Text(
                      showSignUp
                          ? "Entrez vos informations personnelles et commencez l'aventure avec nous"
                          : 'Pour rester connecté, veuillez vous identifier avec vos informations personnelles',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w100,
                          height: 20 / 14,
                          letterSpacing: 0.5),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GhostBtn(
                          label: 'SE CONNECTER',
                          active: !showSignUp,
                          onTap: _switchToSignIn),
                      const SizedBox(width: 10),
                      _GhostBtn(
                          label: "S'INSCRIRE",
                          active: showSignUp,
                          onTap: _switchToSignUp),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: showSignUp
                      ? _FormSignUp(
                          key: const ValueKey('signup'),
                          usernameCtrl: _usernameCtrl,
                          pseudoCtrl: _pseudoCtrl,
                          emailCtrl: _emailCtrl,
                          passwordCtrl: _regPwCtrl,
                          confirmCtrl: _confirmPwCtrl,
                          obscurePassword: _obscureRegPw,
                          obscureConfirm: _obscureConfirmPw,
                          onTogglePassword: () =>
                              setState(() => _obscureRegPw = !_obscureRegPw),
                          onToggleConfirm: () => setState(
                              () => _obscureConfirmPw = !_obscureConfirmPw),
                          usernameAvailable: _usernameAvailable,
                          checkingUsername: _checkingUsername,
                          onUsernameChanged: _onUsernameChanged,
                          errorMessage: _errorMessage,
                          shakeForm: _shakeForm,
                          isLoading: auth.isLoading,
                          onRegister: _register,
                          mobileMode: true,
                          onSwitchToLogin: _switchToSignIn,
                          onGoogleTap: _loginWithGoogle,
                        )
                      : _FormSignIn(
                          key: const ValueKey('signin'),
                          identifierCtrl: _identifierCtrl,
                          passwordCtrl: _loginPwCtrl,
                          obscurePassword: _obscureLoginPw,
                          onTogglePassword: () => setState(
                              () => _obscureLoginPw = !_obscureLoginPw),
                          errorMessage: _errorMessage,
                          shakeForm: _shakeForm,
                          isLoading: auth.isLoading,
                          onLogin: _login,
                          onForgotPassword: () =>
                              context.push('/forgot-password'),
                          mobileMode: true,
                          onSwitchToSignUp: _switchToSignUp,
                          onGoogleTap: _loginWithGoogle,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Panneau overlay (h1 + p + button.ghost) ──────────────────────────────────
// Centré dans le container overlay, padding: 0 40px

class _OverlayPanel extends StatelessWidget {
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onTap;
  const _OverlayPanel(
      {required this.title,
      required this.body,
      required this.buttonLabel,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // .overlay-panel { padding: 0 40px }
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // h1 { font-weight: bold; margin: 0 }
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26),
          ),
          // p { font-size:14px; font-weight:100; line-height:20px; letter-spacing:0.5; margin:20px 0 30px }
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 30),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w100,
                  height: 20 / 14,
                  letterSpacing: 0.5),
            ),
          ),
          // button.ghost
          _CssButton(label: buttonLabel, ghost: true, onTap: onTap),
        ],
      ),
    );
  }
}

// ─── Formulaire Connexion ──────────────────────────────────────────────────────
// form { display:flex; align-items:center; justify-content:center; flex-direction:column;
//        padding:0 50px; height:100%; text-align:center }

class _FormSignIn extends StatelessWidget {
  final TextEditingController identifierCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final String? errorMessage;
  final bool shakeForm;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final bool mobileMode;
  final VoidCallback? onSwitchToSignUp;
  final VoidCallback? onGoogleTap;

  const _FormSignIn({
    super.key,
    required this.identifierCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.errorMessage,
    required this.shakeForm,
    required this.isLoading,
    required this.onLogin,
    required this.onForgotPassword,
    this.mobileMode = false,
    this.onSwitchToSignUp,
    this.onGoogleTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ShakeWrapper(
      shake: shakeForm,
      child: Container(
        color: Colors.white,
        // form { padding: 0 50px; height: 100% } + centré verticalement
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // h1
                const Text('Connexion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.bold,
                        fontSize: 24)),
                // .social-container { margin: 20px 0 }
                _SocialRow(onGoogleTap: onGoogleTap),
                // span { font-size: 12px }
                const Text('ou utilisez votre compte',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _kText)),
                AutofillGroup(
                  child: Column(
                    children: [
                      _CssInput(
                          controller: identifierCtrl,
                          hint: 'E-mail',
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email
                          ]),
                      _CssInput(
                          controller: passwordCtrl,
                          hint: 'Mot de passe',
                          obscure: obscurePassword,
                          action: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => onLogin(),
                          trailing: IconButton(
                              splashRadius: 16,
                              onPressed: onTogglePassword,
                              icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                  color: _kSpan))),
                    ],
                  ),
                ),
                if (errorMessage != null) _ErrorBox(message: errorMessage!),
                // a { color:#333; font-size:14px; margin:15px 0 }
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: GestureDetector(
                    onTap: onForgotPassword,
                    child: const Text('Mot de passe oublié ?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _kText,
                            fontSize: 14,
                            decoration: TextDecoration.none)),
                  ),
                ),
                _CssButton(
                    label: 'SE CONNECTER',
                    ghost: false,
                    isLoading: isLoading,
                    onTap: onLogin),
                if (mobileMode && onSwitchToSignUp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: GestureDetector(
                      onTap: onSwitchToSignUp,
                      child: const Text("Pas de compte ? S'inscrire",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _kRed, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Formulaire Inscription ────────────────────────────────────────────────────

class _FormSignUp extends StatelessWidget {
  final TextEditingController usernameCtrl;
  final TextEditingController pseudoCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final bool? usernameAvailable;
  final bool checkingUsername;
  final ValueChanged<String> onUsernameChanged;
  final String? errorMessage;
  final bool shakeForm;
  final bool isLoading;
  final VoidCallback onRegister;
  final bool mobileMode;
  final VoidCallback? onSwitchToLogin;
  final VoidCallback? onGoogleTap;

  const _FormSignUp({
    super.key,
    required this.usernameCtrl,
    required this.pseudoCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.usernameAvailable,
    required this.checkingUsername,
    required this.onUsernameChanged,
    required this.errorMessage,
    required this.shakeForm,
    required this.isLoading,
    required this.onRegister,
    this.mobileMode = false,
    this.onSwitchToLogin,
    this.onGoogleTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ShakeWrapper(
      shake: shakeForm,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Créer un compte',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.bold,
                        fontSize: 22)),
                _SocialRow(onGoogleTap: onGoogleTap),
                const Text("ou utilisez votre e-mail pour vous inscrire",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _kText)),
                AutofillGroup(
                  child: Column(
                    children: [
                      _CssInput(
                        controller: usernameCtrl,
                        hint: "Nom d'utilisateur",
                        action: TextInputAction.next,
                        autofillHints: const [AutofillHints.newUsername],
                        onChanged: onUsernameChanged,
                        trailing: checkingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: _kRed)))
                            : usernameAvailable == true
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF22C55E), size: 18)
                                : usernameAvailable == false
                                    ? const Icon(Icons.cancel,
                                        color: Color(0xFFF43F5E), size: 18)
                                    : null,
                      ),
                      _CssInput(
                          controller: pseudoCtrl,
                          hint: 'Pseudo',
                          action: TextInputAction.next),
                      _CssInput(
                          controller: emailCtrl,
                          hint: 'E-mail',
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.next,
                          autofillHints: const [AutofillHints.email]),
                      _CssInput(
                          controller: passwordCtrl,
                          hint: 'Mot de passe',
                          obscure: obscurePassword,
                          action: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          trailing: IconButton(
                              splashRadius: 16,
                              onPressed: onTogglePassword,
                              icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                  color: _kSpan))),
                      _CssInput(
                          controller: confirmCtrl,
                          hint: 'Répéter le mot de passe',
                          obscure: obscureConfirm,
                          action: TextInputAction.done,
                          onSubmitted: (_) => onRegister(),
                          trailing: IconButton(
                              splashRadius: 16,
                              onPressed: onToggleConfirm,
                              icon: Icon(
                                  obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                  color: _kSpan))),
                    ],
                  ),
                ),
                if (errorMessage != null) _ErrorBox(message: errorMessage!),
                const SizedBox(height: 16),
                _CssButton(
                    label: "S'INSCRIRE",
                    ghost: false,
                    isLoading: isLoading,
                    onTap: onRegister),
                if (mobileMode && onSwitchToLogin != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: GestureDetector(
                      onTap: onSwitchToLogin,
                      child: const Text('Déjà un compte ? Se connecter',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _kRed, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Widgets fidèles au CSS ────────────────────────────────────────────────────

/// input { background:#eee; border:none; padding:12px 15px; margin:8px 0; width:100% }
class _CssInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  const _CssInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.action,
    this.obscure = false,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8), // margin: 8px 0
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: action,
        obscureText: obscure,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        textAlign: TextAlign.left,
        style: const TextStyle(color: _kText, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kSpan, fontSize: 14),
          suffixIcon: trailing,
          filled: true,
          fillColor: _kInput, // #eee
          // input { border: none } — pas de border-radius dans le CSS original
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
          border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero, borderSide: BorderSide.none),
          enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero, borderSide: BorderSide.none),
          focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: _kRed, width: 1.5)),
        ),
      ),
    );
  }
}

/// button { border-radius:20px; border:1px solid #FF4B2B; background:#FF4B2B;
///          color:#fff; font-size:12px; font-weight:bold; padding:12px 45px;
///          letter-spacing:1px; text-transform:uppercase }
/// button:active { transform: scale(0.95) }
/// button.ghost { background:transparent; border-color:#fff }
class _CssButton extends StatefulWidget {
  final String label;
  final bool ghost;
  final bool isLoading;
  final VoidCallback? onTap;
  const _CssButton(
      {required this.label,
      required this.ghost,
      this.isLoading = false,
      this.onTap});

  @override
  State<_CssButton> createState() => _CssButtonState();
}

class _CssButtonState extends State<_CssButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isLoading) widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeIn,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 45),
          decoration: BoxDecoration(
            color: widget.ghost ? Colors.transparent : _kRed,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.ghost ? Colors.white : _kRed, width: 1),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Bouton Google officiel (sign_in_button)
/// .social-container { margin: 20px 0 }
class _SocialRow extends StatelessWidget {
  final VoidCallback? onGoogleTap;
  const _SocialRow({this.onGoogleTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SignInButton(
        Buttons.google,
        text: 'Continuer avec Google',
        onPressed: onGoogleTap ?? () {},
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Bouton ghost mobile
class _GhostBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _GhostBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? Colors.transparent : Colors.white, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _kRed : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// Message d'erreur
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x1AFF4B2B),
          border: Border.all(color: _kRed, width: 1),
        ),
        child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _kRed, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// Animation tremblement sur erreur
class _ShakeWrapper extends StatelessWidget {
  final bool shake;
  final Widget child;
  const _ShakeWrapper({required this.shake, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      tween: Tween<double>(begin: 0, end: shake ? 1 : 0),
      builder: (context, value, c) => Transform.translate(
        offset: Offset(math.sin(value * math.pi * 9) * 10 * (1 - value), 0),
        child: c,
      ),
      child: child,
    );
  }
}

/// Bouton retour
class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool light;
  const _BackBtn({required this.onTap, this.light = false});

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : _kText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.arrow_back, color: color, size: 20),
      ),
    );
  }
}
