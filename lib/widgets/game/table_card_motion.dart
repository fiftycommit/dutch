import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';

import 'table_card_motion_stub.dart'
    if (dart.library.js_interop) 'table_card_motion_web.dart' as platform;

// Les bounds du platform view couvrent aussi le halo et le mouvement.
const tableHandMotionPadding = 42.0;
const tableDrawnMotionPadding = 40.0;

typedef TableHandCard = ({
  String identity,
  bool hidden,
  String accent,
  int firstMove,
  int secondMove,
});

typedef TableHandStyle = ({
  String backAsset,
  double cardWidth,
  double overlap,
  double radius,
  int shuffle,
  int shuffleStartedAt,
  int shuffleMs,
  bool reduceMotion,
});

typedef TableDrawnStyle = ({
  String asset,
  String label,
  String score,
  double cardWidth,
  double cardHeight,
  double radius,
  double fontSize,
  double? lineHeight,
  double scoreSpacing,
  bool compact,
  bool expanded,
  double scale,
  double safeScale,
  int zoomMs,
  bool reduceMotion,
});

bool get browserTableCardMotionAvailable => platform.available;

class TableCardMotion extends StatefulWidget {
  final TableHandStyle? _hand;
  final List<TableHandCard>? _cards;
  final TableDrawnStyle? _drawn;

  const TableCardMotion.hand({
    super.key,
    required TableHandStyle style,
    required List<TableHandCard> cards,
  }) : _hand = style,
       _cards = cards,
       _drawn = null;

  const TableCardMotion.drawn({super.key, required TableDrawnStyle style})
    : _drawn = style,
      _hand = null,
      _cards = null;

  @override
  State<TableCardMotion> createState() => _TableCardMotionState();
}

class _TableCardMotionState extends State<TableCardMotion> {
  Object? _element;

  @override
  void didUpdateWidget(covariant TableCardMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._hand != oldWidget._hand ||
        widget._drawn != oldWidget._drawn ||
        !listEquals(widget._cards, oldWidget._cards)) {
      _sync(oldWidget._cards);
    }
  }

  void _sync(List<TableHandCard>? previousCards) {
    final element = _element;
    if (element == null) return;

    final hand = widget._hand;
    if (hand != null) {
      final cards = widget._cards!;
      platform.updateHand(element, jsonEncode({
        'backAsset': hand.backAsset,
        'width': hand.cardWidth,
        'padding': tableHandMotionPadding,
        'overlap': hand.overlap,
        'radius': hand.radius,
        'shuffle': hand.shuffle,
        'shuffleStartedAt': hand.shuffleStartedAt,
        'shuffleMs': hand.shuffleMs,
        'reduceMotion': hand.reduceMotion,
        'cards': [
          for (var i = 0; i < cards.length; i++)
            [
              previousCards != null &&
                  i < previousCards.length &&
                  previousCards[i].identity == cards[i].identity,
              cards[i].hidden,
              cards[i].accent,
              cards[i].firstMove,
              cards[i].secondMove,
            ],
        ],
      }));
      return;
    }

    final drawn = widget._drawn!;
    platform.updateDrawn(element, jsonEncode({
      'asset': drawn.asset,
      'label': drawn.label,
      'score': drawn.score,
      'width': drawn.cardWidth,
      'height': drawn.cardHeight,
      'radius': drawn.radius,
      'fontSize': drawn.fontSize,
      'lineHeight': drawn.lineHeight,
      'scoreSpacing': drawn.scoreSpacing,
      'compact': drawn.compact,
      'expanded': drawn.expanded,
      'scale': drawn.scale,
      'safeScale': drawn.safeScale,
      'padding': tableDrawnMotionPadding,
      'zoomMs': drawn.zoomMs,
      'reduceMotion': drawn.reduceMotion,
    }));
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onElementCreated: (element) {
        _element = element;
        _sync(null);
      },
    ),
  );
}
