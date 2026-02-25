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
  InAppNotificationPayload? _current;

  @override
  void initState() {
    super.initState();
    _sub = InAppNotificationService.instance.stream.listen(_onNotification);
  }

  void _onNotification(InAppNotificationPayload payload) {
    if (_queue.length >= 3) _queue.removeFirst();
    _queue.add(payload);
    if (_current == null) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) return;
    setState(() => _current = _queue.removeFirst());
  }

  void _onDismiss() {
    setState(() => _current = null);
    if (_queue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _showNext();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_current != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                type: MaterialType.transparency,
                child: InAppNotificationBanner(
                key: ValueKey(_current.hashCode),
                payload: _current!,
                onDismiss: _onDismiss,
              )),
            ),
        ],
      ),
    );
  }
}
