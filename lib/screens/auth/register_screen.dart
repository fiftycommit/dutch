import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/ui_constants.dart';

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
    if (!_formKey.currentState!.validate()) return;
    if (_usernameAvailable == false) return;

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
      context.go('/multiplayer');
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.gameBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.person_add, color: Colors.amber, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Creer un compte',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Username
                    TextFormField(
                      controller: _usernameController,
                      autofillHints: const [AutofillHints.newUsername],
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      onChanged: _onUsernameChanged,
                      decoration: _inputDecoration(
                              'Nom d\'utilisateur', Icons.alternate_email)
                          .copyWith(
                        suffixIcon: _checkingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.amber),
                                ),
                              )
                            : _usernameAvailable == true
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.success)
                                : _usernameAvailable == false
                                    ? const Icon(Icons.cancel,
                                        color: AppColors.error)
                                    : null,
                        helperText:
                            'Entre 3 et 20 caracteres (lettres, chiffres, . _ -)',
                        helperStyle: const TextStyle(
                            color: AppColors.textHint, fontSize: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Requis';
                        }
                        if (!_usernameRegex.hasMatch(v.trim())) {
                          return '3-20 caracteres, lettres/chiffres/._- uniquement';
                        }
                        if (_usernameAvailable == false) {
                          return 'Ce nom est deja pris';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Display name
                    TextFormField(
                      controller: _displayNameController,
                      autofillHints: const [AutofillHints.nickname],
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration:
                          _inputDecoration('Pseudo (nom affiche)', Icons.badge),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        if (v.trim().length > 24) return 'Max 24 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration:
                          _inputDecoration('Email', Icons.email_outlined),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        if (!_emailRegex.hasMatch(v.trim())) {
                          return 'Email invalide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      autofillHints: const [AutofillHints.newPassword],
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration:
                          _inputDecoration('Mot de passe', Icons.lock).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.textDisabled,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        helperText: 'Minimum 6 caracteres',
                        helperStyle: const TextStyle(
                            color: AppColors.textHint, fontSize: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requis';
                        if (v.length < 6) return 'Minimum 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Confirm password
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                              'Confirmer le mot de passe', Icons.lock_outline)
                          .copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.textDisabled,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Requis';
                        }
                        if (v != _passwordController.text) {
                          return 'Les mots de passe ne correspondent pas';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // Error message
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Register button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Text(
                                'Creer mon compte',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Login link
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text(
                        'Deja un compte ? Se connecter',
                        style: TextStyle(color: Colors.amber, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textDisabled),
      prefixIcon: Icon(icon, color: AppColors.textDisabled),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.amber, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }
}
