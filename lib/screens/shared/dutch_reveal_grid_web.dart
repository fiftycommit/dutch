import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('dutchRoundReveal')
external JSFunction? get _createGrid;

@JS('dutchRoundReveal')
external _BrowserGrid _create(
  web.HTMLElement host,
  JSArray<JSArray<JSString?>> rows,
  JSString back,
);

extension type _BrowserGrid(JSObject _) implements JSObject {
  external JSPromise<JSBoolean>? flip(int row, int duration, bool reducedMotion);
  external void dispose();
}

class WebDutchRevealGrid {
  static WebDutchRevealGrid? create() =>
      _createGrid == null ? null : WebDutchRevealGrid._();

  WebDutchRevealGrid._();

  bool _disposed = false;
  web.HTMLElement? _host;
  _BrowserGrid? _grid;
  Size? _size;
  EdgeInsets? _padding;
  double? _radius;
  TextDirection? _direction;

  Widget build({
    required List<List<String?>> Function() rows,
    required String back,
    required Size size,
    required EdgeInsets padding,
    required double radius,
    required TextDirection direction,
  }) {
    if (_size != size ||
        _padding != padding ||
        _radius != radius ||
        _direction != direction) {
      _size = size;
      _padding = padding;
      _radius = radius;
      _direction = direction;
      final host = _host;
      if (host != null) _layout(host);
    }
    return HtmlElementView.fromTagName(
      tagName: 'div',
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onElementCreated: (element) {
        if (_disposed) return;
        _grid?.dispose();
        final host = element as web.HTMLElement;
        final assets = ui_web.assetManager;
        _host = host;
        _layout(host);
        _grid = _create(
          host,
          [
            for (final row in rows())
              [
                for (final face in row)
                  if (face == null) null else assets.getAssetUrl(face).toJS,
              ].toJS,
          ].toJS,
          assets.getAssetUrl(back).toJS,
        );
      },
    );
  }

  void _layout(web.HTMLElement host) {
    host.dir = _direction!.name;
    host.style
      ..setProperty('--dutch-round-card-width', '${_size!.width}px')
      ..setProperty('--dutch-round-card-height', '${_size!.height}px')
      ..setProperty('--dutch-round-padding-x', '${_padding!.left}px')
      ..setProperty('--dutch-round-padding-y', '${_padding!.top}px')
      ..setProperty('--dutch-round-card-radius', '${_radius}px');
  }

  Future<bool>? flip(int row, Duration duration, bool reducedMotion) {
    final result = _grid?.flip(row, duration.inMilliseconds, reducedMotion);
    return result?.toDart.then((success) => success.toDart);
  }

  void dispose() {
    _disposed = true;
    _grid?.dispose();
    _grid = null;
    _host = null;
  }
}
