import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../auth/auth_service.dart';

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

      _fcmToken = await messaging.getToken(
        vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
      );
      if (kDebugMode) debugPrint('Push: FCM token=$_fcmToken');

      if (_fcmToken != null) {
        final platform = _devicePlatformLabel;
        await authService.registerDeviceToken(_fcmToken!, platform);
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

  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint(
          'Push foreground: ${message.notification?.title} - ${message.data}');
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
