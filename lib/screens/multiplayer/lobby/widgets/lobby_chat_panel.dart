import 'package:flutter/material.dart';
import '../../../../providers/multiplayer_game_provider.dart';
import '../../../../core/service_locator.dart';
import '../../../../core/interfaces/i_haptic_service.dart';

class LobbyChatPanel extends StatelessWidget {
  final MultiplayerGameProvider provider;
  final TextEditingController chatController;
  final ScrollController chatScrollController;
  final VoidCallback onDismissKeyboard;

  const LobbyChatPanel({
    super.key,
    required this.provider,
    required this.chatController,
    required this.chatScrollController,
    required this.onDismissKeyboard,
  });

  void _sendChat() {
    final text = chatController.text.trim();
    if (text.isEmpty) return;
    provider.sendChatMessage(text);
    chatController.clear();
    onDismissKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messages = provider.chatMessages;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 1.2,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = (constraints.maxHeight / 320).clamp(0.55, 1.0);
          double f(double size) => size * scale;
          if (constraints.maxHeight < 120) {
            return Center(
              child: Text(
                'Chat',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: f(12),
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  Icon(Icons.forum, size: f(18), color: Colors.white),
                  SizedBox(width: f(6)),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: f(14),
                    ),
                  ),
                ],
              ),
              SizedBox(height: f(8)),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(f(8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(f(10)),
                  ),
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            'Soyez sympas :)',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: f(11),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: chatScrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe = (message['clientId'] != null &&
                                    message['clientId'] == provider.clientId) ||
                                (message['playerId'] == provider.playerId);
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: EdgeInsets.only(bottom: f(6)),
                                padding: EdgeInsets.symmetric(
                                  horizontal: f(10),
                                  vertical: f(6),
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.6,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? colors.primaryContainer
                                      : Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(f(10)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isMe
                                          ? 'Vous'
                                          : (message['name'] ?? 'Joueur'),
                                      style: TextStyle(
                                        fontSize: f(10),
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? colors.onPrimaryContainer
                                            : colors.primary,
                                      ),
                                    ),
                                    SizedBox(height: f(2)),
                                    Text(
                                      message['message']?.toString() ?? '',
                                      style: TextStyle(
                                        fontSize: f(13),
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
                        ),
                ),
              ),
              SizedBox(height: f(8)),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: f(40),
                      child: TextField(
                        controller: chatController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendChat(),
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: f(14),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(
                            color: Colors.black45,
                            fontSize: f(13),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: f(12),
                            vertical: f(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(f(10)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: f(6)),
                  SizedBox(
                    height: f(40),
                    width: f(40),
                    child: IconButton.filled(
                      onPressed: () {
                        ServiceLocator().get<IHapticService>().buttonTap();
                        _sendChat();
                      },
                      icon: Icon(Icons.send, size: f(18)),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
