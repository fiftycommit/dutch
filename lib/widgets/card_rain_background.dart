import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'card_rain_batch.dart';
import 'card_rain_view_stub.dart'
    if (dart.library.js_interop) 'card_rain_view_web.dart';

/// Liste des assets de cartes SVG utilisables pour la pluie
const _cardAssets = [
  'assets/images/cards/01-coeur.svg',
  'assets/images/cards/01-pique.svg',
  'assets/images/cards/02-carreau.svg',
  'assets/images/cards/03-trefle.svg',
  'assets/images/cards/04-coeur.svg',
  'assets/images/cards/05-pique.svg',
  'assets/images/cards/06-carreau.svg',
  'assets/images/cards/07-trefle.svg',
  'assets/images/cards/08-coeur.svg',
  'assets/images/cards/09-pique.svg',
  'assets/images/cards/10-carreau.svg',
  'assets/images/cards/D-coeur.svg',
  'assets/images/cards/R-pique.svg',
  'assets/images/cards/V-trefle.svg',
  'assets/images/cards/joker-rouge.svg',
];

const _cardCount = 12;
const _aspectRatio = 0.7; // card width / height

class _FallingCard {
  double x; // X position in pixels
  double y; // Y position in pixels
  double vx; // horizontal velocity (px/s)
  double vy; // vertical velocity (px/s)
  double rotation; // radians
  double rotationSpeed; // radians per second
  double size; // card height in pixels
  double opacity;
  String asset;
  bool
      ignoresObstacles; // true = passes through buttons, only card-card collisions

  double get width => size * _aspectRatio;

  _FallingCard({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.opacity,
    required this.asset,
    this.ignoresObstacles = false,
  });

  // The SVG and its opacity do not change while this card is falling.
  // Reuse the subtree rather than rebuilding it on every tick.
  late final Widget visual = RepaintBoundary(
    child: Opacity(
      opacity: opacity,
      child: SvgPicture.asset(
        asset,
        height: size,
        width: width,
        fit: BoxFit.contain,
      ),
    ),
  );
}

/// Notifier léger qui évite de reconstruire tout le widget tree parent
class _CardRainNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class CardRainBackground extends StatefulWidget {
  /// GlobalKeys of UI elements that act as obstacles for bouncing cards
  final List<GlobalKey> obstacleKeys;

  const CardRainBackground({super.key, this.obstacleKeys = const []});

  @override
  State<CardRainBackground> createState() => _CardRainBackgroundState();
}

class _CardRainBackgroundState extends State<CardRainBackground>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  final List<_FallingCard> _cards = [];
  late final bool _usesWebView = webCardRainAvailable;
  Ticker? _ticker;
  bool _motionDisabled = false;
  Duration _lastTick = Duration.zero;
  bool _initialized = false;
  final _obstacleRects = <Rect>[];
  int _frameCount = 0;

  static const _stepsPerWebBatch = 60;
  static const _stepsPerWebSample = 3;
  late final _webCards = _cards.toList(growable: false);
  late final _webFrames = Float64List(
    (_stepsPerWebBatch ~/ _stepsPerWebSample + 1) * _cardCount * 3,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    if (_usesWebView) return;

    if (_motionDisabled) {
      _ticker?.stop();
      _lastTick = Duration.zero;
    } else {
      final ticker = _ticker ??= createTicker(_onTick);
      if (!ticker.isActive) ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _initCards(Size screenSize) {
    _cards.clear();
    for (int i = 0; i < _cardCount; i++) {
      _cards.add(_randomCard(
        screenSize,
        initialY: _random.nextDouble() * (screenSize.height + 100) - 100,
      ));
    }
    _initialized = true;
  }

  _FallingCard _randomCard(Size screenSize, {double? initialY}) {
    final size = 40.0 + _random.nextDouble() * 40; // 40-80px height
    final cardWidth = size * _aspectRatio;
    return _FallingCard(
      x: _random.nextDouble() * (screenSize.width - cardWidth),
      y: initialY ?? -(size + _random.nextDouble() * 200),
      vx: (_random.nextDouble() - 0.5) * 20, // -10..10 px/s lateral drift
      vy: 35 + _random.nextDouble() * 40, // 35-75 px/s downward
      rotation: (_random.nextDouble() - 0.5) * 0.6, // -0.3..0.3 rad
      rotationSpeed: (_random.nextDouble() - 0.5) * 0.3, // slow spin
      size: size,
      opacity: 0.06 + _random.nextDouble() * 0.09, // 0.06-0.15
      asset: _cardAssets[_random.nextInt(_cardAssets.length)],
      ignoresObstacles: _random.nextDouble() < 0.4, // ~40% pass through buttons
    );
  }

  void _updateObstacleRects() {
    if (widget.obstacleKeys.isEmpty) {
      _obstacleRects.clear();
      return;
    }
    final myRenderBox = context.findRenderObject();
    if (myRenderBox is! RenderBox || !myRenderBox.hasSize) return;

    _obstacleRects.clear();
    for (final key in widget.obstacleKeys) {
      final renderObj = key.currentContext?.findRenderObject();
      if (renderObj is RenderBox && renderObj.hasSize) {
        final position = myRenderBox.globalToLocal(
          renderObj.localToGlobal(Offset.zero),
        );
        _obstacleRects.add(position & renderObj.size);
      }
    }
  }

  void _resolveCardCollisions() {
    for (int i = 0; i < _cards.length; i++) {
      final a = _cards[i];
      for (int j = i + 1; j < _cards.length; j++) {
        final b = _cards[j];

        final aCx = a.x + a.width / 2;
        final aCy = a.y + a.size / 2;
        final bCx = b.x + b.width / 2;
        final bCy = b.y + b.size / 2;

        final dx = bCx - aCx;
        final dy = bCy - aCy;

        final overlapX = (a.width + b.width) / 2;
        final overlapY = (a.size + b.size) / 2;

        if (dx.abs() < overlapX && dy.abs() < overlapY) {
          final penX = overlapX - dx.abs();
          final penY = overlapY - dy.abs();

          // Separate cards
          if (penX < penY) {
            final sign = dx > 0 ? 1.0 : -1.0;
            a.x -= sign * penX / 2;
            b.x += sign * penX / 2;
          } else {
            final sign = dy > 0 ? 1.0 : -1.0;
            a.y -= sign * penY / 2;
            b.y += sign * penY / 2;
          }

          // Give each card a completely new random direction to break loops
          final angleA = _random.nextDouble() * 3.14159 * 2;
          final angleB = _random.nextDouble() * 3.14159 * 2;
          final speedA = 30 + _random.nextDouble() * 40;
          final speedB = 30 + _random.nextDouble() * 40;

          a.vx = speedA * (angleA < 3.14159 ? 1 : -1) * _random.nextDouble();
          a.vy = 25 + _random.nextDouble() * 50;
          b.vx = speedB * (angleB < 3.14159 ? 1 : -1) * _random.nextDouble();
          b.vy = 25 + _random.nextDouble() * 50;

          // Ensure they move apart on the collision axis
          if (penX < penY) {
            final sign = dx > 0 ? 1.0 : -1.0;
            a.vx = -sign * speedA * (0.5 + _random.nextDouble() * 0.5);
            b.vx = sign * speedB * (0.5 + _random.nextDouble() * 0.5);
          } else {
            if (dy > 0) {
              a.vy = -(20 + _random.nextDouble() * 30);
              b.vy = 35 + _random.nextDouble() * 40;
            } else {
              a.vy = 35 + _random.nextDouble() * 40;
              b.vy = -(20 + _random.nextDouble() * 30);
            }
          }

          a.rotationSpeed =
              -a.rotationSpeed * 0.8 + (_random.nextDouble() - 0.5) * 3.0;
          b.rotationSpeed =
              -b.rotationSpeed * 0.8 + (_random.nextDouble() - 0.5) * 3.0;
        }
      }
    }
  }

  void _resolveObstacleCollisions() {
    if (_obstacleRects.isEmpty) return;
    for (final card in _cards) {
      if (card.ignoresObstacles) continue;
      final cardWidth = card.width;
      final left = card.x;
      final top = card.y;
      final right = left + cardWidth;
      final bottom = top + card.size;
      final centerX = left + cardWidth / 2;
      final centerY = top + card.size / 2;
      for (final obstacle in _obstacleRects) {
        if (right <= obstacle.left ||
            left >= obstacle.right ||
            bottom <= obstacle.top ||
            top >= obstacle.bottom) {
          continue;
        }

        final dx = centerX - (obstacle.left + obstacle.width / 2);
        final dy = centerY - (obstacle.top + obstacle.height / 2);
        final penX = (cardWidth + obstacle.width) / 2 - dx.abs();
        final penY = (card.size + obstacle.height) / 2 - dy.abs();
        if (penX <= 0 || penY <= 0) continue;

        if (penX < penY) {
          // Push out horizontally
          if (dx > 0) {
            card.x += penX;
          } else {
            card.x -= penX;
          }
          // Strong horizontal bounce + kick
          card.vx = (dx > 0 ? 1 : -1) * (card.vx.abs() * 1.2 + 30);
          card.rotationSpeed += (_random.nextDouble() - 0.5) * 4.0;
        } else {
          // Push out vertically
          if (dy > 0) {
            card.y += penY;
          } else {
            card.y -= penY;
          }
          // Strong vertical bounce (full reversal + boost)
          card.vy = -card.vy.abs() * 1.1 - 20;
          // Scatter horizontally on impact
          card.vx += (_random.nextDouble() - 0.5) * 50;
          card.rotationSpeed += (_random.nextDouble() - 0.5) * 4.0;
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    if (dt <= 0 || dt > 0.5) return;

    final size = MediaQuery.of(context).size;
    if (!_initialized) {
      _initCards(size);
    }

    if (++_frameCount % 10 == 0 || _obstacleRects.isEmpty) {
      _updateObstacleRects();
    }
    _advanceCards(size, dt);
    _notifier.notify();
  }

  bool _advanceCards(Size size, double dt) {
    var replaced = false;

    // Move cards
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      card.x += card.vx * dt;
      card.y += card.vy * dt;
      card.rotation += card.rotationSpeed * dt;

      // Dampen horizontal velocity and spin over time
      card.vx *= 0.998;
      card.rotationSpeed *= 0.995;

      // After a bounce, smoothly restore original fall speed (no gravity feel)
      final baseVy = 35 + (card.size - 40) / 40 * 40; // approximate original vy
      if (card.vy < baseVy) {
        card.vy +=
            (baseVy - card.vy) * 0.8 * dt; // gentle convergence, not gravity
      }

      // Replace cards that exit any screen edge
      if (card.x + card.width < 0 ||
          card.x > size.width ||
          card.y > size.height + card.size) {
        _cards[i] = _randomCard(size);
        replaced = true;
      }
    }

    // Resolve collisions
    _resolveCardCollisions();
    _resolveObstacleCollisions();

    return replaced;
  }

  CardRainBatch _nextWebBatch(double width, double height) {
    const stepsPerBatch = _stepsPerWebBatch;
    const sampleEvery = _stepsPerWebSample;
    const stepSeconds = 1 / 60;
    const stepMilliseconds = stepSeconds * 1000;
    final size = Size(width, height);
    if (!_initialized) _initCards(size);
    _updateObstacleRects();

    // Keep the old card through its exit frame before swapping in its replacement.
    _webCards.setAll(0, _cards);
    var frameCount = 1;
    var step = 0;
    _recordWebFrame(0);
    while (step < stepsPerBatch) {
      step++;
      final replaced = _advanceCards(size, stepSeconds);
      if (replaced || step % sampleEvery == 0) {
        _recordWebFrame(frameCount++);
      }
      if (replaced) break;
    }

    return (
      duration: step * stepMilliseconds,
      sampleInterval: sampleEvery * stepMilliseconds,
      frameCount: frameCount,
      tracks: [
        for (final card in _webCards)
          (
            asset: card.asset,
            width: card.width,
            height: card.size,
            opacity: card.opacity,
          ),
      ],
      frames: _webFrames,
    );
  }

  void _recordWebFrame(int frame) {
    var offset = frame * _cardCount * 3;
    for (final card in _webCards) {
      _webFrames[offset++] = card.x;
      _webFrames[offset++] = card.y;
      _webFrames[offset++] = card.rotation;
    }
  }

  // Notifier léger pour éviter setState à chaque frame
  final _CardRainNotifier _notifier = _CardRainNotifier();

  @override
  Widget build(BuildContext context) {
    if (_motionDisabled) return const SizedBox.expand();
    if (_usesWebView) {
      return buildWebCardRain(
        active: TickerMode.of(context),
        nextBatch: _nextWebBatch,
      );
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: ListenableBuilder(
          listenable: _notifier,
          builder: (context, _) {
            if (_cards.isEmpty) {
              return const SizedBox.expand();
            }

            return Stack(
              children: _cards.map((card) {
                return Positioned(
                  left: card.x,
                  top: card.y,
                  child: Transform.rotate(
                    angle: card.rotation,
                    child: card.visual,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
