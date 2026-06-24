import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/game/bot/bot_gossip_service.dart';
import '../../utils/ui_constants.dart';

/// Overlay d'affichage des speeches bot + bannière d'alliance.
/// À poser dans la Stack du GameScreen, en `Positioned(top: 56, left: 8, right: 8)`.
class BotGossipOverlay extends StatefulWidget {
  const BotGossipOverlay({super.key});

  @override
  State<BotGossipOverlay> createState() => _BotGossipOverlayState();
}

class _BotGossipOverlayState extends State<BotGossipOverlay> {
  Timer? _sweepTimer;

  // Reconstruit l'overlay quand speeches/alliance changent (remplace
  // ValueListenableBuilder : GossipValue est un observable pur Dart).
  void _onGossipChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    BotGossipService.instance.speeches.addListener(_onGossipChanged);
    BotGossipService.instance.alliance.addListener(_onGossipChanged);
    // Rafraîchit l'UI toutes les 500ms pour expirer les speeches visuellement.
    _sweepTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final current = BotGossipService.instance.speeches.value;
      final fresh = current.where((s) => !s.isExpired).toList();
      if (fresh.length != current.length) {
        // déclenche _onGossipChanged via le setter GossipValue
        BotGossipService.instance.speeches.value = fresh;
      } else {
        // expiration temporelle sans changement de liste : rebuild quand même
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    BotGossipService.instance.speeches.removeListener(_onGossipChanged);
    BotGossipService.instance.alliance.removeListener(_onGossipChanged);
    _sweepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alliance = BotGossipService.instance.alliance.value;
    final visible = BotGossipService.instance.speeches.value
        .where((s) => !s.isExpired)
        .toList()
        .reversed
        .take(3)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (alliance != null) _AllianceBanner(alliance: alliance),
        if (visible.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _SpeechBubble(speech: s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AllianceBanner extends StatelessWidget {
  final BotAlliance alliance;
  const _AllianceBanner({required this.alliance});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.withValues(alpha: 0.85),
            Colors.deepOrange.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.handshake, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${alliance.memberNames.join(" + ")} visent ${alliance.targetName}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final BotSpeech speech;
  const _SpeechBubble({required this.speech});

  Color get _accent {
    switch (speech.tone) {
      case BotSpeechTone.warning:
        return Colors.amber;
      case BotSpeechTone.taunt:
        return Colors.redAccent;
      case BotSpeechTone.ally:
        return Colors.orangeAccent;
      case BotSpeechTone.bravado:
        return Colors.lightGreenAccent;
      case BotSpeechTone.dutch:
        return Colors.white;
    }
  }

  IconData get _icon {
    switch (speech.tone) {
      case BotSpeechTone.warning:
        return Icons.priority_high;
      case BotSpeechTone.taunt:
        return Icons.whatshot;
      case BotSpeechTone.ally:
        return Icons.handshake;
      case BotSpeechTone.bravado:
        return Icons.emoji_events;
      case BotSpeechTone.dutch:
        return Icons.flag;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: _accent, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${speech.speakerName} : ',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: speech.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
