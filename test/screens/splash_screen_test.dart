import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/screens/splash_screen.dart';

class _TestAuthProvider extends AuthProvider {
  bool initialized = false;

  @override
  bool get isInitialized => initialized;

  void finishInitialization() {
    initialized = true;
    notifyListeners();
  }
}

void main() {
  Future<void> mountSplash(WidgetTester tester, _TestAuthProvider auth) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final logo = File('assets/images/cards/joker-rouge.vec').readAsBytesSync();
    messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData.sublistView(logo),
    );
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/', builder: (_, __) => const Text('Destination')),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('attend auth puis navigue dès sa notification', (tester) async {
    final auth = _TestAuthProvider();
    await mountSplash(tester, auth);
    expect(find.text('Destination'), findsNothing);

    auth.finishInitialization();
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
  });

  testWidgets('continue après le délai de restauration auth', (tester) async {
    final auth = _TestAuthProvider();
    await mountSplash(tester, auth);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
  });
}
