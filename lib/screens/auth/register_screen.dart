import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _pseudoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool? _usernameAvailable;
  bool _checkingUsername = false;
  bool _shakeForm = false;
  final bool _entered = true;
  String? _errorMessage;

  Timer? _usernameCheckTimer;
  Timer? _shakeResetTimer;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _usernameController.dispose();
    _pseudoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameCheckTimer?.cancel();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _usernameCheckTimer?.cancel();

    if (!_usernameRegex.hasMatch(value.trim())) {
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
      return;
    }

    setState(() => _checkingUsername = true);

    _usernameCheckTimer = Timer(const Duration(milliseconds: 450), () async {
      final authProvider = context.read<AuthProvider>();
      final available =
          await authProvider.authService.checkUsernameAvailable(value.trim());

      if (!mounted || _usernameController.text.trim() != value.trim()) {
        return;
      }
      setState(() {
        _usernameAvailable = available;
        _checkingUsername = false;
      });
    });
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final pseudo = _pseudoController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty ||
        pseudo.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'Tous les champs sont obligatoires');
      _triggerShake();
      return;
    }
    if (!_usernameRegex.hasMatch(username)) {
      setState(
        () => _errorMessage =
            'Nom d\'utilisateur invalide (3-20, lettres/chiffres/._-)',
      );
      _triggerShake();
      return;
    }
    if (_usernameAvailable == false) {
      setState(() => _errorMessage = 'Ce nom d\'utilisateur est déjà pris');
      _triggerShake();
      return;
    }
    if (pseudo.length > 24) {
      setState(
          () => _errorMessage = 'Le pseudo doit contenir 24 caractères max');
      _triggerShake();
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Ce n\'est pas un mail valide');
      _triggerShake();
      return;
    }
    if (password.length < 6) {
      setState(
        () => _errorMessage =
            'Le mot de passe doit contenir au moins 6 caractères',
      );
      _triggerShake();
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas');
      _triggerShake();
      return;
    }

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.register(
      username,
      pseudo,
      email,
      password,
    );

    if (!mounted) return;

    if (result.success) {
      TextInput.finishAutofillContext();
      final didPop = await Navigator.of(context).maybePop(true);
      if (!didPop && mounted) {
        context.go('/multiplayer');
      }
    } else {
      setState(() => _errorMessage = result.error);
      _triggerShake();
    }
  }

  Future<void> _handleBackToLogin() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/login');
    }
  }

  void _triggerShake() {
    setState(() => _shakeForm = true);
    _shakeResetTimer?.cancel();
    _shakeResetTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      setState(() => _shakeForm = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final media = MediaQuery.of(context);
    final noMotion = media.disableAnimations;
    final duration =
        noMotion ? Duration.zero : const Duration(milliseconds: 180);

    final layout = _AuthLayout.from(media);
    final themed = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.screenHorizontalPadding,
                      layout.headerTopPadding,
                      layout.screenHorizontalPadding,
                      0,
                    ),
                    child: AnimatedOpacity(
                      opacity: _entered || noMotion ? 1 : 0,
                      duration: duration,
                      child: AnimatedSlide(
                        offset: _entered || noMotion
                            ? Offset.zero
                            : const Offset(0, -0.08),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: _buildHeader(layout),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          layout.screenHorizontalPadding,
                          layout.formTopPadding,
                          layout.screenHorizontalPadding,
                          layout.formBottomPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: TweenAnimationBuilder<double>(
                            duration: noMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 360),
                            curve: Curves.easeOut,
                            tween: Tween<double>(
                              begin: 0,
                              end: _shakeForm ? 1 : 0,
                            ),
                            builder: (context, value, child) {
                              final translate = math.sin(value * math.pi * 9) *
                                  11 *
                                  (1 - value);
                              return Transform.translate(
                                offset: Offset(translate, 0),
                                child: child,
                              );
                            },
                            child: AnimatedOpacity(
                              opacity: _entered || noMotion ? 1 : 0,
                              duration: duration,
                              child: AnimatedSlide(
                                offset: _entered || noMotion
                                    ? Offset.zero
                                    : const Offset(0, 0.06),
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                child: _buildForm(
                                  layout: layout,
                                  loading: authProvider.isLoading,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_AuthLayout layout) {
    return Row(
      children: <Widget>[
        Material(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(layout.backButtonRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(layout.backButtonRadius),
            onTap: _handleBackToLogin,
            child: Padding(
              padding: EdgeInsets.all(layout.backButtonPadding),
              child: Icon(
                Icons.arrow_back,
                size: layout.backIconSize,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm({
    required _AuthLayout layout,
    required bool loading,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.center,
          child: Container(
            width: layout.iconContainerSize,
            height: layout.iconContainerSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFF59E0B), Color(0xFFF97316)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x33F59E0B),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: layout.iconSize,
            ),
          ),
        ),
        SizedBox(height: layout.spaceAfterIcon),
        Text(
          'Créer un compte',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1E293B),
            fontSize: layout.formTitleSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: layout.spaceAfterTitle),
        Text(
          'Rejoins la communauté Dutch',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFAEAEB2) : const Color(0xFF64748B),
            fontSize: layout.subtitleSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: layout.spaceBeforeFields),
        AutofillGroup(
          child: Column(
            children: <Widget>[
              _field(
                controller: _usernameController,
                hintText: 'Nom d\'utilisateur',
                prefix: _textPrefix(
                  '@',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newUsername],
                onChanged: _onUsernameChanged,
                suffix: _checkingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      )
                    : _usernameAvailable == true
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF22C55E))
                        : _usernameAvailable == false
                            ? const Icon(Icons.cancel, color: Color(0xFFF43F5E))
                            : null,
              ),
              SizedBox(height: layout.fieldGap),
              _field(
                controller: _pseudoController,
                hintText: 'Pseudo',
                prefix: _textPrefix(
                  '👤',
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: layout.fieldGap),
              _field(
                controller: _emailController,
                hintText: 'Email',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
              ),
              SizedBox(height: layout.fieldGap),
              _field(
                controller: _passwordController,
                hintText: 'Mot de passe',
                icon: Icons.lock_outline,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                suffix: IconButton(
                  splashRadius: 18,
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF94A3B8),
                    size: layout.suffixIconSize,
                  ),
                ),
              ),
              SizedBox(height: layout.fieldGap),
              _field(
                controller: _confirmPasswordController,
                hintText: 'Confirmer le mot de passe',
                icon: Icons.lock_outline,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _register(),
                suffix: IconButton(
                  splashRadius: 18,
                  onPressed: () {
                    setState(() => _obscureConfirm = !_obscureConfirm);
                  },
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF94A3B8),
                    size: layout.suffixIconSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          child: _errorMessage == null
              ? const SizedBox(height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1AF43F5E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFF43F5E), width: 1.4),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFE11D48),
                        fontSize: layout.errorSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ),
        SizedBox(height: layout.spaceBeforeButton),
        SizedBox(
          height: layout.buttonHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(layout.buttonRadius),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[Color(0xFFF59E0B), Color(0xFFF97316)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x38F59E0B),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: loading ? null : _register,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shadowColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(layout.buttonRadius),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Créer mon compte',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: layout.buttonTextSize,
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(height: layout.spaceAfterButton),
        TextButton(
          onPressed: _handleBackToLogin,
          style: TextButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(vertical: 2),
          ),
          child: RichText(
            text: TextSpan(
              text: 'Déjà un compte ? ',
              style: TextStyle(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w500,
                fontSize: layout.linkSize,
              ),
              children: const <InlineSpan>[
                TextSpan(
                  text: 'Se connecter',
                  style: TextStyle(
                    color: Color(0xFF4F46E5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hintText,
    IconData? icon,
    Widget? prefix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    Widget? suffix,
  }) {
    final hasError = _errorMessage != null;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        prefixIcon: prefix ??
            (icon != null
                ? Icon(icon, color: const Color(0xFF94A3B8), size: 18)
                : null),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFF334155),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: hasError ? const Color(0xFFF43F5E) : Colors.transparent,
            width: hasError ? 1.5 : 0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: hasError ? const Color(0xFFF43F5E) : const Color(0xFFF59E0B),
            width: 1.8,
          ),
        ),
      ),
    );
  }

  Widget _textPrefix(
    String text, {
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    return SizedBox(
      width: 44,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: const Color(0xFF94A3B8),
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
      ),
    );
  }
}

class _AuthLayout {
  const _AuthLayout({
    required this.screenHorizontalPadding,
    required this.headerTopPadding,
    required this.formTopPadding,
    required this.formBottomPadding,
    required this.backButtonRadius,
    required this.backButtonPadding,
    required this.backIconSize,
    required this.headerGap,
    required this.headerTitleSize,
    required this.iconContainerSize,
    required this.iconSize,
    required this.spaceAfterIcon,
    required this.formTitleSize,
    required this.spaceAfterTitle,
    required this.subtitleSize,
    required this.spaceBeforeFields,
    required this.fieldGap,
    required this.suffixIconSize,
    required this.errorSize,
    required this.spaceBeforeButton,
    required this.buttonHeight,
    required this.buttonRadius,
    required this.buttonTextSize,
    required this.spaceAfterButton,
    required this.linkSize,
  });

  final double screenHorizontalPadding;
  final double headerTopPadding;
  final double formTopPadding;
  final double formBottomPadding;
  final double backButtonRadius;
  final double backButtonPadding;
  final double backIconSize;
  final double headerGap;
  final double headerTitleSize;
  final double iconContainerSize;
  final double iconSize;
  final double spaceAfterIcon;
  final double formTitleSize;
  final double spaceAfterTitle;
  final double subtitleSize;
  final double spaceBeforeFields;
  final double fieldGap;
  final double suffixIconSize;
  final double errorSize;
  final double spaceBeforeButton;
  final double buttonHeight;
  final double buttonRadius;
  final double buttonTextSize;
  final double spaceAfterButton;
  final double linkSize;

  factory _AuthLayout.from(MediaQueryData media) {
    final width = media.size.width;
    final isLandscape = media.orientation == Orientation.landscape;
    final isDesktop = width >= 1100;

    return _AuthLayout(
      screenHorizontalPadding: isDesktop ? 28 : (isLandscape ? 12 : 14),
      headerTopPadding: isLandscape ? 8 : 12,
      formTopPadding: isLandscape ? 6 : 12,
      formBottomPadding: isLandscape ? 8 : 14,
      backButtonRadius: isLandscape ? 14 : 16,
      backButtonPadding: isLandscape ? 9 : 10,
      backIconSize: isLandscape ? 20 : 21,
      headerGap: isLandscape ? 10 : 10,
      headerTitleSize: isDesktop ? 40 : (isLandscape ? 24 : 30),
      iconContainerSize: isLandscape ? 68 : 72,
      iconSize: isLandscape ? 34 : 40,
      spaceAfterIcon: isLandscape ? 10 : 14,
      formTitleSize: isDesktop ? 52 : (isLandscape ? 30 : 40),
      spaceAfterTitle: isLandscape ? 4 : 6,
      subtitleSize: isLandscape ? 11 : 13,
      spaceBeforeFields: isLandscape ? 10 : 16,
      fieldGap: isLandscape ? 8 : 12,
      suffixIconSize: isLandscape ? 18 : 19,
      errorSize: isLandscape ? 11 : 12,
      spaceBeforeButton: isLandscape ? 8 : 12,
      buttonHeight: isLandscape ? 44 : 50,
      buttonRadius: isLandscape ? 14 : 16,
      buttonTextSize: isLandscape ? 15 : 17,
      spaceAfterButton: isLandscape ? 6 : 8,
      linkSize: isLandscape ? 11 : 14,
    );
  }
}
