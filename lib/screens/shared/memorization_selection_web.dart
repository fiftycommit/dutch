import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' show Shadow;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../utils/screen_utils.dart';
import '../../widgets/game/card_widget.dart';

Widget buildWebMemorizationSelection({
  required Size cardSize,
  required double maxWidth,
  required double spacing,
  required double liftFactor,
  required double maxScale,
  required bool compact,
  required bool pulseEnabled,
  required int cardCount,
  required Set<int> selected,
  required ValueChanged<int> onTap,
}) =>
    _WebMemorizationSelection(
      cardSize: cardSize,
      maxWidth: maxWidth,
      spacing: spacing,
      liftFactor: liftFactor,
      maxScale: maxScale,
      compact: compact,
      pulseEnabled: pulseEnabled,
      cardCount: cardCount,
      selected: selected,
      onTap: onTap,
    );

class _WebMemorizationSelection extends StatefulWidget {
  const _WebMemorizationSelection({
    required this.cardSize,
    required this.maxWidth,
    required this.spacing,
    required this.liftFactor,
    required this.maxScale,
    required this.compact,
    required this.pulseEnabled,
    required this.cardCount,
    required this.selected,
    required this.onTap,
  });

  final Size cardSize;
  final double maxWidth;
  final double spacing;
  final double liftFactor;
  final double maxScale;
  final bool compact;
  final bool pulseEnabled;
  final int cardCount;
  final Set<int> selected;
  final ValueChanged<int> onTap;

  @override
  State<_WebMemorizationSelection> createState() =>
      _WebMemorizationSelectionState();
}

class _WebMemorizationSelectionState extends State<_WebMemorizationSelection> {
  final _reducedMotion = web.window.matchMedia('(prefers-reduced-motion: reduce)');
  final _cards = <_BrowserCard>[];
  late final JSFunction _motionChanged = ((web.Event _) => _sync()).toJS;
  late final _hitCard = _containsCard;
  web.HTMLDivElement? _host;
  JSAny? _pulseStart;
  late bool _flutterReducedMotion;
  late bool _rtl;
  late double _borderRadius;
  late double _imageRadius;
  late double _imageScale;
  late Rect _hitRect;

  @override
  void initState() {
    super.initState();
    _reducedMotion.addEventListener('change', _motionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flutterReducedMotion = MediaQuery.disableAnimationsOf(context);
    _rtl = Directionality.of(context) == TextDirection.rtl;
    _borderRadius = ScreenUtils.borderRadius(context, 8);
    _updateCardGeometry();
    _sync(reposition: true);
  }

  @override
  void didUpdateWidget(covariant _WebMemorizationSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final geometryChanged = widget.cardSize != oldWidget.cardSize ||
        widget.maxWidth != oldWidget.maxWidth ||
        widget.spacing != oldWidget.spacing ||
        widget.compact != oldWidget.compact ||
        widget.cardCount != oldWidget.cardCount;
    if (geometryChanged) _updateCardGeometry();
    _sync(reposition: geometryChanged);
  }

  // Keep the same wrapping limit and centered runs as the Flutter Wrap.
  int get _columns =>
      ((widget.maxWidth + widget.spacing + precisionErrorTolerance) /
              (widget.cardSize.width + widget.spacing))
          .floor()
          .clamp(1, widget.cardCount);

  double _runWidth(int count) =>
      count * widget.cardSize.width + (count - 1) * widget.spacing;

  Rect _slot(int index, int columns) {
    final row = index ~/ columns;
    final runLength = math.min(columns, widget.cardCount - row * columns);
    final column = _rtl ? runLength - 1 - index % columns : index % columns;
    return Rect.fromLTWH(
      (_runWidth(columns) - _runWidth(runLength)) / 2 +
          column * (widget.cardSize.width + widget.spacing),
      row * (widget.cardSize.height + widget.spacing),
      widget.cardSize.width,
      widget.cardSize.height,
    );
  }

  // Reserve real platform-view bounds for the glow and the lifted card.
  double get _overscan => widget.cardSize.height *
      (widget.liftFactor * widget.maxScale + (widget.maxScale - 1) / 2) + 40;

  void _updateCardGeometry() {
    _imageScale = widget.cardSize.width /
        CardWidget.visualSize(context, CardSize.large).width;
    _imageRadius = ScreenUtils.borderRadius(context, 4) * _imageScale;
    _hitRect = Offset.zero & widget.cardSize;
  }

  void _positionCards() {
    if (_cards.isEmpty) return;
    final columns = _columns;
    final overscan = _overscan;
    for (var index = 0; index < _cards.length; index++) {
      _cards[index].position(
        _slot(index, columns).shift(Offset(overscan, overscan)),
        borderRadius: _borderRadius,
        imageRadius: _imageRadius,
        imageScale: _imageScale,
        compact: widget.compact,
      );
    }
  }

  void _onElementCreated(Object element) {
    if (!mounted) return;
    _host = element as web.HTMLDivElement
      ..className = 'dutch-memorization-selection'
      ..setAttribute('aria-hidden', 'true');
    _sync();
  }

  void _sync({bool reposition = false}) {
    final reduced = _flutterReducedMotion || _reducedMotion.matches;
    if (reduced || !widget.pulseEnabled || widget.selected.isEmpty) {
      _pulseStart = null;
    } else {
      _pulseStart ??= web.document.timeline.currentTime ??
          web.window.performance.now().toJS;
    }

    final host = _host;
    if (host == null) return;
    final countChanged = _cards.length != widget.cardCount;
    while (_cards.length > widget.cardCount) {
      _cards.removeLast().dispose();
    }
    for (var index = 0; index < _cards.length; index++) {
      _cards[index].update(
        widget.selected.contains(index),
        reduced,
        _pulseStart,
      );
    }
    while (_cards.length < widget.cardCount) {
      final card = _BrowserCard(
        liftFactor: widget.liftFactor,
        maxScale: widget.maxScale,
      );
      card.update(widget.selected.contains(_cards.length), true, _pulseStart);
      _cards.add(card);
      host.appendChild(card.element);
    }
    if (reposition || countChanged) _positionCards();
  }

  bool _containsCard(int index, Offset point) {
    if (index >= _cards.length) return _hitRect.contains(point);
    final card = _cards[index];
    final center = _hitRect.center;
    // Invert the two browser transforms at hit-test time, not on animation ticks.
    final unscaled = center + (point - center) / card.pulseScale;
    return _hitRect.contains(
      unscaled.translate(
        0,
        widget.cardSize.height * widget.liftFactor * card.lift,
      ),
    );
  }

  @override
  void dispose() {
    _reducedMotion.removeEventListener('change', _motionChanged);
    for (final card in _cards) {
      card.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final rows = (widget.cardCount + columns - 1) ~/ columns;
    final overscan = _overscan;
    return SizedBox(
      width: _runWidth(columns),
      height: rows * widget.cardSize.height + (rows - 1) * widget.spacing,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -overscan,
            top: -overscan,
            right: -overscan,
            bottom: -overscan,
            child: HtmlElementView.fromTagName(
              tagName: 'div',
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              onElementCreated: _onElementCreated,
            ),
          ),
          for (var index = 0; index < widget.cardCount; index++)
            Positioned.fromRect(
              rect: _slot(index, columns),
              child: Semantics(
                label: 'Carte à mémoriser ${index + 1}',
                button: true,
                selected: widget.selected.contains(index),
                child: GestureDetector(
                  onTap: () => widget.onTap(index),
                  child: _BrowserCardHitRegion(index: index, contains: _hitCard),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

@JS()
extension type _TransformKeyframe._(JSObject _) implements JSObject {
  external factory _TransformKeyframe({required String transform});
}

class _BrowserCard {
  _BrowserCard({required this.liftFactor, required this.maxScale}) {
    element.className = 'dutch-memorization-card';
    _lift.className = 'dutch-memorization-lift';
    final face = web.HTMLDivElement()..className = 'dutch-memorization-back';
    face.appendChild(web.HTMLImageElement()
      ..alt = ''
      ..draggable = false
      ..src = 'assets/${CardWidget.backAsset}');
    _lift.appendChild(face);
    element.appendChild(_lift);
  }

  static const _liftDuration = 180;
  static const _pulseDuration = 900;

  final double liftFactor;
  final double maxScale;
  final element = web.HTMLDivElement();
  final _lift = web.HTMLDivElement();
  web.Animation? _liftAnimation;
  web.Animation? _pulseAnimation;
  double _from = 0;
  double _target = 0;

  double get lift {
    final animation = _liftAnimation;
    if (animation == null) return _target;
    final time = (animation.currentTime as JSNumber?)?.toDartDouble ?? 0;
    final progress = Curves.easeOut.transform((time / _liftDuration).clamp(0, 1));
    return _from + (_target - _from) * progress;
  }

  double get pulseScale {
    final time = (_pulseAnimation?.currentTime as JSNumber?)?.toDartDouble ?? 0;
    final phase = time / _pulseDuration % 2;
    return 1 + (phase <= 1 ? phase : 2 - phase) * (maxScale - 1);
  }

  void position(
    Rect rect, {
    required double borderRadius,
    required double imageRadius,
    required double imageScale,
    required bool compact,
  }) {
    element.style
      ..left = '${rect.left}px'
      ..top = '${rect.top}px'
      ..width = '${rect.width}px'
      ..height = '${rect.height}px'
      ..setProperty('--selection-radius', '${borderRadius}px')
      ..setProperty('--selection-image-radius', '${imageRadius}px')
      ..setProperty('--selection-shadow-offset', '${2 * imageScale}px')
      ..setProperty('--selection-shadow-blur', '${_cssBlur(4) * imageScale}px')
      ..setProperty('--selection-border', compact ? '2px' : '3px')
      ..setProperty(
        '--selection-glow-blur',
        '${_cssBlur(compact ? 10 : 15)}px',
      );
  }

  // CSS blur radii are twice the standard deviation of the shadow.
  static double _cssBlur(double radius) => 2 * Shadow.convertRadiusToSigma(radius);

  String _translation(double lift) => 'translateY(${-100 * liftFactor * lift}%)';

  void update(bool selected, bool reduced, JSAny? pulseStart) {
    final target = selected ? 1.0 : 0.0;
    if (target != _target || (reduced && _liftAnimation != null)) {
      _from = lift;
      _target = target;
      _liftAnimation?.cancel();
      _lift.style.transform = _translation(target);
      _lift.classList.toggle('dutch-memorization-selected', selected);
      _liftAnimation = reduced || _from == target
          ? null
          : _lift.animate(
              [
                _TransformKeyframe(transform: _translation(_from)),
                _TransformKeyframe(transform: _translation(target)),
              ].toJS,
              web.KeyframeAnimationOptions(
                duration: _liftDuration.toJS,
                easing: 'cubic-bezier(0, 0, .58, 1)',
                fill: 'backwards',
              ),
            );
    }
    if (!selected || pulseStart == null) {
      _pulseAnimation?.cancel();
      _pulseAnimation = null;
    } else if (_pulseAnimation == null) {
      _pulseAnimation = element.animate(
        [
          _TransformKeyframe(transform: 'scale(1)'),
          _TransformKeyframe(transform: 'scale($maxScale)'),
        ].toJS,
        web.KeyframeAnimationOptions(
          duration: _pulseDuration.toJS,
          direction: 'alternate',
          iterations: double.infinity,
        ),
      )..startTime = pulseStart;
    }
  }

  void dispose() {
    _liftAnimation?.cancel();
    _pulseAnimation?.cancel();
    element.remove();
  }
}

class _BrowserCardHitRegion extends LeafRenderObjectWidget {
  const _BrowserCardHitRegion({required this.index, required this.contains});

  final int index;
  final bool Function(int, Offset) contains;

  @override
  _RenderBrowserCardHitRegion createRenderObject(BuildContext context) =>
      _RenderBrowserCardHitRegion(index, contains);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBrowserCardHitRegion renderObject,
  ) {
    renderObject
      ..index = index
      ..contains = contains;
  }
}

class _RenderBrowserCardHitRegion extends RenderBox {
  _RenderBrowserCardHitRegion(this.index, this.contains);

  int index;
  bool Function(int, Offset) contains;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => contains(index, position);
}
