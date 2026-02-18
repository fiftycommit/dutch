import '../../../models/player.dart';

Future<void> showBotSpyNotification(
  Object? context,
  Player bot,
  String targetName,
  int cardIndex,
) async {}

Future<void> showBotSwapNotification(
  Object? context,
  Player bot,
  String targetName,
  int targetCardIndex, {
  String? swapPartnerName,
  int? receivedCardPosition,
}) async {}

Future<void> showBotJokerNotification(
  Object? context,
  Player bot,
  String targetName,
) async {}
