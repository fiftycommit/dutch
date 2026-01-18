import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../utils/screen_utils.dart';

class HapticButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isEnabled;
  final IconData? icon;
  final double? width;
  final double? height;

  const HapticButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.backgroundColor,
    this.foregroundColor,
    this.isEnabled = true,
    this.icon,
    this.width,
    this.height,
  });

  @override
  State<HapticButton> createState() => _HapticButtonState();
}

class _HapticButtonState extends State<HapticButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.isEnabled && widget.onPressed != null) {
      _scaleController.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  void _handleTap() {
    if (widget.isEnabled && widget.onPressed != null) {
      HapticService.buttonTap();
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.isEnabled || widget.onPressed == null;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width ?? double.infinity,
              height: widget.height ?? ScreenUtils.buttonHeight(context),
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.grey.shade600
                    : (widget.backgroundColor ?? const Color(0xFF2d5f3e)),
                borderRadius: BorderRadius.circular(
                  ScreenUtils.borderRadius(context, 12),
                ),
                boxShadow: isDisabled
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Center(
                child: widget.icon != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.icon,
                            color: isDisabled
                                ? Colors.grey.shade400
                                : (widget.foregroundColor ?? Colors.white),
                            size: ScreenUtils.scale(context, 20),
                          ),
                          SizedBox(width: ScreenUtils.spacing(context, 8)),
                          Text(
                            widget.text,
                            style: TextStyle(
                              color: isDisabled
                                  ? Colors.grey.shade400
                                  : (widget.foregroundColor ?? Colors.white),
                              fontSize: ScreenUtils.scaleFont(context, 18),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        widget.text,
                        style: TextStyle(
                          color: isDisabled
                              ? Colors.grey.shade400
                              : (widget.foregroundColor ?? Colors.white),
                          fontSize: ScreenUtils.scaleFont(context, 18),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
