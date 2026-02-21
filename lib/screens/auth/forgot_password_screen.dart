import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../utils/ui_constants.dart';
import '../multiplayer/ui/multiplayer_motion.dart';
import '../multiplayer/ui/multiplayer_ui_tokens.dart';
import '../multiplayer/ui/multiplayer_ui_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _message;
  String? _error;
  bool _shakeForm = false;
  Timer? _shakeResetTimer;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _triggerShake();
      return;
    }

    setState(() {
      _message = null;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final result =
        await authProvider.forgotPassword(_emailController.text.trim());
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
    _shakeResetTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _shakeForm = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final motionEnabled = MultiplayerUiTokens.motionEnabled(context);

    return Scaffold(
      body: Container(
        decoration: MultiplayerUiTokens.pageBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: <Widget>[
                fadeInUp(
                  delay: motionEnabled ? staggerIndexDelay(0) : Duration.zero,
                  child: MpHeader(
                    title: 'Mot de passe oublié',
                    onBack: _handleBackToLogin,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: fadeInUp(
                          delay: motionEnabled
                              ? staggerIndexDelay(1)
                              : Duration.zero,
                          child: _buildCard(authProvider),
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
    );
  }

  Widget _buildCard(AuthProvider authProvider) {
    final compact = MediaQuery.of(context).size.width < 420;

    return shakeOnError(
      shake: _shakeForm,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFFF59E0B),
                      Color(0xFFD97706),
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.warning.withValues(alpha: 0.3),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Réinitialiser',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 40 : 52,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Entre ton email pour recevoir un lien de réinitialisation',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 26),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.email],
              onFieldSubmitted: (_) => _submit(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                if (!_emailRegex.hasMatch(v.trim())) {
                  return 'Email invalide';
                }
                return null;
              },
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: const TextStyle(
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w500,
                  fontSize: 17,
                ),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: AppColors.textDisabled,
                ),
                filled: true,
                fillColor: Color(0xDD4E6B58),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: AppColors.warning.withValues(alpha: 0.9),
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: AppColors.error, width: 1.5),
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF59E0B), Color(0xFFD97706)],
                  ),
                ),
                child: ElevatedButton(
                  onPressed: authProvider.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Envoyer le lien',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
