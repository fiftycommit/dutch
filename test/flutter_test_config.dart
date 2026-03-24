import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration globale pour les tests Flutter
/// Mock les assets SVG pour éviter les erreurs de chargement
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  SharedPreferences.setMockInitialValues({});

  // Mock le chargement des assets SVG
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/assets'),
    (MethodCall methodCall) async {
      // Retourne un SVG vide valide pour tous les assets
      if (methodCall.method == 'getAssetBundle') {
        return null;
      }
      return null;
    },
  );

  // Mock global path_provider pour les tests headless/CI.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
        case 'getLibraryDirectory':
        case 'getExternalStorageDirectory':
        case 'getDownloadsDirectory':
          return '/tmp/dutch_test';
        case 'getExternalCacheDirectories':
        case 'getExternalStorageDirectories':
          return <String>['/tmp/dutch_test'];
      }
      return '/tmp/dutch_test';
    },
  );

  await testMain();
}
