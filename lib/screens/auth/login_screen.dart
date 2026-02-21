import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _shakeForm = false;
  final bool _entered = true;
  String? _errorMessage;
  Timer? _shakeResetTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty) {
      setState(() => _errorMessage = 'Email ou pseudo requis');
      _triggerShake();
      return;
    }
    if (identifier.contains(' ')) {
      setState(() => _errorMessage = 'Email ou pseudo invalide');
      _triggerShake();
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Mot de passe requis');
      _triggerShake();
      return;
    }

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.login(identifier, password);

    if (!mounted) return;

    if (result.success) {
      TextInput.finishAutofillContext();
      await _completeAuthSuccess();
    } else {
      setState(() => _errorMessage = result.error);
      _triggerShake();
    }
  }

  Future<void> _completeAuthSuccess() async {
    final didPop = await Navigator.of(context).maybePop(true);
    if (!didPop && mounted) {
      context.go('/multiplayer');
    }
  }

  Future<void> _handleBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/');
    }
  }

  Future<void> _openRegister() async {
    final registered = await context.push<bool>('/register');
    if (!mounted || registered != true) return;
    await _completeAuthSuccess();
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

    final layout = _AuthLayout.from(media, context);
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
          color: Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(layout.backButtonRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(layout.backButtonRadius),
            onTap: _handleBack,
            child: Padding(
              padding: EdgeInsets.all(layout.backButtonPadding),
              child: Icon(
                Icons.arrow_back,
                size: layout.backIconSize,
                color: const Color(0xFF334155),
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
                colors: <Color>[Color(0xFF6366F1), Color(0xFF9333EA)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x3D6366F1),
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
          'Connexion',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF334155),
            fontSize: layout.formTitleSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: layout.spaceAfterTitle),
        Text(
          'Connecte-toi pour jouer en multijoueur',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: layout.subtitleSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: layout.spaceBeforeFields),
        AutofillGroup(
          child: Column(
            children: <Widget>[
              _field(
                controller: _identifierController,
                hintText: 'Email ou nom d\'utilisateur',
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.text,
                autofillHints: const <String>[
                  AutofillHints.username,
                  AutofillHints.email,
                ],
              ),
              SizedBox(height: layout.fieldGap),
              _field(
                controller: _passwordController,
                hintText: 'Mot de passe',
                icon: Icons.lock_outline,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                onSubmitted: (_) => _login(),
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
                colors: <Color>[Color(0xFF6366F1), Color(0xFFA21CAF)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x386366F1),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: loading ? null : _login,
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
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Se connecter',
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: layout.buttonTextSize,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(height: layout.spaceAfterButton),
        TextButton(
          onPressed: () => context.push('/forgot-password'),
          style: TextButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(vertical: 2),
          ),
          child: Text(
            'Mot de passe oublié ?',
            style: TextStyle(
              color: const Color(0xFF4F46E5),
              fontWeight: FontWeight.w500,
              fontSize: layout.linkSize,
            ),
          ),
        ),
        TextButton(
          onPressed: _openRegister,
          style: TextButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(vertical: 2),
          ),
          child: RichText(
            text: TextSpan(
              text: 'Pas encore de compte ? ',
              style: TextStyle(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w500,
                fontSize: layout.linkSize,
              ),
              children: const <InlineSpan>[
                TextSpan(
                  text: 'S\'inscrire',
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
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
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
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF334155),
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
            color: hasError ? const Color(0xFFF43F5E) : const Color(0xFF6366F1),
            width: 1.8,
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

  factory _AuthLayout.from(MediaQueryData media, BuildContext context) {
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
      headerTitleSize: isDesktop ? 42 : (isLandscape ? 26 : 32),
      iconContainerSize: isLandscape ? 68 : 72,
      iconSize: isLandscape ? 34 : 40,
      spaceAfterIcon: isLandscape ? 10 : 14,
      formTitleSize: isDesktop ? 56 : (isLandscape ? 32 : 42),
      spaceAfterTitle: isLandscape ? 4 : 6,
      subtitleSize: isLandscape ? 11 : 13,
      spaceBeforeFields: isLandscape ? 10 : 16,
      fieldGap: isLandscape ? 8 : 12,
      suffixIconSize: isLandscape ? 18 : 19,
      errorSize: isLandscape ? 11 : 12,
      spaceBeforeButton: isLandscape ? 8 : 12,
      buttonHeight: isLandscape ? 44 : 50,
      buttonRadius: isLandscape ? 14 : 16,
      buttonTextSize: isLandscape ? 16 : 18,
      spaceAfterButton: isLandscape ? 6 : 8,
      linkSize: isLandscape ? 11 : 14,
    );
  }
}
