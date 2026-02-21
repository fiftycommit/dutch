import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../multiplayer/ui/multiplayer_motion.dart';
import '../multiplayer/ui/multiplayer_ui_tokens.dart';
import '../multiplayer/ui/multiplayer_ui_widgets.dart';
import '../../utils/ui_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _shakeForm = false;
  Timer? _shakeResetTimer;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      _triggerShake();
      return;
    }

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.login(
      _identifierController.text.trim(),
      _passwordController.text,
    );

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
                    title: 'Multijoueur',
                    onBack: _handleBack,
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
                          child: _buildAuthCard(authProvider),
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

  Widget _buildAuthCard(AuthProvider authProvider) {
    final compact = MediaQuery.of(context).size.width < 420;

    return AutofillGroup(
      child: shakeOnError(
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
                    gradient: LinearGradient(
                      colors: <Color>[
                        AppColors.primary.withValues(alpha: 0.96),
                        AppColors.primaryDark.withValues(alpha: 0.92),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.32),
                        blurRadius: 18,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_outline,
                      color: Colors.white, size: 54),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Connexion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 42 : 56,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Connecte-toi pour jouer en multijoueur',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 30),
              _buildField(
                controller: _identifierController,
                hintText: 'Email ou pseudo',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requis';
                  if (v.trim().contains(' ')) return 'Email ou pseudo invalide';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _passwordController,
                hintText: 'Mot de passe',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                onFieldSubmitted: (_) => _login(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textDisabled,
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 60,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: <Color>[
                        AppColors.primary.withValues(alpha: 0.98),
                        AppColors.primaryDark.withValues(alpha: 0.96),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.34),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      shadowColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
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
                            'Se connecter',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                  ),
                ),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.push('/forgot-password'),
                child: const Text(
                  'Mot de passe oublié ?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openRegister,
                child: const Text(
                  'Pas encore de compte ? Créer un compte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    ValueChanged<String>? onFieldSubmitted,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    Iterable<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.textDisabled,
          fontWeight: FontWeight.w500,
          fontSize: 17,
        ),
        prefixIcon: Icon(icon, color: AppColors.textDisabled),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xDD4E6B58),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.9),
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}
