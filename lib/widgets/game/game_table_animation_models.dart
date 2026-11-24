import 'package:flutter/material.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';

class PenaltyAnimation {
  final int id;
  final String playerId;
  final int hiddenIndex;
  final Offset start;
  final Offset end;
  final CardSize size;

  PenaltyAnimation({
    required this.id,
    required this.playerId,
    required this.hiddenIndex,
    required this.start,
    required this.end,
    required this.size,
  });
}

class DiscardAnimation {
  final int id;
  final PlayingCard card;
  final Offset start;
  final Offset end;
  final CardSize size;

  DiscardAnimation({
    required this.id,
    required this.card,
    required this.start,
    required this.end,
    required this.size,
  });
}

class DrawnToHandAnimation {
  final int id;
  final String playerId;
  final int hiddenIndex;
  final PlayingCard card;
  final Offset start;
  final Offset end;
  final CardSize size;

  DrawnToHandAnimation({
    required this.id,
    required this.playerId,
    required this.hiddenIndex,
    required this.card,
    required this.start,
    required this.end,
    required this.size,
  });
}

class ValetSwapAnimation {
  final int id;
  final String playerId;
  final String cardId;
  final Offset start;
  final Offset end;
  final CardSize size;

  ValetSwapAnimation({
    required this.id,
    required this.playerId,
    required this.cardId,
    required this.start,
    required this.end,
    required this.size,
  });
}
