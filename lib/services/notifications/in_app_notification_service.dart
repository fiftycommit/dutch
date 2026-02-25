import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum InAppNotificationType { friendRequest, friendAccepted, playerJoined, privateMessage }

class InAppNotificationPayload {
  final InAppNotificationType type;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final String? route;

  const InAppNotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    this.onTap,
    this.route,
  });
}

class InAppNotificationService {
  InAppNotificationService._();
  static final InAppNotificationService instance = InAppNotificationService._();

  final _controller = StreamController<InAppNotificationPayload>.broadcast();
  GoRouter? router;

  Stream<InAppNotificationPayload> get stream => _controller.stream;

  void show(InAppNotificationPayload payload) {
    _controller.add(payload);
  }

  void handleTap(InAppNotificationPayload payload) {
    if (payload.onTap != null) {
      payload.onTap!();
    } else if (payload.route != null && router != null) {
      router!.push(payload.route!);
    }
  }

  void dispose() {
    _controller.close();
  }
}
