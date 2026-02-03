import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dutch_game/core/interfaces/i_game_controller.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/utils/screen_utils.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:dutch_game/widgets/game/game_layout_mixin.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/widgets/game/player_hand.dart';
import 'package:dutch_game/widgets/game/animated_card_transition.dart';
import 'package:dutch_game/widgets/game/center_table.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Configuration pour les callbacks d'actions de jeu
class GameTableCallbacks {
  final VoidCallback onDrawCard;
  final VoidCallback onDiscardDrawnCard;
  final VoidCallback onCallDutch;
  final VoidCallback? onTakeFromDiscard;
  final ValueChanged<int> onCardTap;
  final void Function(int opponentIndex, int cardIndex)? onOpponentCardTap;
  final VoidCallback onShowDiscardPile;

  const GameTableCallbacks({
    required this.onDrawCard,
    required this.onDiscardDrawnCard,
    required this.onCallDutch,
    this.onTakeFromDiscard,
    required this.onCardTap,
    this.onOpponentCardTap,
    required this.onShowDiscardPile,
  });

  /// Factory pour créer des callbacks à partir d'un IGameController
  /// Réduit le couplage entre l'UI et les providers concrets
  /// Auto-wire onShowDiscardPile et onCardTap depuis le controller
  factory GameTableCallbacks.fromController({
    required BuildContext context,
    required IGameController controller,
    void Function(int opponentIndex, int cardIndex)? onOpponentCardTap,
    bool supportsTakeFromDiscard = true,
  }) {
    return GameTableCallbacks(
      onDrawCard: controller.drawCard,
      onTakeFromDiscard: supportsTakeFromDiscard ? controller.takeFromDiscard : null,
      onDiscardDrawnCard: controller.discardDrawnCard,
      onCallDutch: controller.callDutch,
      onCardTap: controller.handleCardTap,
      onOpponentCardTap: onOpponentCardTap,
      onShowDiscardPile: () {
        final gs = controller.gameState;
        if (gs == null || gs.discardPile.isEmpty) return;
        GameDialogs.showDiscardPile(context, gs);
      },
    );
  }
}

/// Configuration optionnelle pour le mode multiplayer
class MultiplayerConfig {
  final String? playerId;
  final Map<String, bool> playerConnections;
  final Map<String, bool> playerAfkStatus;
  final int? turnStartTime;
  final int? turnDuration;
  final int reactionTimeTotalMs;

  const MultiplayerConfig({
    this.playerId,
    this.playerConnections = const {},
    this.playerAfkStatus = const {},
    this.turnStartTime,
    this.turnDuration,
    this.reactionTimeTotalMs = 0,
  });

  static const solo = MultiplayerConfig();
}

/// Widget principal de la table de jeu - partagé entre solo et multiplayer
class GameTableWidget extends StatelessWidget {
  final GameState gameState;
  final GameTableCallbacks callbacks;
  final MultiplayerConfig multiplayerConfig;
  final List<int> shakingCardIndices;
  final bool isProcessing;
  final bool isSpectator;
  final bool? animationsEnabled;
  final ValueChanged<String>? onSpecialPowerAnimationComplete;

  const GameTableWidget({
    super.key,
    required this.gameState,
    required this.callbacks,
    this.multiplayerConfig = MultiplayerConfig.solo,
    this.shakingCardIndices = const [],
    this.isProcessing = false,
    this.isSpectator = false,
    this.animationsEnabled,
    this.onSpecialPowerAnimationComplete,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return _GameTableContent(
      gameState: gameState,
      callbacks: callbacks,
      multiplayerConfig: multiplayerConfig,
      shakingCardIndices: shakingCardIndices,
      isProcessing: isProcessing,
      isSpectator: isSpectator,
      animationsEnabled: animationsEnabled ?? settings.animationsEnabled,
      onSpecialPowerAnimationComplete: onSpecialPowerAnimationComplete,
    );
  }
}

class _GameTableContent extends StatefulWidget {
  final GameState gameState;
  final GameTableCallbacks callbacks;
  final MultiplayerConfig multiplayerConfig;
  final List<int> shakingCardIndices;
  final bool isProcessing;
  final bool isSpectator;
  final bool animationsEnabled;
  final ValueChanged<String>? onSpecialPowerAnimationComplete;

  const _GameTableContent({
    required this.gameState,
    required this.callbacks,
    required this.multiplayerConfig,
    required this.shakingCardIndices,
    required this.isProcessing,
    required this.isSpectator,
    required this.animationsEnabled,
    this.onSpecialPowerAnimationComplete,
  });

  @override
  State<_GameTableContent> createState() => _GameTableContentState();
}

class _GameTableContentState extends State<_GameTableContent>
    with GameLayoutMixin<_GameTableContent> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _deckKey = GlobalKey();
  final GlobalKey _discardKey = GlobalKey();
  final GlobalKey _drawnCardKey = GlobalKey();
  final Map<String, GlobalKey> _handKeys = {};
  final Map<String, int> _lastHandCounts = {};
  final Map<String, Set<int>> _hiddenCardIndexByPlayer = {};
  final Map<String, Set<String>> _hiddenCardIdsByPlayer = {};
  final List<_PenaltyAnimation> _penaltyAnimations = [];
  int _nextPenaltyAnimationId = 0;
  final Map<String, List<PlayingCard>> _lastHandCards = {};
  int _lastDiscardPileSize = 0;
  PlayingCard? _lastTopDiscardCard;
  final List<_DiscardAnimation> _discardAnimations = [];
  int _nextDiscardAnimationId = 0;
  PlayingCard? _discardOverrideCard;
  int _discardOverrideCount = 0;
  PlayingCard? _lastDrawnCard;
  Offset? _lastDrawnCardCenter;
  final List<_DrawnToHandAnimation> _drawnToHandAnimations = [];
  int _nextDrawnToHandAnimationId = 0;
  String? _pendingSpecialPowerCardId;

  GameState get gs => widget.gameState;
  GameTableCallbacks get callbacks => widget.callbacks;
  MultiplayerConfig get mpConfig => widget.multiplayerConfig;
  bool get isSpectator => widget.isSpectator;
  bool get _animationsEnabled => widget.animationsEnabled;

  @override
  void initState() {
    super.initState();
    _syncHandTracking();
    _syncCardTracking();
  }

  @override
  void didUpdateWidget(covariant _GameTableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationsEnabled && !_animationsEnabled) {
      setState(() {
        _clearAnimationsAndOverrides();
      });
    }
    _syncHandTracking();
    _checkPenaltyAnimations();
    _checkDiscardAnimations();
    _checkDrawnCardAnimations();
    _syncCardTracking();
  }

  Player? get _humanPlayer {
    if (mpConfig.playerId != null) {
      try {
        return gs.players.firstWhere((p) => p.id == mpConfig.playerId);
      } catch (_) {
        return null;
      }
    }
    try {
      return gs.players.firstWhere((p) => p.isHuman);
    } catch (_) {
      return null;
    }
  }

  List<Player> get _opponents {
    final human = _humanPlayer;
    if (human == null) return gs.players;
    return gs.players.where((p) => p.id != human.id).toList();
  }

  bool get _isMyTurn {
    final human = _humanPlayer;
    if (human == null) return false;
    return gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
  }

  bool get _hasDrawn => gs.drawnCard != null;

  bool get _canInteractWithCards {
    if (isSpectator) return false;
    return _isMyTurn || gs.phase == GamePhase.reaction;
  }

  void _syncHandTracking() {
    final ids = gs.players.map((p) => p.id).toSet();
    _handKeys.removeWhere((id, _) => !ids.contains(id));
    _lastHandCounts.removeWhere((id, _) => !ids.contains(id));
    _hiddenCardIndexByPlayer.removeWhere((id, _) => !ids.contains(id));
    _hiddenCardIdsByPlayer.removeWhere((id, _) => !ids.contains(id));
    for (final player in gs.players) {
      _handKeys.putIfAbsent(player.id, () => GlobalKey());
      _lastHandCounts.putIfAbsent(player.id, () => player.hand.length);
    }
  }

  void _syncCardTracking() {
    final ids = gs.players.map((p) => p.id).toSet();
    _lastHandCards.removeWhere((id, _) => !ids.contains(id));
    for (final player in gs.players) {
      _lastHandCards[player.id] = List<PlayingCard>.from(player.hand);
    }
    _lastDiscardPileSize = gs.discardPile.length;
    _lastTopDiscardCard = gs.topDiscardCard;
    // En multijoueur, ne tracker la carte piochée que si c'est notre tour
    // Cela évite que tous les joueurs voient l'animation quand un autre pioche
    final human = _humanPlayer;
    final isMultiplayer = mpConfig.playerId != null;
    final isMyTurn = human != null && gs.currentPlayer.id == human.id;
    if (!isMultiplayer || isMyTurn) {
      _lastDrawnCard = gs.drawnCard;
    } else if (gs.drawnCard == null) {
      // Reset quand la carte piochée disparaît (fin du tour de l'autre joueur)
      _lastDrawnCard = null;
    }
  }

  void _checkPenaltyAnimations() {
    if (!_animationsEnabled) {
      _ensureAnimationsDisabled();
      _updateHandCounts();
      return;
    }
    if (gs.phase != GamePhase.reaction) {
      if (_penaltyAnimations.isNotEmpty) {
        setState(() {
          for (final anim in _penaltyAnimations) {
            _unhideHandIndex(anim.playerId, anim.hiddenIndex);
          }
          _penaltyAnimations.clear();
        });
      }
      _updateHandCounts();
      return;
    }

    for (final player in gs.players) {
      final previous = _lastHandCounts[player.id] ?? player.hand.length;
      if (player.hand.length > previous) {
        final newIndex = player.hand.length - 1;
        _hideHandIndex(player.id, newIndex);
        _schedulePenaltyAnimation(player, newIndex);
      }
    }

    _updateHandCounts();
  }

  void _checkDiscardAnimations() {
    if (!_animationsEnabled) {
      _ensureAnimationsDisabled();
      return;
    }
    final human = _humanPlayer;
    if (human == null) {
      return;
    }

    // En multijoueur, ne montrer l'animation que si c'est le joueur local qui agit
    // (la carte piochée était visible par lui et il la défausse/remplace)
    final isMultiplayer = mpConfig.playerId != null;
    if (isMultiplayer && _lastDrawnCard == null) {
      // Si on n'avait pas de carte piochée visible, on ne doit pas animer
      // car c'est probablement l'action d'un autre joueur
      return;
    }

    final currentDiscard = gs.discardPile.length;
    if (currentDiscard <= _lastDiscardPileSize) {
      return;
    }

    final previousHand = _lastHandCards[human.id];
    if (previousHand == null || previousHand.isEmpty) {
      return;
    }

    final currentIds = human.hand.map((c) => c.id).toSet();
    final removedCards =
        previousHand.where((c) => !currentIds.contains(c.id)).toList();

    if (removedCards.isNotEmpty) {
      final previousTop = _lastTopDiscardCard;
      final removedCard = removedCards.first;
      final removedIndex =
          previousHand.indexWhere((c) => c.id == removedCard.id);
      if (removedIndex >= 0) {
        _scheduleDiscardAnimation(
          player: human,
          card: removedCard,
          cardIndex: removedIndex,
          previousHandCount: previousHand.length,
          previousTop: previousTop,
        );
      }
    }
  }

  void _checkDrawnCardAnimations() {
    if (!_animationsEnabled) {
      _ensureAnimationsDisabled();
      return;
    }
    final human = _humanPlayer;
    if (human == null) return;

    final previousDrawn = _lastDrawnCard;
    final currentDrawn = gs.drawnCard;
    if (previousDrawn == null || currentDrawn != null) return;

    // En multijoueur, cette animation ne concerne que le joueur local
    // car seul lui peut voir sa carte piochée
    // Si _lastDrawnCard existait, c'est que c'était notre tour et on avait pioché

    if (gs.discardPile.length <= _lastDiscardPileSize) return;

    final previousHand = _lastHandCards[human.id];
    if (previousHand == null) return;

    final currentHand = human.hand;
    final handLengthSame = previousHand.length == currentHand.length;

    int? changedIndex;
    int diffCount = 0;
    if (handLengthSame) {
      for (int i = 0; i < currentHand.length; i++) {
        if (previousHand[i].id != currentHand[i].id) {
          diffCount += 1;
          changedIndex = i;
          if (diffCount > 1) break;
        }
      }
    }

    final previousTop = _lastTopDiscardCard;

    if (handLengthSame && diffCount == 1 && changedIndex != null) {
      if (currentHand[changedIndex].id == previousDrawn.id) {
        _scheduleDrawnToHandAnimation(
          player: human,
          card: previousDrawn,
          cardIndex: changedIndex,
        );
      }
      return;
    }

    if (handLengthSame && diffCount == 0) {
      _scheduleDrawnToDiscardAnimation(
        player: human,
        card: previousDrawn,
        previousTop: previousTop,
      );
    }
  }

  void _updateHandCounts() {
    for (final player in gs.players) {
      _lastHandCounts[player.id] = player.hand.length;
    }
  }

  void _clearAnimationsAndOverrides() {
    _hiddenCardIndexByPlayer.clear();
    _hiddenCardIdsByPlayer.clear();
    _penaltyAnimations.clear();
    _discardAnimations.clear();
    _drawnToHandAnimations.clear();
    _discardOverrideCard = null;
    _discardOverrideCount = 0;
    _pendingSpecialPowerCardId = null;
  }

  void _ensureAnimationsDisabled() {
    final hasActive = _hiddenCardIndexByPlayer.isNotEmpty ||
        _hiddenCardIdsByPlayer.isNotEmpty ||
        _penaltyAnimations.isNotEmpty ||
        _discardAnimations.isNotEmpty ||
        _drawnToHandAnimations.isNotEmpty ||
        _discardOverrideCount != 0;
    if (!hasActive) return;
    setState(() {
      _clearAnimationsAndOverrides();
    });
  }

  void _hideHandIndex(String playerId, int index) {
    final set = _hiddenCardIndexByPlayer.putIfAbsent(playerId, () => <int>{});
    set.add(index);
  }

  void _unhideHandIndex(String playerId, int index) {
    final set = _hiddenCardIndexByPlayer[playerId];
    if (set == null) return;
    set.remove(index);
    if (set.isEmpty) {
      _hiddenCardIndexByPlayer.remove(playerId);
    }
  }

  void _hideHandCardId(String playerId, String cardId) {
    final set =
        _hiddenCardIdsByPlayer.putIfAbsent(playerId, () => <String>{});
    set.add(cardId);
  }

  void _unhideHandCardId(String playerId, String cardId) {
    final set = _hiddenCardIdsByPlayer[playerId];
    if (set == null) return;
    set.remove(cardId);
    if (set.isEmpty) {
      _hiddenCardIdsByPlayer.remove(playerId);
    }
  }

  Offset? _globalCenter(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox) return null;
    final size = render.size;
    return render.localToGlobal(Offset(size.width / 2, size.height / 2));
  }

  Offset? _globalLastCardCenter(GlobalKey key, CardSize cardSize) {
    final context = key.currentContext;
    if (context == null) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox) return null;
    final size = render.size;
    final metrics = cardVisualSize(context, cardSize);
    final dx = (size.width - (metrics.width / 2)).clamp(0.0, size.width);
    final dy = (size.height / 2).clamp(0.0, size.height);
    return render.localToGlobal(Offset(dx, dy));
  }

  Offset? _globalDrawnCardCenter() {
    final center = _globalCenter(_drawnCardKey);
    return center ?? _lastDrawnCardCenter ?? _globalCenter(_deckKey);
  }

  Offset? _globalCardCenterInHand(
    GlobalKey key,
    int index,
    CardSize cardSize,
    int handCount, {
    required bool overlapCards,
    required bool fitToWidth,
  }) {
    final context = key.currentContext;
    if (context == null) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox) return null;
    if (handCount <= 0) return null;

    final size = render.size;
    final cardGap = ScreenUtils.spacing(context, 4.0);
    final metrics = PlayerHandWidget.metrics(
      context,
      cardSize,
      handCount,
      overlapCards: overlapCards,
      cardGap: cardGap,
    );

    double overlap = metrics.overlap;
    double totalWidth = metrics.totalWidth;
    final maxWidth =
        size.width.isFinite ? size.width : metrics.totalWidth;

    if (fitToWidth && handCount > 1 && totalWidth > maxWidth + 0.5) {
      final desiredOverlap = (maxWidth - metrics.cardWidth) / (handCount - 1);
      final minOverlap = metrics.cardWidth * 0.55;
      overlap = desiredOverlap.clamp(minOverlap, overlap);
      totalWidth = metrics.cardWidth + (handCount - 1) * overlap;
    }

    double startX;
    if (totalWidth <= maxWidth + 0.5) {
      startX = (maxWidth - totalWidth) / 2;
    } else {
      startX = 0.0;
    }

    final clampedIndex = index.clamp(0, handCount - 1);
    final dx = startX + (clampedIndex * overlap) + (metrics.cardWidth / 2);
    final dy = size.height / 2;
    return render.localToGlobal(Offset(dx, dy));
  }

  CardSize _cardSizeForPlayer(Player player) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.height < 400 || size.width < 700;
    if (player.isHuman) {
      return isCompact ? CardSize.small : CardSize.medium;
    }
    return isCompact ? CardSize.tiny : CardSize.small;
  }

  void _schedulePenaltyAnimation(Player player, int hiddenIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackContext = _stackKey.currentContext;
      if (stackContext == null) return;
      final stackRender = stackContext.findRenderObject();
      if (stackRender is! RenderBox) return;

      final startGlobal = _globalCenter(_deckKey);
      final cardSize = _cardSizeForPlayer(player);
      final endGlobal =
          _globalLastCardCenter(_handKeys[player.id] ?? GlobalKey(), cardSize);
      if (startGlobal == null || endGlobal == null) return;

      final stackOrigin = stackRender.localToGlobal(Offset.zero);
      final cardMetrics = cardVisualSize(context, cardSize);
      final halfCard = Offset(cardMetrics.width / 2, cardMetrics.height / 2);
      final start = startGlobal - stackOrigin - halfCard;
      final end = endGlobal - stackOrigin - halfCard;

      final anim = _PenaltyAnimation(
        id: _nextPenaltyAnimationId++,
        playerId: player.id,
        hiddenIndex: hiddenIndex,
        start: start,
        end: end,
        size: cardSize,
      );

      setState(() {
        _penaltyAnimations.add(anim);
      });
    });
  }

  void _removePenaltyAnimation(int id) {
    if (!mounted) return;
    setState(() {
      final removed = _penaltyAnimations.where((a) => a.id == id).toList();
      _penaltyAnimations.removeWhere((a) => a.id == id);
      for (final anim in removed) {
        _unhideHandIndex(anim.playerId, anim.hiddenIndex);
      }
    });
  }

  void _scheduleDiscardAnimation({
    required Player player,
    required PlayingCard card,
    required int cardIndex,
    required int previousHandCount,
    required PlayingCard? previousTop,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackContext = _stackKey.currentContext;
      if (stackContext == null) return;
      final stackRender = stackContext.findRenderObject();
      if (stackRender is! RenderBox) return;

      final handKey = _handKeys[player.id];
      if (handKey == null) return;
      final cardSize = _cardSizeForPlayer(player);
      final startGlobal = _globalCardCenterInHand(
        handKey,
        cardIndex,
        cardSize,
        previousHandCount,
        overlapCards: !player.isHuman,
        fitToWidth: player.isHuman,
      );
      final endGlobal = _globalCenter(_discardKey);
      if (startGlobal == null) return;

      final stackOrigin = stackRender.localToGlobal(Offset.zero);
      final cardMetrics = cardVisualSize(context, cardSize);
      final halfCard = Offset(cardMetrics.width / 2, cardMetrics.height / 2);
      final start = startGlobal - stackOrigin - halfCard;
      final end = endGlobal != null
          ? endGlobal - stackOrigin - halfCard
          : (stackRender.size.center(Offset.zero) - halfCard);

      final anim = _DiscardAnimation(
        id: _nextDiscardAnimationId++,
        card: card,
        start: start,
        end: end,
        size: cardSize,
      );

      setState(() {
        final special = gs.specialCardToActivate;
        if (_animationsEnabled &&
            special != null &&
            gs.isWaitingForSpecialPower &&
            special.id == card.id) {
          _pendingSpecialPowerCardId = card.id;
        }
        if (gs.phase == GamePhase.playing) {
          if (_discardOverrideCount == 0) {
            _discardOverrideCard = previousTop;
          }
          _discardOverrideCount += 1;
        }
        _discardAnimations.add(anim);
      });
    });
  }

  void _removeDiscardAnimation(int id) {
    if (!mounted) return;
    setState(() {
      final removed = _discardAnimations.where((a) => a.id == id).toList();
      if (removed.isEmpty) return;
      _discardAnimations.removeWhere((a) => a.id == id);
      _discardOverrideCount =
          (_discardOverrideCount - removed.length).clamp(0, 9999).toInt();
      if (_discardOverrideCount == 0) {
        _discardOverrideCard = null;
      }
      for (final anim in removed) {
        final specialId = gs.specialCardToActivate?.id;
        if (specialId != null &&
            anim.card.id == specialId &&
            (_pendingSpecialPowerCardId == null ||
                _pendingSpecialPowerCardId == anim.card.id)) {
          _pendingSpecialPowerCardId = anim.card.id;
          if (_drawnToHandAnimations.isEmpty) {
            _pendingSpecialPowerCardId = null;
            _notifySpecialPowerAfterDelay(anim.card.id);
          }
        }
      }
    });
  }

  void _scheduleDrawnToHandAnimation({
    required Player player,
    required PlayingCard card,
    required int cardIndex,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackContext = _stackKey.currentContext;
      if (stackContext == null) return;
      final stackRender = stackContext.findRenderObject();
      if (stackRender is! RenderBox) return;

      final handKey = _handKeys[player.id];
      if (handKey == null) return;
      final cardSize = _cardSizeForPlayer(player);
      final startGlobal = _globalDrawnCardCenter();
      final endGlobal = _globalCardCenterInHand(
        handKey,
        cardIndex,
        cardSize,
        player.hand.length,
        overlapCards: !player.isHuman,
        fitToWidth: player.isHuman,
      );
      if (startGlobal == null || endGlobal == null) return;

      final stackOrigin = stackRender.localToGlobal(Offset.zero);
      final cardMetrics = cardVisualSize(context, cardSize);
      final halfCard = Offset(cardMetrics.width / 2, cardMetrics.height / 2);
      final start = startGlobal - stackOrigin - halfCard;
      final end = endGlobal - stackOrigin - halfCard;

      final anim = _DrawnToHandAnimation(
        id: _nextDrawnToHandAnimationId++,
        playerId: player.id,
        hiddenIndex: cardIndex,
        card: card,
        start: start,
        end: end,
        size: cardSize,
      );

      setState(() {
        _hideHandCardId(player.id, card.id);
        _drawnToHandAnimations.add(anim);
      });
    });
  }

  void _removeDrawnToHandAnimation(int id) {
    if (!mounted) return;
    setState(() {
      final removed = _drawnToHandAnimations.where((a) => a.id == id).toList();
      if (removed.isEmpty) return;
      _drawnToHandAnimations.removeWhere((a) => a.id == id);
      for (final anim in removed) {
        _unhideHandCardId(anim.playerId, anim.card.id);
      }
      if (_pendingSpecialPowerCardId != null &&
          _drawnToHandAnimations.isEmpty) {
        final pendingId = _pendingSpecialPowerCardId!;
        _pendingSpecialPowerCardId = null;
        _notifySpecialPowerAfterDelay(pendingId);
      }
    });
  }

  void _scheduleDrawnToDiscardAnimation({
    required Player player,
    required PlayingCard card,
    required PlayingCard? previousTop,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackContext = _stackKey.currentContext;
      if (stackContext == null) return;
      final stackRender = stackContext.findRenderObject();
      if (stackRender is! RenderBox) return;

      final cardSize = _cardSizeForPlayer(player);
      final startGlobal = _globalDrawnCardCenter();
      final endGlobal = _globalCenter(_discardKey);
      if (startGlobal == null) return;

      final stackOrigin = stackRender.localToGlobal(Offset.zero);
      final cardMetrics = cardVisualSize(context, cardSize);
      final halfCard = Offset(cardMetrics.width / 2, cardMetrics.height / 2);
      final start = startGlobal - stackOrigin - halfCard;
      final end = endGlobal != null
          ? endGlobal - stackOrigin - halfCard
          : (stackRender.size.center(Offset.zero) - halfCard);

      final anim = _DiscardAnimation(
        id: _nextDiscardAnimationId++,
        card: card,
        start: start,
        end: end,
        size: cardSize,
      );

      setState(() {
        final special = gs.specialCardToActivate;
        if (_animationsEnabled &&
            special != null &&
            gs.isWaitingForSpecialPower &&
            special.id == card.id) {
          _pendingSpecialPowerCardId = card.id;
        }
        if (gs.phase == GamePhase.playing) {
          if (_discardOverrideCount == 0) {
            _discardOverrideCard = previousTop;
          }
          _discardOverrideCount += 1;
        }
        _discardAnimations.add(anim);
      });
    });
  }

  void _notifySpecialPowerAfterDelay(String cardId) {
    final callback = widget.onSpecialPowerAnimationComplete;
    if (callback == null) return;
    const delay = Duration(milliseconds: 140);
    Future.delayed(delay, () {
      if (!mounted) return;
      final specialId = gs.specialCardToActivate?.id;
      if (gs.isWaitingForSpecialPower && specialId == cardId) {
        callback(cardId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final human = _humanPlayer;
    final opponents = _opponents;

    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    final isCompact = screenHeight < 400 || screenWidth < 700;
    final isLandscape = screenWidth > screenHeight;
    // Active la disposition latérale pioche/défausse sur les petits écrans en paysage
    // (iPhones, petites tablettes en paysage avec hauteur < 500)
    final useSideDeckDiscard = isLandscape && screenHeight < 500;
    final showCenterDeck =
        !useSideDeckDiscard || isSpectator || human == null;
    final botCardType = isCompact ? CardSize.tiny : CardSize.small;
    final playerCardType = isCompact ? CardSize.small : CardSize.medium;
    final botCardMetrics = cardVisualSize(context, botCardType);
    final playerCardMetrics = cardVisualSize(context, playerCardType);
    final blockSpacing = ScreenUtils.spacing(context, isCompact ? 4.0 : 6.0);
    final botOverlap =
        botCardMetrics.width * PlayerHandWidget.overlapFactor(botCardType);
    final outerGapBase =
        math.min(botCardMetrics.height, playerCardMetrics.height) *
            (isCompact ? 0.05 : 0.035);
    final outerGap = outerGapBase.clamp(0.0, 6.0);
    final centerGapX = botCardMetrics.width * (isCompact ? 0.3 : 0.22);
    final botBadgeSize = isCompact ? 18.0 : 24.0;

    final botBadgeHeight = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => compactBadgeHeight(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final botBlockHeight =
        botBadgeHeight + blockSpacing + botCardMetrics.height;

    final maxBotBadgeWidth = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => compactBadgeWidth(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final maxBotHandWidth = opponents.isEmpty
        ? botCardMetrics.width
        : opponents.map((bot) {
            final count = math.max(1, bot.hand.length);
            return botCardMetrics.width + (count - 1) * botOverlap;
          }).fold(0.0, math.max);

    final playerBadgeSize = isCompact ? 24.0 : 28.0;
    final playerBadgeHeight = isSpectator || human == null
        ? 40.0
        : compactBadgeHeight(context, human, playerBadgeSize);

    final playerBlockHeight = isSpectator
        ? 60.0
        : playerBadgeHeight + blockSpacing + playerCardMetrics.height;

    final layout = actionButtonLayout(context, isCompact, playerCardMetrics);
    final playerAreaHeight =
        isSpectator ? 60.0 : math.max(layout.columnHeight, playerBlockHeight);

    final sideBandContentWidth =
        math.max(botBlockHeight, math.max(maxBotBadgeWidth, maxBotHandWidth));
    final sideBandWidth = sideBandContentWidth + outerGap + centerGapX;
    final centerMinHeight = estimateCenterMinHeight(context, gs, isCompact);
    final opponentCount = opponents.length;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final baseHeight = botBlockHeight +
              playerAreaHeight +
              centerMinHeight +
              (outerGap * 2);
          final slack = math.max(0.0, constraints.maxHeight - baseHeight);
          final totalWeight =
              botBlockHeight + playerAreaHeight + centerMinHeight;
          final centerExtra =
              totalWeight == 0 ? 0.0 : slack * (centerMinHeight / totalWeight);
          final gapSlack = slack - centerExtra;
          final topGap = gapSlack;
          const bottomGap = 0.0;
          final topBandHeight = botBlockHeight + outerGap + topGap;
          final bottomBandHeight = playerAreaHeight + outerGap + bottomGap;
          final centerWidth =
              math.max(0.0, constraints.maxWidth - (sideBandWidth * 2));
          final centerHeight = math.max(
            0.0,
            constraints.maxHeight - topBandHeight - bottomBandHeight,
          );
          final isDrawnCardVisible =
              _isMyTurn && _hasDrawn && gs.drawnCard != null;

          final centerSmallMetrics = cardVisualSize(context, CardSize.small);
          final centerMediumMetrics = cardVisualSize(context, CardSize.medium);
          const centerSmallPadding = 8.0;
          const centerMediumPadding = 15.0;
          const centerSmallGap = 10.0;
          const centerMediumGap = 20.0;
          final centerSmallWidth =
              (centerSmallMetrics.width * 2) + centerSmallGap + (centerSmallPadding * 2);
          final centerSmallHeight =
              centerSmallMetrics.height + (centerSmallPadding * 2);
          final centerMediumWidth =
              (centerMediumMetrics.width * 2) + centerMediumGap + (centerMediumPadding * 2);
          final centerMediumHeight =
              centerMediumMetrics.height + (centerMediumPadding * 2);
          final centerUseMedium =
              centerWidth >= centerMediumWidth && centerHeight >= centerMediumHeight;
          final centerCompact = isCompact && !centerUseMedium;
          final baseCenterWidth = centerUseMedium ? centerMediumWidth : centerSmallWidth;
          final baseCenterHeight = centerUseMedium ? centerMediumHeight : centerSmallHeight;
          final rawCenterScale = math.min(
            baseCenterWidth <= 0 ? 1.0 : centerWidth / baseCenterWidth,
            baseCenterHeight <= 0 ? 1.0 : centerHeight / baseCenterHeight,
          );
          final centerScale = isCompact
              ? rawCenterScale.clamp(1.0, 1.25).toDouble()
              : 1.0;

          // Largeur des zones pioche/défausse latérales
          // Calculée en réservant d'abord l'espace nécessaire au centre,
          // puis en distribuant l'espace restant aux côtés
          final desiredCenterWidth = baseCenterWidth * centerScale;
          final centerReservedWidth = desiredCenterWidth.clamp(0.0, centerWidth);
          final remainingWidth = centerWidth - centerReservedWidth;
          final sideAccessoryWidth = useSideDeckDiscard
              ? (remainingWidth / 2)
              : 0.0;

          final centerShiftY = (botCardMetrics.height -
                  playerCardMetrics.height -
                  topBandHeight +
                  bottomBandHeight) /
              2.0;
          final centerShiftFraction = centerHeight == 0
              ? 0.0
              : (centerShiftY / (centerHeight / 2)).clamp(-1.0, 1.0);
    if (isDrawnCardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final center = _globalCenter(_drawnCardKey);
        if (center != null) {
          _lastDrawnCardCenter = center;
        }
      });
    }

    // Largeur effective pour le centre (réduite si accessoires latéraux)
    final effectiveSideBandWidth = sideBandWidth + sideAccessoryWidth;

    return Stack(
      key: _stackKey,
      children: [
        // Centre - Table (pioche + défausse ou juste texte reaction)
        Positioned(
          left: effectiveSideBandWidth,
          right: effectiveSideBandWidth,
                top: topBandHeight,
                bottom: bottomBandHeight,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: centerWidth,
                      maxHeight: centerHeight,
                    ),
                    child: Align(
                      alignment: Alignment(
                        0,
                        isDrawnCardVisible
                            ? centerShiftFraction
                            : (isCompact ? centerShiftFraction * 0.35 : 0.0),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Transform.scale(
                          scale: centerScale,
                          child: CenterTable(
                            gameState: gs,
                            isMyTurn: _isMyTurn,
                            hasDrawn: _hasDrawn,
                            isCompactMode: centerCompact,
                            onShowDiscard: callbacks.onShowDiscardPile,
                            onDrawCard: callbacks.onDrawCard,
                            onTakeFromDiscard: callbacks.onTakeFromDiscard,
                            reactionTimeTotalMs:
                                mpConfig.reactionTimeTotalMs,
                            enableHaptics: true,
                            showDeckAndDiscard: showCenterDeck,
                            deckKey: _deckKey,
                            discardKey: _discardKey,
                            discardCardOverride:
                                gs.phase == GamePhase.playing
                                    ? _discardOverrideCard
                                    : null,
                            drawnCardKey: _drawnCardKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ),

              // Pioche à gauche (entre adversaires gauche et centre)
              if (useSideDeckDiscard && !isSpectator && human != null)
                Positioned(
                  left: sideBandWidth,
                  top: topBandHeight,
                  bottom: bottomBandHeight,
                  width: sideAccessoryWidth,
                  child: _buildSideDeck(context, sideAccessoryWidth, centerHeight),
                ),

              // Défausse à droite (entre centre et adversaires droite)
              if (useSideDeckDiscard && !isSpectator && human != null)
                Positioned(
                  right: sideBandWidth,
                  top: topBandHeight,
                  bottom: bottomBandHeight,
                  width: sideAccessoryWidth,
                  child: _buildSideDiscard(context, sideAccessoryWidth, centerHeight),
                ),

              // Disposition adversaires (2-4 joueurs personnalisée, 5-6 inchangé)
              if (opponentCount >= 4)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildLeftOpponents(
                    context,
                    opponents,
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),
              if (opponentCount >= 4)
                Positioned(
                  top: 0,
                  left: sideBandWidth,
                  right: sideBandWidth,
                  height: topBandHeight,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: outerGap),
                      child: _buildOpponentBlock(
                        context,
                        opponents[2],
                        isCompact,
                        botCardType,
                        botBadgeSize,
                        blockSpacing,
                      ),
                    ),
                  ),
                ),
              if (opponentCount >= 4)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildRightOpponents(
                    context,
                    opponents,
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),
              if (opponentCount == 3)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildSingleLeftOpponent(
                    context,
                    opponents[0],
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),
              if (opponentCount == 3)
                Positioned(
                  top: 0,
                  left: sideBandWidth,
                  right: sideBandWidth,
                  height: topBandHeight,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: outerGap),
                      child: _buildOpponentBlock(
                        context,
                        opponents[1],
                        isCompact,
                        botCardType,
                        botBadgeSize,
                        blockSpacing,
                      ),
                    ),
                  ),
                ),
              if (opponentCount == 3)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildSingleRightOpponent(
                    context,
                    opponents[2],
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),
              if (opponentCount == 2)
                Positioned(
                  top: 0,
                  left: sideBandWidth,
                  right: sideBandWidth,
                  height: topBandHeight,
                  child: Padding(
                    padding: EdgeInsets.only(top: outerGap),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: _buildOpponentBlock(
                              context,
                              opponents[0],
                              isCompact,
                              botCardType,
                              botBadgeSize,
                              blockSpacing,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: _buildOpponentBlock(
                              context,
                              opponents[1],
                              isCompact,
                              botCardType,
                              botBadgeSize,
                              blockSpacing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (opponentCount == 1)
                Positioned(
                  top: 0,
                  left: sideBandWidth,
                  right: sideBandWidth,
                  height: topBandHeight,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: outerGap),
                      child: _buildOpponentBlock(
                        context,
                        opponents[0],
                        isCompact,
                        botCardType,
                        botBadgeSize,
                        blockSpacing,
                      ),
                    ),
                  ),
                ),

              // Bas - Zone joueur
              if (!isSpectator && human != null)
                Positioned(
                  left: sideBandWidth,
                  right: sideBandWidth,
                  bottom: outerGap,
                  height: playerAreaHeight,
                  child: _buildPlayerArea(
                    context,
                    human,
                    isCompact,
                    playerCardType,
                    playerBadgeSize,
                    blockSpacing,
                    playerAreaHeight,
                    constraints.maxWidth - (sideBandWidth * 2),
                  ),
                ),

              // Spectateur - Bandeau info
              if (isSpectator)
                Positioned(
                  left: sideBandWidth,
                  right: sideBandWidth,
                  bottom: outerGap,
                  height: 60,
                  child: _buildSpectatorBanner(context),
                ),

              ..._penaltyAnimations.map((anim) {
                return AnimatedCardTransition(
                  key: ValueKey('penalty_${anim.id}'),
                  card: null,
                  isRevealed: false,
                  size: anim.size,
                  startPosition: anim.start,
                  endPosition: anim.end,
                  duration: const Duration(milliseconds: 380),
                  onComplete: () => _removePenaltyAnimation(anim.id),
                );
              }),
              ..._discardAnimations.map((anim) {
                return AnimatedCardTransition(
                  key: ValueKey('discard_${anim.id}'),
                  card: anim.card,
                  isRevealed: true,
                  size: anim.size,
                  startPosition: anim.start,
                  endPosition: anim.end,
                  duration: const Duration(milliseconds: 360),
                  onComplete: () => _removeDiscardAnimation(anim.id),
                );
              }),
              ..._drawnToHandAnimations.map((anim) {
                return AnimatedCardTransition(
                  key: ValueKey('drawn_${anim.id}'),
                  card: anim.card,
                  isRevealed: true,
                  size: anim.size,
                  startPosition: anim.start,
                  endPosition: anim.end,
                  duration: const Duration(milliseconds: 380),
                  onComplete: () => _removeDrawnToHandAnimation(anim.id),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeftOpponents(
    BuildContext context,
    List<Player> opponents,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    if (opponents.length >= 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(left: outerGap),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _buildOpponentBlock(
                    context,
                    opponents[1],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(left: outerGap),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _buildOpponentBlock(
                    context,
                    opponents[0],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: outerGap),
        child: RotatedBox(
          quarterTurns: 1,
          child: _buildOpponentBlock(
            context,
            opponents[0],
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleLeftOpponent(
    BuildContext context,
    Player opponent,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: outerGap),
        child: RotatedBox(
          quarterTurns: 1,
          child: _buildOpponentBlock(
            context,
            opponent,
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildRightOpponents(
    BuildContext context,
    List<Player> opponents,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    if (opponents.length >= 5) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: outerGap),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: _buildOpponentBlock(
                    context,
                    opponents[3],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: outerGap),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: _buildOpponentBlock(
                    context,
                    opponents[4],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: outerGap),
        child: RotatedBox(
          quarterTurns: 3,
          child: _buildOpponentBlock(
            context,
            opponents[3],
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleRightOpponent(
    BuildContext context,
    Player opponent,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: outerGap),
        child: RotatedBox(
          quarterTurns: 3,
          child: _buildOpponentBlock(
            context,
            opponent,
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildOpponentBlock(
    BuildContext context,
    Player opponent,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
  ) {
    final isActive = gs.currentPlayer.id == opponent.id;
    final isConnected = mpConfig.playerConnections[opponent.id];
    final isAfk = mpConfig.playerAfkStatus[opponent.id] ?? false;

    final canInteract = gs.isWaitingForSpecialPower &&
        _humanPlayer != null &&
        gs.currentPlayer.id == _humanPlayer!.id;

    return buildOpponentArea(
      context: context,
      opponent: opponent,
      isActive: isActive,
      canInteract: canInteract,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      isCompactMode: isCompact,
      handKey: _handKeys[opponent.id],
      hiddenIndices: _hiddenCardIndexByPlayer[opponent.id]?.toList(),
      hiddenCardIds: _hiddenCardIdsByPlayer[opponent.id]?.toList(),
      isConnected: isConnected,
      isAfk: isAfk,
      turnStartTime: isActive ? mpConfig.turnStartTime : null,
      turnDuration: isActive ? mpConfig.turnDuration : null,
      onCardTap: canInteract && callbacks.onOpponentCardTap != null
          ? (index) => callbacks.onOpponentCardTap!(opponent.position, index)
          : null,
    );
  }

  Widget _buildPlayerArea(
    BuildContext context,
    Player human,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double maxHeight,
    double availableWidth,
  ) {
    return buildPlayerAreaWithButtons(
      context: context,
      human: human,
      isMyTurn: _isMyTurn,
      hasDrawn: _hasDrawn,
      canInteractWithCards: _canInteractWithCards,
      isCompactMode: isCompact,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      maxHeight: maxHeight,
      selectedIndices: widget.shakingCardIndices,
      onCardTap: callbacks.onCardTap,
      onDraw: callbacks.onDrawCard,
      onDiscard: callbacks.onDiscardDrawnCard,
      onDutch: () async {
        final confirmed = await GameDialogs.confirmDutch(context);
        if (confirmed == true) {
          callbacks.onCallDutch();
        }
      },
      constrainedWidth: availableWidth,
      handKey: _handKeys[human.id],
      hiddenIndices: _hiddenCardIndexByPlayer[human.id]?.toList(),
      hiddenCardIds: _hiddenCardIdsByPlayer[human.id]?.toList(),
    );
  }

  Widget _buildSideDeck(BuildContext context, double maxWidth, double maxHeight) {
    final canDraw = _isMyTurn && !_hasDrawn && gs.phase == GamePhase.playing;
    const padding = 8.0;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: canDraw ? 1.0 : 0.6,
                child: GestureDetector(
                  onTap: canDraw ? callbacks.onDrawCard : null,
                  child: CardWidget(
                    key: _deckKey,
                    card: null,
                    size: CardSize.medium,
                    isRevealed: false,
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${gs.deck.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideDiscard(BuildContext context, double maxWidth, double maxHeight) {
    final canTakeDiscard = callbacks.onTakeFromDiscard != null &&
        _isMyTurn &&
        !_hasDrawn &&
        gs.phase == GamePhase.playing &&
        gs.discardPile.isNotEmpty;
    final discardCard = (gs.phase == GamePhase.playing
            ? _discardOverrideCard
            : null) ??
        gs.topDiscardCard;
    const padding = 8.0;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: GestureDetector(
            onTap: canTakeDiscard
                ? callbacks.onTakeFromDiscard
                : callbacks.onShowDiscardPile,
            child: CardWidget(
              key: _discardKey,
              card: discardCard,
              size: CardSize.medium,
              isRevealed: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpectatorBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility, color: Colors.amber, size: 24),
            SizedBox(width: 12),
            Text(
              "Mode Spectateur",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenaltyAnimation {
  final int id;
  final String playerId;
  final int hiddenIndex;
  final Offset start;
  final Offset end;
  final CardSize size;

  _PenaltyAnimation({
    required this.id,
    required this.playerId,
    required this.hiddenIndex,
    required this.start,
    required this.end,
    required this.size,
  });
}

class _DiscardAnimation {
  final int id;
  final PlayingCard card;
  final Offset start;
  final Offset end;
  final CardSize size;

  _DiscardAnimation({
    required this.id,
    required this.card,
    required this.start,
    required this.end,
    required this.size,
  });
}

class _DrawnToHandAnimation {
  final int id;
  final String playerId;
  final int hiddenIndex;
  final PlayingCard card;
  final Offset start;
  final Offset end;
  final CardSize size;

  _DrawnToHandAnimation({
    required this.id,
    required this.playerId,
    required this.hiddenIndex,
    required this.card,
    required this.start,
    required this.end,
    required this.size,
  });
}
