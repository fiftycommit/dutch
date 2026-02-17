import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class _FallingCard {
  double x; // fraction of screen width (0..1)
  double y; // current Y position in pixels
  double speed; // pixels per second
  double rotation; // radians
  double size; // card height in pixels
  double opacity;
  String asset;

  _FallingCard({
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.size,
    required this.opacity,
    required this.asset,
  });
}

class CardRainBackground extends StatefulWidget {
  const CardRainBackground({super.key});

  @override
  State<CardRainBackground> createState() => _CardRainBackgroundState();
}

class _CardRainBackgroundState extends State<CardRainBackground>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  final List<_FallingCard> _cards = [];
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
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
    return _FallingCard(
      x: _random.nextDouble(),
      y: initialY ?? -(size + _random.nextDouble() * 200),
      speed: 35 + _random.nextDouble() * 40, // 35-75 px/s
      rotation: (_random.nextDouble() - 0.5) * 0.6, // -0.3..0.3 rad
      size: size,
      opacity: 0.06 + _random.nextDouble() * 0.09, // 0.06-0.15
      asset: _cardAssets[_random.nextInt(_cardAssets.length)],
    );
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    if (dt <= 0 || dt > 0.5) return; // skip huge jumps (e.g. tab switch)

    final size = MediaQuery.of(context).size;
    if (!_initialized) {
      _initCards(size);
    }

    bool needsRebuild = false;
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      card.y += card.speed * dt;

      if (card.y > size.height + card.size) {
        _cards[i] = _randomCard(size);
        needsRebuild = true;
      }
    }

    if (needsRebuild || dt > 0) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) return const SizedBox.expand();

    final screenWidth = MediaQuery.of(context).size.width;

    return IgnorePointer(
      child: Stack(
        children: _cards.map((card) {
          final cardWidth = card.size * 0.7; // aspect ratio ~0.7
          return Positioned(
            left: card.x * (screenWidth - cardWidth),
            top: card.y,
            child: Opacity(
              opacity: card.opacity,
              child: Transform.rotate(
                angle: card.rotation,
                child: SvgPicture.asset(
                  card.asset,
                  height: card.size,
                  width: cardWidth,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
