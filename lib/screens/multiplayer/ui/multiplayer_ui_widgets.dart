import 'package:flutter/material.dart';

import 'multiplayer_ui_tokens.dart';
import '../../../utils/ui_constants.dart';

class MpHeader extends StatelessWidget {
  const MpHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing = const <Widget>[],
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final titleGradient = LinearGradient(
      colors: <Color>[
        AppColors.primary.withValues(alpha: 0.98),
        AppColors.primaryDark.withValues(alpha: 0.98),
      ],
    );

    return Row(
      children: <Widget>[
        _HeaderIconButton(
          icon: Icons.arrow_back,
          onPressed: onBack,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ShaderMask(
            shaderCallback: (bounds) => titleGradient.createShader(bounds),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        if (trailing.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trailing,
          ),
      ],
    );
  }
}

class MpPill extends StatelessWidget {
  const MpPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MultiplayerUiTokens.surfaceCardStrong(),
      borderRadius: MultiplayerUiTokens.radiusPill,
      child: InkWell(
        borderRadius: MultiplayerUiTokens.radiusPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: MultiplayerUiTokens.onSurfacePrimary, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: MultiplayerUiTokens.onSurfacePrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MpActionCard extends StatelessWidget {
  const MpActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
    this.actionLabel = 'Ouvrir',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final Color? accent;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final primary = accent ?? MultiplayerUiTokens.accentPrimary;
    return MpSectionCard(
      padding: const EdgeInsets.all(24),
      child: InkWell(
        borderRadius: MultiplayerUiTokens.radiusLg,
        onTap: () async {
          await onTap();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: <Color>[
                    primary.withValues(alpha: 0.95),
                    primary.withValues(alpha: 0.7),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.32),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: MultiplayerUiTokens.onSurfacePrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.06,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                color: MultiplayerUiTokens.onSurfaceSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Text(
                  actionLabel,
                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFFB45309)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MpSectionCard extends StatelessWidget {
  const MpSectionCard({
    super.key,
    this.icon,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final IconData? icon;
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MultiplayerUiTokens.surfaceCard(),
        borderRadius: MultiplayerUiTokens.radiusLg,
        border: Border.all(color: MultiplayerUiTokens.outline()),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null || icon != null || trailing != null) ...<Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon,
                        color: MultiplayerUiTokens.onSurfacePrimary, size: 20),
                    const SizedBox(width: 8),
                  ],
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: MultiplayerUiTokens.onSurfacePrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class MpEmptyState extends StatelessWidget {
  const MpEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: MultiplayerUiTokens.onSurfaceSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MultiplayerUiTokens.onSurfaceSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MultiplayerUiTokens.onSurfaceSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class MpTextField extends StatelessWidget {
  const MpTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction,
    this.suffixIcon,
    this.autofillHints,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.textDisabled,
          fontWeight: FontWeight.w500,
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
            color: MultiplayerUiTokens.accentPrimary.withValues(alpha: 0.9),
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MultiplayerUiTokens.surfaceCardStrong(),
      borderRadius: MultiplayerUiTokens.radiusMd,
      child: InkWell(
        borderRadius: MultiplayerUiTokens.radiusMd,
        onTap: onPressed,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: MultiplayerUiTokens.onSurfacePrimary,
            size: 24,
          ),
        ),
      ),
    );
  }
}
