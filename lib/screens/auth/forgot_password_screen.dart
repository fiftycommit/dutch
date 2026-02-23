import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  String? _message;
  String? _error;
  bool _shakeForm = false;
  final bool _entered = true;
  Timer? _shakeResetTimer;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _error = 'L\'email est obligatoire';
        _message = null;
      });
      _triggerShake();
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() {
        _error = 'Email invalide';
        _message = null;
      });
      _triggerShake();
      return;
    }

    setState(() {
      _message = null;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.forgotPassword(email);
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _message =
            'Si un compte existe avec cet email, un lien de réinitialisation a été envoyé.';
      });
    } else {
      setState(() {
        _error = result.error ?? 'Erreur';
      });
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

  Widget _buildForm({required _AuthLayout layout, required bool loading}) {
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
                colors: <Color>[Color(0xFFFB923C), Color(0xFFEF4444)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x38FB923C),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.lock_outline,
              color: Colors.white,
              size: layout.iconSize,
            ),
          ),
        ),
        SizedBox(height: layout.spaceAfterIcon),
        Text(
          'Réinitialiser',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1E293B),
            fontSize: layout.formTitleSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: layout.spaceAfterTitle),
        Text(
          'Entre ton email pour recevoir un lien de réinitialisation',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFAEAEB2) : const Color(0xFF64748B),
            fontSize: layout.subtitleSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: layout.spaceBeforeFields),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          autofillHints: const <String>[AutofillHints.email],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Email',
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            prefixIcon: const Icon(Icons.mail_outline,
                color: Color(0xFF94A3B8), size: 18),
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
                color: _error == null
                    ? Colors.transparent
                    : const Color(0xFFF43F5E),
                width: _error == null ? 0 : 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _error == null
                    ? const Color(0xFFFB923C)
                    : const Color(0xFFF43F5E),
                width: 1.8,
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          child: _error == null
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
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFE11D48),
                        fontSize: layout.feedbackSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          child: _message == null
              ? const SizedBox(height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1422C55E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0x8822C55E), width: 1.3),
                    ),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF15803D),
                        fontSize: layout.feedbackSize,
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
                colors: <Color>[Color(0xFFFB923C), Color(0xFFEF4444)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x38FB923C),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: loading ? null : _submit,
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
                      'Envoyer le lien',
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
              text: 'Retour à la ',
              style: TextStyle(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w500,
                fontSize: layout.linkSize,
              ),
              children: const <InlineSpan>[
                TextSpan(
                  text: 'connexion',
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
    required this.feedbackSize,
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
  final double feedbackSize;
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
      headerTitleSize: isDesktop ? 40 : (isLandscape ? 22 : 28),
      iconContainerSize: isLandscape ? 68 : 72,
      iconSize: isLandscape ? 34 : 40,
      spaceAfterIcon: isLandscape ? 10 : 14,
      formTitleSize: isDesktop ? 52 : (isLandscape ? 30 : 40),
      spaceAfterTitle: isLandscape ? 4 : 6,
      subtitleSize: isLandscape ? 11 : 13,
      spaceBeforeFields: isLandscape ? 10 : 16,
      feedbackSize: isLandscape ? 11 : 12,
      spaceBeforeButton: isLandscape ? 8 : 12,
      buttonHeight: isLandscape ? 44 : 50,
      buttonRadius: isLandscape ? 14 : 16,
      buttonTextSize: isLandscape ? 15 : 17,
      spaceAfterButton: isLandscape ? 6 : 8,
      linkSize: isLandscape ? 11 : 14,
    );
  }
}
