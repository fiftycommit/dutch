import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';

class EmoteOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final Function(String) onEmoteSent;

  const EmoteOverlay({
    super.key,
    required this.onClose,
    required this.onEmoteSent,
  });

  @override
  State<EmoteOverlay> createState() => _EmoteOverlayState();
}

class _EmoteOverlayState extends State<EmoteOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  static const List<Map<String, String>> _emotes = [
    {'emoji': '😂', 'label': 'Rire'},
    {'emoji': '😎', 'label': 'Cool'},
    {'emoji': '🤔', 'label': 'Réfléchir'},
    {'emoji': '😱', 'label': 'Choqué'},
    {'emoji': '🎉', 'label': 'Bravo'},
    {'emoji': '😤', 'label': 'Énervé'},
    {'emoji': '👍', 'label': 'OK'},
    {'emoji': '👎', 'label': 'Pas OK'},
    {'emoji': '🔥', 'label': 'Feu'},
    {'emoji': '💪', 'label': 'Force'},
    {'emoji': '🤷', 'label': 'Bof'},
    {'emoji': '😴', 'label': 'Ennui'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendEmote(String emoji) {
    widget.onEmoteSent(emoji);
    _controller.reverse().then((_) => widget.onClose());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.height < 400;
    // Largeur maximale adaptative: 90% de l'ecran ou 400px max
    final maxWidth = (size.width * 0.9).clamp(200.0, 400.0);
    // Nombre de colonnes adaptatif
    final crossAxisCount = isCompact ? 6 : 4;

    return GestureDetector(
      onTap: () {
        _controller.reverse().then((_) => widget.onClose());
      },
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping the panel
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: EdgeInsets.all(isCompact ? 10 : 20),
                padding: EdgeInsets.all(isCompact ? 12 : 20),
                constraints: BoxConstraints(maxWidth: maxWidth),
                decoration: BoxDecoration(
                  color: AppColors.gradientBottom,
                  borderRadius: BorderRadius.circular(isCompact ? 14 : 20),
                  border: Border.all(color: Colors.amber, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ÉMOTES',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: isCompact ? 14 : 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.textSecondary, size: isCompact ? 20 : 24),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _controller.reverse().then((_) => widget.onClose());
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: isCompact ? 6 : 10),
                    // Utiliser ConstrainedBox pour limiter la hauteur du GridView
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: size.height * 0.5, // Max 50% de l'écran
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: isCompact ? 4 : 8,
                          crossAxisSpacing: isCompact ? 4 : 8,
                          // Ratio plus large pour accommoder emoji + label
                          childAspectRatio: isCompact ? 1.0 : 0.85,
                        ),
                        itemCount: _emotes.length,
                        itemBuilder: (context, index) {
                          final emote = _emotes[index];
                          return _EmoteButton(
                            emoji: emote['emoji']!,
                            label: emote['label']!,
                            onTap: () => _sendEmote(emote['emoji']!),
                            isCompact: isCompact,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmoteButton extends StatefulWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool isCompact;

  const _EmoteButton({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  State<_EmoteButton> createState() => _EmoteButtonState();
}

class _EmoteButtonState extends State<_EmoteButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 12),
            border: Border.all(
              color: _isPressed ? Colors.amber : Colors.white24,
              width: widget.isCompact ? 1.5 : 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.emoji,
                    style: TextStyle(fontSize: widget.isCompact ? 20 : 32),
                  ),
                ),
              ),
              if (!widget.isCompact) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FloatingEmote extends StatefulWidget {
  final String emoji;
  final String playerName;
  final Offset position;
  final VoidCallback onComplete;

  const FloatingEmote({
    super.key,
    required this.emoji,
    required this.playerName,
    required this.position,
    required this.onComplete,
  });

  @override
  State<FloatingEmote> createState() => _FloatingEmoteState();
}

class _FloatingEmoteState extends State<FloatingEmote>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 0,
      end: -100,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 20,
      ),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.2),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0),
        weight: 70,
      ),
    ]).animate(_controller);

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: widget.position.dx,
          top: widget.position.dy + _slideAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.playerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
