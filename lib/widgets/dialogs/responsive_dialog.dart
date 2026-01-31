import 'dart:math' as math;

import 'package:flutter/material.dart';

class DialogMetrics {
  final double maxWidth;
  final double maxHeight;
  final double contentWidth;
  final double contentHeight;
  final double scale;
  final EdgeInsets padding;

  DialogMetrics({
    required this.maxWidth,
    required this.maxHeight,
    required this.contentWidth,
    required this.contentHeight,
    required this.scale,
    required this.padding,
  });

  double space(double base) {
    return (base * scale).clamp(base * 0.6, base * 1.4);
  }

  double font(double base) {
    return (base * scale).clamp(base * 0.8, base * 1.3);
  }

  double size(double base) {
    return (base * scale).clamp(base * 0.7, base * 1.4);
  }
}

class ResponsiveDialog extends StatelessWidget {
  final Color backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsets? insetPadding;
  final Widget Function(BuildContext context, DialogMetrics metrics) builder;

  const ResponsiveDialog({
    super.key,
    required this.backgroundColor,
    required this.builder,
    this.shape,
    this.insetPadding,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final defaultInsets = EdgeInsets.symmetric(
      horizontal: screenSize.width * 0.08,
      vertical: screenSize.height * 0.06,
    );

    return Dialog(
      backgroundColor: backgroundColor,
      insetPadding: insetPadding ?? defaultInsets,
      shape: shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : screenSize.height * 0.85;
          final scale = math.min(maxWidth / 360.0, maxHeight / 640.0).clamp(0.75, 1.25);
          final paddingValue = (16.0 * scale).clamp(8.0, 20.0);
          final padding = EdgeInsets.all(paddingValue);
          final contentWidth =
              math.max(0.0, maxWidth - padding.horizontal);
          final contentHeight =
              math.max(0.0, maxHeight - padding.vertical);

          final metrics = DialogMetrics(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            scale: scale,
            padding: padding,
          );

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
            child: Padding(
              padding: padding,
              child: builder(context, metrics),
            ),
          );
        },
      ),
    );
  }
}
