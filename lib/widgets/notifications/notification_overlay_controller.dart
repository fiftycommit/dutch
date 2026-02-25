import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../services/notifications/in_app_notification_service.dart';
import 'in_app_notification_banner.dart';

class NotificationOverlayController extends StatefulWidget {
  final Widget child;

  const NotificationOverlayController({super.key, required this.child});

  @override
  State<NotificationOverlayController> createState() =>
      _NotificationOverlayControllerState();
}

class _NotificationOverlayControllerState
    extends State<NotificationOverlayController> {
  StreamSubscription<InAppNotificationPayload>? _sub;
  final _queue = Queue<InAppNotificationPayload>();
  OverlayEntry? _currentEntry;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _sub = InAppNotificationService.instance.stream.listen(_onNotification);
  }

  void _onNotification(InAppNotificationPayload payload) {
    if (_queue.length >= 3) _queue.removeFirst();
    _queue.add(payload);
    _showNext();
  }

  void _showNext() {
    if (_showing || _queue.isEmpty) return;
    _showing = true;

    final payload = _queue.removeFirst();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = Overlay.of(context, rootOverlay: true);
      _currentEntry = OverlayEntry(
        builder: (_) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: InAppNotificationBanner(
              payload: payload,
              onDismiss: _onDismiss,
            ),
          ),
        ),
      );
      overlay.insert(_currentEntry!);
    });
  }

  void _onDismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
    _showing = false;
    if (_queue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 200), _showNext);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _currentEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
