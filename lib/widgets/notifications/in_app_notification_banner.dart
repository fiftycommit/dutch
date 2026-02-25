import 'dart:async';
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
  State<InAppNotificationBanner> createState() => _InAppNotificationBannerState();
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
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_animController);

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

  Color _iconColor() {
    switch (widget.payload.type) {
      case InAppNotificationType.friendRequest:
      case InAppNotificationType.friendAccepted:
        return const Color(0xFF34C759);
      case InAppNotificationType.playerJoined:
        return const Color(0xFFFF9500);
      case InAppNotificationType.privateMessage:
        return const Color(0xFF007AFF);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: () {
            widget.payload.onTap?.call();
            _dismiss();
          },
          onVerticalDragEnd: (details) {
            if (details.velocity.pixelsPerSecond.dy < -100) {
              _dismiss();
            }
          },
          child: Container(
            margin: EdgeInsets.only(top: topPadding + 8, left: 12, right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _iconColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon(), color: _iconColor(), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.payload.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.payload.body,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _dismiss,
                  child: Icon(
                    Icons.close,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
