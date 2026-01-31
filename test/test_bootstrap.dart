import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// SVG minimal valide pour les mocks d'assets
const String _minimalSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" viewBox="0 0 100 140">
  <rect width="100" height="140" fill="#1a472a" rx="8"/>
</svg>
''';

/// Configure les mocks pour les assets SVG globalement
/// Doit être appelé dans setUpAll() ou setUp() avant pumpWidget
void setupAssetMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock le channel flutter/assets pour intercepter les chargements d'assets
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/assets'),
    (MethodCall methodCall) async {
      // Retourne le SVG minimal en ByteData pour tous les assets demandés
      final bytes = utf8.encode(_minimalSvg);
      return ByteData.view(Uint8List.fromList(bytes).buffer);
    },
  );
}

/// Nettoie les mocks après les tests
void tearDownAssetMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/assets'),
    null,
  );
}
