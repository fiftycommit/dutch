import 'dart:js_interop';

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';

import 'card_rain_batch.dart';

@JS('dutchCardRain')
external JSObject? get _bridge;

bool get webCardRainAvailable => _bridge != null;

@JS('dutchCardRain.mount')
external _Controller _mount(JSObject host, JSFunction nextBatch, bool active);

extension type _Controller._(JSObject _) implements JSObject {
  external void setActive(bool active);
  external void dispose();
}

extension type _Track._(JSObject _) implements JSObject {
  external _Track({
    required JSString asset,
    required double width,
    required double height,
    required double opacity,
  });
}

extension type _Batch._(JSObject _) implements JSObject {
  external _Batch({
    required double duration,
    required double sampleInterval,
    required int frameCount,
    required JSArray<_Track> tracks,
    required JSFloat64Array frames,
  });
}

Widget buildWebCardRain({
  required bool active,
  required NextCardRainBatch nextBatch,
}) =>
    _WebCardRain(active: active, nextBatch: nextBatch);

class _WebCardRain extends StatefulWidget {
  const _WebCardRain({required this.active, required this.nextBatch});

  final bool active;
  final NextCardRainBatch nextBatch;

  @override
  State<_WebCardRain> createState() => _WebCardRainState();
}

class _WebCardRainState extends State<_WebCardRain> {
  _Controller? _controller;

  void _onElementCreated(Object element) {
    if (!mounted) return;
    _controller = _mount(element as JSObject, _nextBatch.toJS, widget.active);
  }

  _Batch _nextBatch(JSNumber width, JSNumber height) {
    final batch = widget.nextBatch(width.toDartDouble, height.toDartDouble);
    return _Batch(
      duration: batch.duration,
      sampleInterval: batch.sampleInterval,
      frameCount: batch.frameCount,
      frames: batch.frames.toJS,
      tracks: [
        for (final track in batch.tracks)
          _Track(
            asset: track.asset.toJS,
            width: track.width,
            height: track.height,
            opacity: track.opacity,
          ),
      ].toJS,
    );
  }

  @override
  void didUpdateWidget(_WebCardRain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _controller?.setActive(widget.active);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _onElementCreated,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}
