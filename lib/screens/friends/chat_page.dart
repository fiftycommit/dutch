import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
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

  // Meta (wallpaper, read receipts, typing)
  String? _wallpaperUrl;
  DateTime? _friendReadAt;
  bool _friendIsTyping = false;
  StreamSubscription<ChatMeta>? _metaSub;

  // Pagination
  final List<ChatMessage> _olderMessages = [];
  bool _hasMoreMessages = true;
  bool _loadingMore = false;
  DocumentSnapshot? _oldestDoc;

  // Typing debounce
  Timer? _typingDebounce;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _chatService = PrivateChatService();
    _myUserId = context.read<AuthProvider>().user!.id;
    _chatId = PrivateChatService.chatId(_myUserId, widget.friendUserId);
    _listenMeta();
    _chatService.markAsRead(_chatId, _myUserId);
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onTextChanged);
  }

  void _listenMeta() {
    _metaSub = _chatService
        .metaStream(_chatId, widget.friendUserId)
        .listen((meta) {
      if (!mounted) return;
      if (meta.wallpaperUrl != _wallpaperUrl && meta.wallpaperUrl != null) {
        imageCache.evict(NetworkImage(meta.wallpaperUrl!));
        imageCache.clear();
      }
      setState(() {
        _wallpaperUrl = meta.wallpaperUrl;
        _friendReadAt = meta.friendReadAt;
        _friendIsTyping = meta.friendIsTyping;
      });
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 60 &&
        !_loadingMore &&
        _hasMoreMessages &&
        _oldestDoc != null) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _oldestDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final older = await _chatService.loadMoreMessages(
          _chatId, widget.friendUserId, _oldestDoc!);
      if (older.isEmpty) {
        setState(() => _hasMoreMessages = false);
      } else {
        setState(() {
          _olderMessages.insertAll(0, older);
          if (older.first.snapshot != null) {
            _oldestDoc = older.first.snapshot;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onTextChanged() {
    final typing = _controller.text.trim().isNotEmpty;
    if (typing != _isTyping) {
      _isTyping = typing;
      _chatService.updateTyping(_chatId, _myUserId, typing);
    }
    // Auto-clear typing après 4s d'inactivité
    _typingDebounce?.cancel();
    if (typing) {
      _typingDebounce = Timer(const Duration(seconds: 4), () {
        _chatService.updateTyping(_chatId, _myUserId, false);
        _isTyping = false;
      });
    }
  }

  Future<void> _pickWallpaper() async {
    final picker = ImagePicker();
    XFile? xfile;
    try {
      xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: kIsWeb ? null : 60,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sélection image: $e')),
        );
      }
      return;
    }
    if (xfile == null) return;

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_wallpapers/$_chatId.jpg');
      if (kIsWeb) {
        final bytes = await xfile.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(
            File(xfile.path), SettableMetadata(contentType: 'image/jpeg'));
      }
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('private_chats')
          .doc(_chatId)
          .set({'wallpaperUrl': url}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur upload: $e')),
        );
      }
    }
  }

  Future<void> _removeWallpaper() async {
    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(_chatId)
        .update({'wallpaperUrl': FieldValue.delete()});
    try {
      await FirebaseStorage.instance
          .ref()
          .child('chat_wallpapers/$_chatId.jpg')
          .delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _metaSub?.cancel();
    _typingDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Effacer le typing au départ
    _chatService.updateTyping(_chatId, _myUserId, false);
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    _typingDebounce?.cancel();
    _chatService.updateTyping(_chatId, _myUserId, false);
    _isTyping = false;
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
    XFile? xfile;
    try {
      xfile = await picker.pickImage(
        source: source,
        imageQuality: kIsWeb ? null : 50, // compression agressive
        maxWidth: 1200,
        maxHeight: 1200,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sélection photo: $e')),
        );
      }
      return;
    }
    if (xfile == null) return;

    try {
      if (kIsWeb) {
        final bytes = await xfile.readAsBytes();
        await _chatService.sendImageBytes(_chatId, _myUserId, bytes);
      } else {
        final file = File(xfile.path);
        await _chatService.sendImage(_chatId, _myUserId, file);
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur envoi photo: $e')),
        );
      }
    }
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
            if (!kIsWeb)
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
            if (_wallpaperUrl != null)
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
    final hasWallpaper = _wallpaperUrl != null;

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
          key: ValueKey(_wallpaperUrl),
          decoration: hasWallpaper
              ? BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      '$_wallpaperUrl&t=${_wallpaperUrl.hashCode}',
                    ),
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
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _olderMessages.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF4F46E5)),
                      );
                    }

                    final streamMessages = snapshot.data ?? [];

                    // Fusionner olderMessages + streamMessages (dédupliqués par id)
                    final seenIds = <String>{};
                    final allMessages = <ChatMessage>[];
                    for (final m in [..._olderMessages, ...streamMessages]) {
                      if (seenIds.add(m.id)) allMessages.add(m);
                    }

                    // Stocker le doc le plus ancien pour la pagination
                    if (streamMessages.isNotEmpty &&
                        _olderMessages.isEmpty &&
                        streamMessages.first.snapshot != null) {
                      _oldestDoc = streamMessages.first.snapshot;
                    }

                    if (allMessages.isEmpty) {
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
                      if (_olderMessages.isEmpty) _scrollToBottom();
                    });
                    _chatService.markAsRead(_chatId, _myUserId);

                    final lastMyIndex = allMessages.lastIndexWhere(
                        (m) => m.senderId == _myUserId);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      itemCount:
                          allMessages.length +
                          (_hasMoreMessages || _loadingMore ? 1 : 0) +
                          (_friendIsTyping ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Header : load more ou spinner
                        if (index == 0 &&
                            (_hasMoreMessages || _loadingMore)) {
                          if (_loadingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(
                                  child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF4F46E5)),
                              )),
                            );
                          }
                          return TextButton(
                            onPressed: _loadMore,
                            child: const Text('Charger les messages précédents',
                                style: TextStyle(
                                    color: Color(0xFF4F46E5), fontSize: 13)),
                          );
                        }

                        final msgOffset =
                            (_hasMoreMessages || _loadingMore) ? 1 : 0;

                        // Typing indicator en bas
                        if (_friendIsTyping &&
                            index == allMessages.length + msgOffset) {
                          return _TypingBubble(hasWallpaper: hasWallpaper);
                        }

                        final msgIndex = index - msgOffset;
                        final msg = allMessages[msgIndex];
                        final isMe = msg.senderId == _myUserId;
                        final showReceipt = isMe &&
                            msgIndex == lastMyIndex &&
                            _friendReadAt != null &&
                            _friendReadAt!.isAfter(msg.timestamp);
                        return _MessageBubble(
                            message: msg,
                            isMe: isMe,
                            hasWallpaper: hasWallpaper,
                            showReceipt: showReceipt,
                            friendReadAt:
                                showReceipt ? _friendReadAt : null);
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

// ─── Typing bubble ────────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.hasWallpaper});
  final bool hasWallpaper;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1, _dot2, _dot3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _dot1 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4)));
    _dot2 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.6)));
    _dot3 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.hasWallpaper
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: widget.hasWallpaper ? 0.18 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(_dot1.value),
              const SizedBox(width: 4),
              _dot(_dot2.value),
              const SizedBox(width: 4),
              _dot(_dot3.value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(double v) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
              const Color(0xFFD1D5DB), const Color(0xFF4F46E5), v),
        ),
      );
}

// ─── Message bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.hasWallpaper,
    this.showReceipt = false,
    this.friendReadAt,
  });

  final ChatMessage message;
  final bool isMe;
  final bool hasWallpaper;
  final bool showReceipt;
  final DateTime? friendReadAt;

  String _formatReadAt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24 && now.day == dt.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Lu à $h:$m';
    }
    const jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const mois = ['jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin',
        'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    return 'Lu ${jours[dt.weekday - 1]} ${dt.day} ${mois[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
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
                  color: Colors.black
                      .withValues(alpha: hasWallpaper ? 0.18 : 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _bubbleContent(isMe, context),
          ),
          if (showReceipt && friendReadAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 2),
              child: Text(
                _formatReadAt(friendReadAt!),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _bubbleContent(bool isMe, BuildContext context) {
    switch (message.type) {
      case ChatMessageType.image:
        final radius = BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        );
        return GestureDetector(
          onTap: () => _openFullScreen(context, message.mediaUrl ?? ''),
          child: ClipRRect(
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 220,
                maxHeight: 180,
              ),
              child: Image.network(
                message.mediaUrl ?? '',
                fit: BoxFit.cover,
                width: 220,
                cacheWidth: 440, // 2x pour les écrans Retina
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        width: 220,
                        height: 140,
                        child: Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      ),
              ),
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

void _openFullScreen(BuildContext context, String url) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (ctx, _, __) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    ),
  );
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

enum _RecordState { idle, recording, preview }

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
  _RecordState _recordState = _RecordState.idle;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();
  DateTime? _recordStart;
  String? _recordPath;
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final has = widget.controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewPlaying = false);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _previewPlayer.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startRecord() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission micro refusée')),
          );
        }
        return;
      }

      String path;
      if (kIsWeb) {
        path = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      _recordPath = path;

      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _elapsedSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
      setState(() {
        _recordState = _RecordState.recording;
        _recordStart = DateTime.now();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur micro: $e')),
        );
      }
    }
  }

  Future<void> _stopRecord() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path != null) _recordPath = path;
    setState(() => _recordState = _RecordState.preview);
  }

  Future<void> _cancelRecord() async {
    _timer?.cancel();
    await _recorder.stop();
    await _previewPlayer.stop();
    setState(() {
      _recordState = _RecordState.idle;
      _previewPlaying = false;
    });
  }

  Future<void> _sendAudio() async {
    final path = _recordPath;
    if (path == null) return;
    final durationMs =
        DateTime.now().difference(_recordStart!).inMilliseconds;
    await _previewPlayer.stop();
    setState(() {
      _recordState = _RecordState.idle;
      _previewPlaying = false;
    });
    if (kIsWeb) {
      await widget.chatService
          .sendAudioFromUrl(widget.chatId, widget.myUserId, path, durationMs);
    } else {
      await widget.chatService
          .sendAudio(widget.chatId, widget.myUserId, File(path), durationMs);
    }
    widget.onMediaSent();
  }

  Future<void> _togglePreview() async {
    if (_previewPlaying) {
      await _previewPlayer.pause();
      setState(() => _previewPlaying = false);
    } else {
      final source = kIsWeb
          ? UrlSource(_recordPath!)
          : DeviceFileSource(_recordPath!);
      await _previewPlayer.play(source);
      setState(() => _previewPlaying = true);
    }
  }

  String _fmtSeconds(int s) {
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
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
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_recordState) {
      case _RecordState.recording:
        return _buildRecordingBar();
      case _RecordState.preview:
        return _buildPreviewBar();
      case _RecordState.idle:
        return _buildIdleBar();
    }
  }

  Widget _buildRecordingBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: const Icon(Icons.mic, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 10),
          Text(
            _fmtSeconds(_elapsedSeconds),
            style: const TextStyle(
                color: Colors.red, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Appuie pour arrêter',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          ),
          GestureDetector(
            onTap: _cancelRecord,
            child: const Icon(Icons.delete_outline,
                color: Color(0xFF9CA3AF), size: 22),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _stopRecord,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stop, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePreview,
            child: Icon(
              _previewPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: const Color(0xFF21a1f4),
              size: 34,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.graphic_eq, color: Color(0xFF6B7280), size: 20),
          const SizedBox(width: 4),
          Text(
            _fmtSeconds(_elapsedSeconds),
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _cancelRecord,
            child: const Icon(Icons.delete_outline,
                color: Color(0xFFEF4444), size: 22),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendAudio,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF4feb69),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // + button
        GestureDetector(
          onTap: widget.onPlusPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFD1D5DB),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: Color(0xFF111827), size: 22),
          ),
        ),
        const SizedBox(width: 8),

        // Text field with Enter = send, Shift+Enter = newline
        Expanded(
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  !HardwareKeyboard.instance.isShiftPressed) {
                if (_hasText) widget.onSend();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style:
                  const TextStyle(color: Color(0xFF111827), fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13),
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
        ),
        const SizedBox(width: 8),

        // Right button: send (green) or mic (blue)
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
            onTap: _startRecord,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF21a1f4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
      ],
    );
  }
}
