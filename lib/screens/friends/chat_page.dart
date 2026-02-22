import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/social/private_chat_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.friendUserId,
    required this.friendDisplayName,
  });

  final String friendUserId;
  final String friendDisplayName;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final PrivateChatService _chatService;
  late final String _myUserId;
  late final String _chatId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  String? _wallpaperPath;

  @override
  void initState() {
    super.initState();
    _chatService = PrivateChatService();
    _myUserId = context.read<AuthProvider>().user!.id;
    _chatId = PrivateChatService.chatId(_myUserId, widget.friendUserId);
    _loadWallpaper();
  }

  Future<void> _loadWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('wallpaper_$_chatId');
    if (path != null && File(path).existsSync()) {
      setState(() => _wallpaperPath = path);
    }
  }

  Future<void> _pickWallpaper() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    // Copier dans le dossier app pour que ça persiste
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/wallpaper_$_chatId.jpg');
    await File(xfile.path).copy(dest.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper_$_chatId', dest.path);
    setState(() => _wallpaperPath = dest.path);
  }

  Future<void> _removeWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallpaper_$_chatId');
    setState(() => _wallpaperPath = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    await _chatService.sendMessage(
        _chatId, _myUserId, text, widget.friendUserId);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;
    final file = File(xfile.path);
    await _chatService.sendImage(_chatId, _myUserId, file);
    _scrollToBottom();
  }

  void _showPlusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF4F46E5),
                child: Icon(Icons.photo_library, color: Colors.white),
              ),
              title: const Text('Bibliothèque photos'),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF10B981),
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: const Text('Appareil photo'),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAppBarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF8B5CF6),
                child: Icon(Icons.wallpaper, color: Colors.white),
              ),
              title: const Text('Changer le fond d\'écran'),
              onTap: () {
                Navigator.pop(context);
                _pickWallpaper();
              },
            ),
            if (_wallpaperPath != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEF4444),
                  child: Icon(Icons.delete_outline, color: Colors.white),
                ),
                title: const Text('Supprimer le fond d\'écran'),
                onTap: () {
                  Navigator.pop(context);
                  _removeWallpaper();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasWallpaper = _wallpaperPath != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.friendDisplayName,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              Row(
                children: const [
                  Icon(Icons.lock, size: 10, color: Color(0xFFBFDBFE)),
                  SizedBox(width: 3),
                  Text(
                    'Messagerie sécurisée',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBFDBFE),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showAppBarMenu,
            ),
          ],
          elevation: 0,
        ),
        body: Container(
          decoration: hasWallpaper
              ? BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(_wallpaperPath!)),
                    fit: BoxFit.cover,
                  ),
                )
              : const BoxDecoration(color: Color(0xFFF0F2F5)),
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _chatService.messagesStream(
                      _chatId, widget.friendUserId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF4F46E5)),
                      );
                    }
                    final messages = snapshot.data ?? [];
                    if (messages.isEmpty) {
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Envoie le premier message à ${widget.friendDisplayName} !',
                            style: TextStyle(
                              color: hasWallpaper
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToBottom();
                    });
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == _myUserId;
                        return _MessageBubble(
                            message: msg,
                            isMe: isMe,
                            hasWallpaper: hasWallpaper);
                      },
                    );
                  },
                ),
              ),
              _InputBar(
                controller: _controller,
                focusNode: _focusNode,
                onSend: _send,
                onPlusPressed: _showPlusMenu,
                chatId: _chatId,
                myUserId: _myUserId,
                chatService: _chatService,
                onMediaSent: _scrollToBottom,
                hasWallpaper: hasWallpaper,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Message bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message, required this.isMe, required this.hasWallpaper});

  final ChatMessage message;
  final bool isMe;
  final bool hasWallpaper;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF4F46E5)
              : hasWallpaper
                  ? Colors.white.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hasWallpaper ? 0.18 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _bubbleContent(isMe),
      ),
    );
  }

  Widget _bubbleContent(bool isMe) {
    switch (message.type) {
      case ChatMessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          child: Image.network(
            message.mediaUrl ?? '',
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const SizedBox(
                    height: 120,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
          ),
        );

      case ChatMessageType.audio:
        return _AudioBubble(
            mediaUrl: message.mediaUrl ?? '',
            durationMs: message.audioDurationMs ?? 0,
            isMe: isMe);

      case ChatMessageType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _LinkifiedText(
            text: message.text,
            textColor: isMe ? Colors.white : Colors.black87,
            linkColor: isMe ? Colors.white70 : const Color(0xFF4F46E5),
          ),
        );
    }
  }
}

// ─── Linkified text ───────────────────────────────────────────────────────────

class _LinkifiedText extends StatelessWidget {
  const _LinkifiedText(
      {required this.text,
      required this.textColor,
      required this.linkColor});

  final String text;
  final Color textColor;
  final Color linkColor;

  static final _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text,
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4));
    }

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, m.start),
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
        ));
      }
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication),
          child: Text(
            url,
            style: TextStyle(
              color: linkColor,
              fontSize: 14,
              height: 1.4,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            ),
          ),
        ),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

// ─── Audio bubble ─────────────────────────────────────────────────────────────

class _AudioBubble extends StatefulWidget {
  const _AudioBubble(
      {required this.mediaUrl,
      required this.durationMs,
      required this.isMe});

  final String mediaUrl;
  final int durationMs;
  final bool isMe;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(widget.mediaUrl));
      setState(() => _playing = true);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    }
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : const Color(0xFF4F46E5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: color,
              size: 36,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.graphic_eq, color: color, size: 20),
              Text(_fmt(widget.durationMs),
                  style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onPlusPressed,
    required this.chatId,
    required this.myUserId,
    required this.chatService,
    required this.onMediaSent,
    required this.hasWallpaper,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final String chatId;
  final String myUserId;
  final PrivateChatService chatService;
  final VoidCallback onMediaSent;
  final bool hasWallpaper;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;
  bool _recording = false;
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordStart;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final has = widget.controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecord() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() {
      _recording = true;
      _recordStart = DateTime.now();
    });
  }

  Future<void> _stopRecord() async {
    final path = await _recorder.stop();
    final durationMs =
        DateTime.now().difference(_recordStart!).inMilliseconds;
    setState(() => _recording = false);
    if (path == null) return;
    await widget.chatService
        .sendAudio(widget.chatId, widget.myUserId, File(path), durationMs);
    widget.onMediaSent();
  }

  Future<void> _cancelRecord() async {
    await _recorder.stop();
    setState(() => _recording = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // + button — même couleur que le textField, icône noire
          GestureDetector(
            onTap: widget.onPlusPressed,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.black, size: 22),
            ),
          ),
          const SizedBox(width: 8),

          // Text field — compact, même hauteur que les boutons
          Expanded(
            child: _recording
                ? Container(
                    height: 36,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text('Enregistrement…',
                              style: TextStyle(
                                  color: Color(0xFF374151), fontSize: 13)),
                        ),
                        GestureDetector(
                          onTap: _cancelRecord,
                          child: const Icon(Icons.delete_outline,
                              color: Color(0xFF9CA3AF), size: 18),
                        ),
                      ],
                    ),
                  )
                : TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                        color: Color(0xFF111827), fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle:
                          const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),

          // Bouton droit : vert si peut envoyer, bleu (mic) sinon
          if (_hasText)
            GestureDetector(
              onTap: widget.onSend,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF4feb69),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward,
                    color: Colors.white, size: 20),
              ),
            )
          else
            GestureDetector(
              onLongPressStart: (_) => _startRecord(),
              onLongPressEnd: (_) => _stopRecord(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _recording
                      ? Colors.red
                      : const Color(0xFF21a1f4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  color: _recording ? Colors.white : Colors.black,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
