import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/notifications/in_app_notification_service.dart';

class InAppNotificationBanner extends StatefulWidget {
  final InAppNotificationPayload payload;
  final VoidCallback onDismiss;

  const InAppNotificationBanner({
    super.key,
    required this.payload,
    required this.onDismiss,
  });

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
    _autoDismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Color _accentColor() {
    switch (widget.payload.type) {
      case InAppNotificationType.friendRequest:
      case InAppNotificationType.friendAccepted:
        return const Color(0xFF34C759);
      case InAppNotificationType.playerJoined:
        return const Color(0xFFFF9500);
      case InAppNotificationType.privateMessage:
        return const Color(0xFF007AFF);
      case InAppNotificationType.wizz:
        return const Color(0xFFFF9F0A);
      case InAppNotificationType.yourTurn:
        return const Color(0xFF30D158);
    }
  }

  IconData _icon() {
    switch (widget.payload.type) {
      case InAppNotificationType.friendRequest:
      case InAppNotificationType.friendAccepted:
        return Icons.person_add_rounded;
      case InAppNotificationType.playerJoined:
        return Icons.group_add_rounded;
      case InAppNotificationType.privateMessage:
        return Icons.chat_bubble_rounded;
      case InAppNotificationType.wizz:
        return Icons.notification_important_rounded;
      case InAppNotificationType.yourTurn:
        return Icons.style_rounded;
    }
  }

  String _appLabel() {
    switch (widget.payload.type) {
      case InAppNotificationType.friendRequest:
      case InAppNotificationType.friendAccepted:
        return 'DUTCH · Amis';
      case InAppNotificationType.playerJoined:
        return 'DUTCH · Salon';
      case InAppNotificationType.privateMessage:
        return 'DUTCH · Message';
      case InAppNotificationType.wizz:
        return 'DUTCH · Wizz';
      case InAppNotificationType.yourTurn:
        return 'DUTCH · À toi !';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: () {
            InAppNotificationService.instance.handleTap(widget.payload);
            _dismiss();
          },
          onVerticalDragEnd: (details) {
            if (details.velocity.pixelsPerSecond.dy < -100) _dismiss();
          },
          child: Container(
            margin: EdgeInsets.only(top: topPadding + 8, left: 10, right: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // App icon
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _accentColor(),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(_icon(), color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      // Text content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // App label + time
                            Row(
                              children: [
                                Text(
                                  _appLabel(),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : Colors.black.withValues(alpha: 0.4),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'maintenant',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.35)
                                        : Colors.black.withValues(alpha: 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            // Title
                            Text(
                              widget.payload.title,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            // Body
                            Text(
                              widget.payload.body,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.black.withValues(alpha: 0.55),
                                fontSize: 14,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
