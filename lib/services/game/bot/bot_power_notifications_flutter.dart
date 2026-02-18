import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/player.dart';
import '../../../providers/game_provider.dart';
import '../../../widgets/dialogs/shared/unified_power_dialogs.dart';

GameProvider? _readGameProvider(BuildContext context) {
  try {
    return Provider.of<GameProvider>(context, listen: false);
  } catch (_) {
    return null;
  }
}

Future<void> _runWithReactionPause(
  BuildContext context,
  Future<void> Function() action,
) async {
  final gameProvider = _readGameProvider(context);
  gameProvider?.pauseReactionTimerForNotification();
  try {
    await action();
  } finally {
    gameProvider?.resumeReactionTimerAfterNotification();
  }
}

Future<void> showBotSpyNotification(
  Object? context,
  Player bot,
  String targetName,
  int cardIndex,
) async {
  if (context is! BuildContext) return;
  await _runWithReactionPause(
    context,
    () => UnifiedPowerDialogs.showBotSpyNotification(
      context,
      bot,
      targetName,
      cardIndex,
    ),
  );
}

Future<void> showBotSwapNotification(
  Object? context,
  Player bot,
  String targetName,
  int targetCardIndex, {
  String? swapPartnerName,
  int? receivedCardPosition,
}) async {
  if (context is! BuildContext) return;
  await _runWithReactionPause(
    context,
    () => UnifiedPowerDialogs.showBotSwapNotification(
      context,
      bot,
      targetName,
      targetCardIndex,
      swapPartnerName: swapPartnerName,
      receivedCardPosition: receivedCardPosition,
    ),
  );
}

Future<void> showBotJokerNotification(
  Object? context,
  Player bot,
  String targetName,
) async {
  if (context is! BuildContext) return;
  await _runWithReactionPause(
    context,
    () => UnifiedPowerDialogs.showBotJokerNotification(
      context,
      bot,
      targetName,
    ),
  );
}
