import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Configuration globale pour les tests Flutter
/// Mock les assets SVG pour éviter les erreurs de chargement
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
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

  await testMain();
}
