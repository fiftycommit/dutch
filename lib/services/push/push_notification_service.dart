import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../notifications/in_app_notification_service.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;
  PushNotificationService._();

  static const String _webVapidKey =
      String.fromEnvironment('FCM_WEB_VAPID_KEY');

  bool _initialized = false;
  String? _fcmToken;

  /// Callbacks pour la navigation depuis les notifications
  Function(String roomCode)? onRoomInviteTapped;
  Function()? onFriendRequestTapped;

  /// Router for in-app navigation from notification taps
  GoRouter? router;

  String? get fcmToken => _fcmToken;
  bool get isInitialized => _initialized;

  Future<void> init(AuthService authService) async {
    if (_initialized) return;
    if (!_isSupportedPlatform) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('Push: permission refusée');
        return;
      }

      if (kIsWeb && _webVapidKey.isEmpty && kDebugMode) {
        debugPrint(
          'Push: FCM_WEB_VAPID_KEY manquante. '
          'Lance avec --dart-define=FCM_WEB_VAPID_KEY=... pour le web.',
        );
      }

      _fcmToken = await _obtainFcmToken(messaging);
      if (kDebugMode) debugPrint('Push: FCM token=$_fcmToken');

      if (_fcmToken != null) {
        final platform = _devicePlatformLabel;
        await authService.registerDeviceToken(_fcmToken!, platform);
      } else if (kDebugMode && _isApplePlatform) {
        debugPrint(
          'Push: APNS token pas encore prêt, enregistrement FCM différé.',
        );
      }

      messaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        final platform = _devicePlatformLabel;
        await authService.registerDeviceToken(newToken, platform);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      if (kDebugMode) debugPrint('Push: initialisé');
    } catch (e) {
      if (kDebugMode) debugPrint('Push: init failed: $e');
    }
  }

  Future<String?> _obtainFcmToken(FirebaseMessaging messaging) async {
    if (_isApplePlatform) {
      // iOS: APNS peut arriver après le boot de l'app.
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          final apns = await messaging.getAPNSToken();
          if (apns != null && apns.isNotEmpty) {
            break;
          }
        } catch (_) {
          // continue retry
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    try {
      return await messaging.getToken(
        vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
      );
    } catch (e) {
      // Ne bloque pas tout le flux push si le token n'est pas prêt.
      if (kDebugMode) debugPrint('Push: getToken deferred: $e');
      return null;
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint(
          'Push foreground: ${message.notification?.title} - ${message.data}');
    }

    final data = message.data;
    final type = data['type'] as String?;
    final notification = message.notification;
    final currentLocation =
        router?.routerDelegate.currentConfiguration.uri.path ?? '';

    switch (type) {
      case 'friend_request':
        final fromUsername = data['fromUsername'] as String? ?? 'Quelqu\'un';
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.friendRequest,
          title: 'Demande d\'ami',
          body: '$fromUsername veut être ton ami',
          onTap: () => router?.go('/friends?tab=1'),
        ));
        break;
      case 'friend_accepted':
        final fromUsername = data['fromUsername'] as String? ?? 'Un ami';
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.friendAccepted,
          title: 'Ami accepté !',
          body: '$fromUsername est maintenant ton ami',
          onTap: () => router?.go('/friends'),
        ));
        break;
      case 'chat_message':
        final senderId = data['senderId'] as String?;
        if (senderId != null &&
            currentLocation == '/friends/chat/$senderId') {
          return;
        }
        final title = notification?.title ?? 'Message';
        final body = notification?.body ?? '';
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.privateMessage,
          title: title,
          body: body,
          onTap: () {
            if (senderId != null) router?.go('/friends/chat/$senderId');
          },
        ));
        break;
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;

    switch (type) {
      case 'room_invite':
        final roomCode = data['roomCode'] as String?;
        if (roomCode != null) {
          onRoomInviteTapped?.call(roomCode);
        }
        break;
      case 'friend_request':
      case 'friend_accepted':
        onFriendRequestTapped?.call();
        break;
    }
  }

  void dispose() {
    _initialized = false;
    _fcmToken = null;
  }

  bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _isSupportedPlatform =>
      kIsWeb ||
      _isApplePlatform ||
      defaultTargetPlatform == TargetPlatform.android;

  String get _devicePlatformLabel {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.macOS) return 'macos';
    return 'android';
  }
}
