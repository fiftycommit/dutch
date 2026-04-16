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

  @override
  void initState() {
    super.initState();
    // Rafraîchit l'UI toutes les 500ms pour expirer les speeches visuellement.
    _sweepTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final current = BotGossipService.instance.speeches.value;
      final fresh = current.where((s) => !s.isExpired).toList();
      if (fresh.length != current.length) {
        BotGossipService.instance.speeches.value = fresh;
      }
    });
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<BotAlliance?>(
          valueListenable: BotGossipService.instance.alliance,
          builder: (context, alliance, _) {
            if (alliance == null) return const SizedBox.shrink();
            return _AllianceBanner(alliance: alliance);
          },
        ),
        ValueListenableBuilder<List<BotSpeech>>(
          valueListenable: BotGossipService.instance.speeches,
          builder: (context, speeches, _) {
            final visible =
                speeches.where((s) => !s.isExpired).toList().reversed.take(3).toList();
            if (visible.isEmpty) return const SizedBox.shrink();
            return Padding(
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
            );
          },
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
