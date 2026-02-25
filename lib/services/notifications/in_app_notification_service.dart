import 'dart:async';
import 'package:flutter/material.dart';

enum InAppNotificationType { friendRequest, friendAccepted, playerJoined, privateMessage }

class InAppNotificationPayload {
  final InAppNotificationType type;
  final String title;
  final String body;
  final VoidCallback? onTap;

  const InAppNotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    this.onTap,
  });
}

class InAppNotificationService {
  InAppNotificationService._();
  static final InAppNotificationService instance = InAppNotificationService._();

  final _controller = StreamController<InAppNotificationPayload>.broadcast();

  Stream<InAppNotificationPayload> get stream => _controller.stream;

  void show(InAppNotificationPayload payload) {
    _controller.add(payload);
  }

  void dispose() {
    _controller.close();
  }
}
