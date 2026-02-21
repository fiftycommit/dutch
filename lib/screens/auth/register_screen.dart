import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../utils/ui_constants.dart';
import '../multiplayer/ui/multiplayer_motion.dart';
import '../multiplayer/ui/multiplayer_ui_tokens.dart';
import '../multiplayer/ui/multiplayer_ui_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  bool? _usernameAvailable;
  Timer? _usernameCheckTimer;
  bool _checkingUsername = false;
  bool _shakeForm = false;
  Timer? _shakeResetTimer;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameCheckTimer?.cancel();
    _shakeResetTimer?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _usernameCheckTimer?.cancel();

    if (!_usernameRegex.hasMatch(value)) {
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
      return;
    }

    setState(() => _checkingUsername = true);

    _usernameCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      final authProvider = context.read<AuthProvider>();
      final available =
          await authProvider.authService.checkUsernameAvailable(value);
      if (mounted && _usernameController.text == value) {
        setState(() {
          _usernameAvailable = available;
          _checkingUsername = false;
        });
      }
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || _usernameAvailable == false) {
      _triggerShake();
      return;
    }

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.register(
      _usernameController.text.trim(),
      _displayNameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
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
                    title: 'S\'inscrire',
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
                          child: _buildRegisterCard(authProvider),
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

  Widget _buildRegisterCard(AuthProvider authProvider) {
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
                        AppColors.primary.withValues(alpha: 0.95),
                        AppColors.primaryDark.withValues(alpha: 0.9),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_add_alt_1,
                      color: Colors.white, size: 52),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Créer un compte',
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
                'Rejoins la communauté Dutch',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 26),
              _buildField(
                controller: _usernameController,
                hintText: 'Nom d\'utilisateur',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newUsername],
                onChanged: _onUsernameChanged,
                suffixIcon: _checkingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : _usernameAvailable == true
                        ? const Icon(Icons.check_circle,
                            color: AppColors.success)
                        : _usernameAvailable == false
                            ? const Icon(Icons.cancel, color: AppColors.error)
                            : null,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requis';
                  if (!_usernameRegex.hasMatch(v.trim())) {
                    return '3-20 caractères, lettres/chiffres/._-';
                  }
                  if (_usernameAvailable == false) {
                    return 'Ce nom est déjà pris';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'Entre 3 et 20 caractères (lettres, chiffres, . _ -)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _displayNameController,
                hintText: 'Pseudo (nom affiché)',
                icon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.nickname],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requis';
                  if (v.trim().length > 24) return 'Max 24 caractères';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _emailController,
                hintText: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requis';
                  if (!_emailRegex.hasMatch(v.trim())) {
                    return 'Ce n\'est pas un mail valide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _passwordController,
                hintText: 'Mot de passe',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
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
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requis';
                  if (v.length < 6) return 'Minimum 6 caractères';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _confirmPasswordController,
                hintText: 'Confirmer le mot de passe',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _register(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscureConfirm = !_obscureConfirm);
                  },
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textDisabled,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requis';
                  if (v != _passwordController.text) {
                    return 'Les mots de passe ne correspondent pas';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
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
                  ),
                  child: ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
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
                            'Créer mon compte',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _handleBackToLogin,
                child: const Text(
                  'Déjà un compte ? Se connecter',
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
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onChanged: onChanged,
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
