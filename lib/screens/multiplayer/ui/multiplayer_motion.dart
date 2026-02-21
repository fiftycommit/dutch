import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'multiplayer_ui_tokens.dart';

Duration staggerIndexDelay(
  int index, {
  Duration step = const Duration(milliseconds: 70),
}) {
  if (index <= 0) return Duration.zero;
  return Duration(milliseconds: step.inMilliseconds * index);
}

Widget fadeInUp({
  required Widget child,
  Duration delay = Duration.zero,
  Duration duration = MultiplayerUiTokens.motionMedium,
  double beginOffsetY = 0.06,
  Curve curve = Curves.easeOutCubic,
}) {
  return _MpFadeInUp(
    delay: delay,
    duration: duration,
    beginOffsetY: beginOffsetY,
    curve: curve,
    child: child,
  );
}

Widget shakeOnError({
  required bool shake,
  required Widget child,
  Duration duration = const Duration(milliseconds: 280),
  double amplitude = 8,
}) {
  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: shake ? 1 : 0),
    duration: duration,
    curve: Curves.easeOut,
    child: child,
    builder: (context, value, currentChild) {
      final offsetX = math.sin(value * math.pi * 6) * amplitude * (1 - value);
      return Transform.translate(
        offset: Offset(offsetX, 0),
        child: currentChild,
      );
    },
  );
}

Widget dropdownScaleFade({
  required bool visible,
  required Widget child,
  Duration duration = MultiplayerUiTokens.motionFast,
}) {
  return AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (transitionChild, animation) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          alignment: Alignment.topRight,
          child: transitionChild,
        ),
      );
    },
    child: visible
        ? KeyedSubtree(
            key: const ValueKey<String>('dropdown_open'),
            child: child,
          )
        : const SizedBox(
            key: ValueKey<String>('dropdown_closed'),
          ),
  );
}

Widget tabContentTransition({
  required Widget child,
  Duration duration = MultiplayerUiTokens.motionMedium,
}) {
  return AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (transitionChild, animation) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: transitionChild,
        ),
      );
    },
    child: child,
  );
}

class _MpFadeInUp extends StatefulWidget {
  const _MpFadeInUp({
    required this.child,
    required this.delay,
    required this.duration,
    required this.beginOffsetY,
    required this.curve,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double beginOffsetY;
  final Curve curve;

  @override
  State<_MpFadeInUp> createState() => _MpFadeInUpState();
}

class _MpFadeInUpState extends State<_MpFadeInUp> {
  bool _visible = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _visible = true;
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (!mounted) return;
        setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: widget.duration,
      curve: widget.curve,
      offset: _visible ? Offset.zero : Offset(0, widget.beginOffsetY),
      child: AnimatedOpacity(
        duration: widget.duration,
        curve: widget.curve,
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}
