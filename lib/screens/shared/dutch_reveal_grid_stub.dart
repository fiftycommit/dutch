import 'package:flutter/widgets.dart';

abstract class WebDutchRevealGrid {
  static WebDutchRevealGrid? create() => null;

  Widget build({
    required List<List<String?>> Function() rows,
    required String back,
    required Size size,
    required EdgeInsets padding,
    required double radius,
    required TextDirection direction,
  });

  Future<bool>? flip(int row, Duration duration, bool reducedMotion);
  void dispose();
}
