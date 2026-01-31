import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Builder function for SVG images - allows injection for testing
typedef SvgBuilder = Widget Function(String assetPath, double width, double height);

/// Default SVG builder using flutter_svg
Widget defaultSvgBuilder(String assetPath, double width, double height) {
  return SvgPicture.asset(
    assetPath,
    width: width,
    height: height,
    fit: BoxFit.contain,
  );
}

/// InheritedWidget to propagate SvgBuilder through the widget tree
/// Usage in tests: wrap your widget with SvgBuilderProvider(svgBuilder: testSvgBuilder, child: ...)
class SvgBuilderProvider extends InheritedWidget {
  final SvgBuilder svgBuilder;

  const SvgBuilderProvider({
    super.key,
    required this.svgBuilder,
    required super.child,
  });

  static SvgBuilder of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SvgBuilderProvider>();
    return provider?.svgBuilder ?? defaultSvgBuilder;
  }

  /// Get SvgBuilder without registering dependency (for performance in build methods)
  static SvgBuilder maybeOf(BuildContext context) {
    final provider = context.getInheritedWidgetOfExactType<SvgBuilderProvider>();
    return provider?.svgBuilder ?? defaultSvgBuilder;
  }

  @override
  bool updateShouldNotify(SvgBuilderProvider oldWidget) {
    return svgBuilder != oldWidget.svgBuilder;
  }
}
