import 'dart:js_interop';

@JS('dutchCardReveal')
external JSObject? get _bridge;

@JS('dutchCardReveal.fly')
external JSFunction? get _flight;

bool get webFlightAvailable => _bridge != null && _flight != null;

@JS('dutchCardReveal.fly')
external JSFunction _fly(JSString asset, double x, double y, double dx,
    double dy, double width, double height, int milliseconds,
    bool easeInOut, JSFunction done);

void Function() startWebFlight(
  String asset, double x, double y, double dx, double dy, double width,
  double height, int milliseconds, bool easeInOut, void Function(bool) onDone,
) {
  final cancel = _fly(asset.toJS, x, y, dx, dy, width, height, milliseconds, easeInOut,
      ((JSBoolean success) => onDone(success.toDart)).toJS);
  return () => cancel.callAsFunction();
}
