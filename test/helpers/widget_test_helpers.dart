import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/widgets/game/svg_builder_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';

/// SVG builder for tests - returns a simple colored box instead of SVG
Widget testSvgBuilder(String assetPath, double width, double height) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF1a472a),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.white24),
    ),
  );
}

/// Helper pour configurer les tests de widgets
class WidgetTestHelpers {
  /// Standard test screen size
  static const Size defaultSize = Size(1280, 720);

  /// Wrapper complet pour tests de widgets avec SvgBuilderProvider et SettingsProvider
  /// Inclut MediaQuery, MaterialApp, Scaffold avec taille fixe
  static Widget wrapWithTestApp(Widget child, {Size? size, bool mockSvg = true}) {
    final screenSize = size ?? defaultSize;
    Widget app = MediaQuery(
      data: MediaQueryData(
        size: screenSize,
        devicePixelRatio: 1.0,
        padding: EdgeInsets.zero,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: child,
          ),
        ),
      ),
    );
    
    if (mockSvg) {
      app = SvgBuilderProvider(svgBuilder: testSvgBuilder, child: app);
    }
    
    // Wrap with SettingsProvider
    app = ChangeNotifierProvider<SettingsProvider>(
      create: (_) => SettingsProvider(),
      child: app,
    );
    
    return app;
  }

  /// Wrapper minimal pour tests simples
  static Widget wrapWithMaterialApp(Widget child, {Size? size}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size ?? defaultSize),
        child: Scaffold(body: child),
      ),
    );
  }
}

/// Extension pour simplifier les tests de widgets
extension WidgetTesterExtensions on WidgetTester {
  /// Pump un widget avec l'environnement de test complet (SVG mockés)
  Future<void> pumpTestApp(Widget widget, {Size? size, bool mockSvg = true}) async {
    await pumpWidget(
      WidgetTestHelpers.wrapWithTestApp(widget, size: size, mockSvg: mockSvg),
    );
  }

  /// Pump et attend que les animations se stabilisent
  Future<void> pumpTestAppAndSettle(Widget widget, {Size? size, bool mockSvg = true}) async {
    await pumpTestApp(widget, size: size, mockSvg: mockSvg);
    await pumpAndSettle();
  }
}
