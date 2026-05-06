import 'package:flutter/material.dart';
import '../../../../providers/multiplayer_game_provider.dart';
import '../../../../core/service_locator.dart';
import '../../../../core/interfaces/i_haptic_service.dart';

/// Chat affiché en `showModalBottomSheet` sur mobile portrait.
///
/// Avantages vs. panneau inline :
/// - Le clavier remonte naturellement la sheet via `viewInsets.bottom`,
///   ce qui contourne les bugs Flutter Web iOS Safari (issues #42211, #91755)
///   où le clavier ne s'ouvre pas correctement avec un `GestureDetector` parent.
/// - Libère l'espace écran pour la liste des joueurs en lobby.
/// - FocusNode dédié → focus synchrone sur tap, requis par iOS Safari.
class LobbyChatBottomSheet {
  static Future<void> show(
    BuildContext context, {
    required MultiplayerGameProvider provider,
    required TextEditingController controller,
    required ScrollController scrollController,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => _ChatSheetContent(
        provider: provider,
        controller: controller,
        scrollController: scrollController,
      ),
    );
  }
}

class _ChatSheetContent extends StatefulWidget {
  final MultiplayerGameProvider provider;
  final TextEditingController controller;
  final ScrollController scrollController;

  const _ChatSheetContent({
    required this.provider,
    required this.controller,
    required this.scrollController,
  });

  @override
  State<_ChatSheetContent> createState() => _ChatSheetContentState();
}

class _ChatSheetContentState extends State<_ChatSheetContent> {
  final FocusNode _focusNode = FocusNode();
  int _lastChatCount = 0;

  @override
  void initState() {
    super.initState();
    _lastChatCount = widget.provider.chatMessages.length;
    widget.provider.addListener(_onProviderChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final count = widget.provider.chatMessages.length;
    if (count != _lastChatCount) {
      _lastChatCount = count;
      _scrollToBottom();
    }
    setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    ServiceLocator().get<IHapticService>().buttonTap();
    widget.provider.sendChatMessage(text);
    widget.controller.clear();
    // Garder le focus pour enchainer les messages — l'utilisateur ferme avec
    // le bouton dédié ou le drag.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final messages = widget.provider.chatMessages;
    final keyboardHeight = media.viewInsets.bottom;
    // Hauteur cible : 75% du viewport, mais on laisse le clavier prendre
    // le dessus quand il s'ouvre (Padding bottom + flex interne).
    final sheetHeight = (media.size.height * 0.75).clamp(320.0, 720.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a472a), Color(0xFF0d2818)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(context),
            const Divider(color: Colors.white24, height: 1),
            Expanded(child: _buildMessageList(colors, messages)),
            _buildComposer(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.forum, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Chat',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
      ColorScheme colors, List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Aucun message — soyez sympas :)',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMe = (message['clientId'] != null &&
                message['clientId'] == widget.provider.clientId) ||
            (message['playerId'] == widget.provider.playerId);
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? colors.primaryContainer
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'Vous' : (message['name'] ?? 'Joueur'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        isMe ? colors.onPrimaryContainer : colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message['message']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: isMe
                        ? colors.onPrimaryContainer
                        : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: Colors.black87, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: const TextStyle(color: Colors.black45),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            width: 44,
            child: IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.send, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton "Chat (n)" avec badge de messages non lus, à utiliser en portrait
/// mobile à la place du panneau inline.
class LobbyChatButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;
  final bool enabled;

  const LobbyChatButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    return Semantics(
      button: true,
      label: hasUnread
          ? 'Chat, $unreadCount message${unreadCount > 1 ? 's' : ''} non lu${unreadCount > 1 ? 's' : ''}'
          : 'Ouvrir le chat',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.14 : 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasUnread
                    ? const Color(0xFFFFB300).withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.24),
                width: hasUnread ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum,
                  color: enabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Chat',
                  style: TextStyle(
                    color: enabled
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 18),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
