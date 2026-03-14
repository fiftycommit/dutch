import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
import '../../services/notifications/in_app_notification_service.dart';
import '../../services/social/private_chat_service.dart';
import '../../utils/ui_constants.dart';

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
  // Fichier local affiché immédiatement pendant l'upload
  String? _localWallpaperPath;
  bool _wallpaperIsDark = true;
  DateTime? _friendReadAt;
  bool _friendIsTyping = false;
  StreamSubscription<ChatMeta>? _metaSub;

  // Pagination
  final List<ChatMessage> _olderMessages = [];
  bool _hasMoreMessages = true;
  bool _loadingMore = false;
  DocumentSnapshot? _oldestDoc;

  // Anti-scintillement : suivi du nombre de messages pour scroll conditionnel
  int _lastMessageCount = 0;

  // Messages optimistes (audio/image en cours d'upload)
  final List<ChatMessage> _pendingMessages = [];

  // Mode sélection
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

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
    InAppNotificationService.instance.activeChatFriendId = widget.friendUserId;
  }

  void _listenMeta() {
    _metaSub =
        _chatService.metaStream(_chatId, widget.friendUserId).listen((meta) {
      if (!mounted) return;
      final oldUrl = _wallpaperUrl;
      setState(() {
        _wallpaperUrl = meta.wallpaperUrl;
        _friendReadAt = meta.friendReadAt;
        _friendIsTyping = meta.friendIsTyping;
      });
      if (meta.wallpaperUrl != oldUrl) {
        _analyzeWallpaperBrightness(meta.wallpaperUrl);
      }
    });
  }

  Future<void> _analyzeLocalWallpaperBrightness(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final pixels = byteData.buffer.asUint8List();
      double totalLuminance = 0;
      int sampleCount = 0;
      final step = (pixels.length ~/ 4) > 500 ? (pixels.length ~/ 4) ~/ 500 : 1;
      for (int i = 0; i < pixels.length; i += step * 4) {
        final r = pixels[i] / 255.0;
        final g = pixels[i + 1] / 255.0;
        final b = pixels[i + 2] / 255.0;
        totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        sampleCount++;
      }
      final avgLuminance = sampleCount > 0 ? totalLuminance / sampleCount : 0.5;
      if (mounted) setState(() => _wallpaperIsDark = avgLuminance < 0.5);
    } catch (_) {
      if (mounted) setState(() => _wallpaperIsDark = true);
    }
  }

  Future<void> _analyzeWallpaperBrightness(String? url) async {
    if (url == null) {
      if (mounted) setState(() => _wallpaperIsDark = true);
      return;
    }
    try {
      final completer = Completer<ui.Image>();
      final provider = NetworkImage('$url&t=${url.hashCode}');
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (e, _) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final image = await completer.future;
      // Sample a small area to determine brightness
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final pixels = byteData.buffer.asUint8List();
      double totalLuminance = 0;
      int sampleCount = 0;
      // Sample every Nth pixel for performance
      final step = (pixels.length ~/ 4) > 500 ? (pixels.length ~/ 4) ~/ 500 : 1;
      for (int i = 0; i < pixels.length; i += step * 4) {
        final r = pixels[i] / 255.0;
        final g = pixels[i + 1] / 255.0;
        final b = pixels[i + 2] / 255.0;
        // Relative luminance (sRGB)
        totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        sampleCount++;
      }
      final avgLuminance = sampleCount > 0 ? totalLuminance / sampleCount : 0.5;
      if (mounted) {
        setState(() => _wallpaperIsDark = avgLuminance < 0.5);
      }
    } catch (_) {
      // On error, default to dark
      if (mounted) setState(() => _wallpaperIsDark = true);
    }
  }

  void _addPendingAudio(String localPath, int durationMs) {
    final pending = ChatMessage(
      id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myUserId,
      text: '',
      type: ChatMessageType.audio,
      mediaUrl: kIsWeb ? localPath : localPath,
      audioDurationMs: durationMs,
      timestamp: DateTime.now(),
    );
    setState(() => _pendingMessages.add(pending));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom();
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
    _typingDebounce?.cancel();
    if (typing) {
      _typingDebounce = Timer(const Duration(seconds: 4), () {
        _chatService.updateTyping(_chatId, _myUserId, false);
        _isTyping = false;
      });
    }
  }

  void _enterSelectionMode(String firstId) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(firstId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelectedForMe() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    for (final id in ids) {
      await _chatService.deleteMessageForMe(_chatId, id, _myUserId);
    }
  }

  Future<void> _deleteSelectedForAll(List<ChatMessage> allMessages) async {
    final ids = List<String>.from(_selectedIds);
    // Vérifier que tous les messages sélectionnés sont les miens
    final myMessages = allMessages
        .where((m) => ids.contains(m.id) && m.senderId == _myUserId)
        .map((m) => m.id)
        .toSet();
    final notMine = ids.where((id) => !myMessages.contains(id)).toList();
    if (notMine.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Seuls tes propres messages peuvent être supprimés pour tous.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    _exitSelectionMode();
    for (final id in ids) {
      await _chatService.deleteMessageForAll(_chatId, id);
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

    // Optimistic: afficher immédiatement le fichier local
    if (!kIsWeb) {
      setState(() => _localWallpaperPath = xfile!.path);
      _analyzeLocalWallpaperBrightness(xfile.path);
    }

    try {
      final ref =
          FirebaseStorage.instance.ref().child('chat_wallpapers/$_chatId.jpg');
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
      // Le stream Firestore mettra à jour _wallpaperUrl, on retire le local
      if (mounted) setState(() => _localWallpaperPath = null);
    } catch (e) {
      if (mounted) {
        setState(() => _localWallpaperPath = null);
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
    InAppNotificationService.instance.activeChatFriendId = null;
    _metaSub?.cancel();
    _typingDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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
        imageQuality: kIsWeb ? null : 50,
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
    final cs = MultiplayerColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
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
                color: cs.separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primary,
                child: const Icon(Icons.photo_library, color: Colors.white),
              ),
              title: Text('Bibliothèque photos',
                  style: TextStyle(color: cs.textPrimary)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.success,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: Text('Appareil photo',
                    style: TextStyle(color: cs.textPrimary)),
                onTap: () => _pickImage(ImageSource.camera),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAppBarMenu() {
    final cs = MultiplayerColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
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
                color: cs.separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primary,
                child: const Icon(Icons.wallpaper, color: Colors.white),
              ),
              title: Text('Changer le fond d\'écran',
                  style: TextStyle(color: cs.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickWallpaper();
              },
            ),
            if (_wallpaperUrl != null)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.danger,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                title: Text('Supprimer le fond d\'écran',
                    style: TextStyle(color: cs.textPrimary)),
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
    final cs = MultiplayerColors.of(context);
    final hasWallpaper = _wallpaperUrl != null || _localWallpaperPath != null;
    final wallpaperTextColor =
        hasWallpaper ? (_wallpaperIsDark ? Colors.white : Colors.black) : null;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        backgroundColor: cs.background,
        appBar:
            _selectionMode ? _buildSelectionAppBar(cs) : _buildNormalAppBar(cs),
        body: StreamBuilder<List<ChatMessage>>(
          stream: _chatService.messagesStream(_chatId, widget.friendUserId),
          builder: (context, snapshot) {
            final streamMessages = snapshot.data ?? [];
            final seenIds = <String>{};
            final allMessages = <ChatMessage>[];
            for (final m in [..._olderMessages, ...streamMessages]) {
              // Filtrer les messages supprimés
              if (m.deletedForAll) continue;
              if (m.deletedFor.contains(_myUserId)) continue;
              if (seenIds.add(m.id)) allMessages.add(m);
            }
            // Retirer les pending quand un vrai message audio arrive du stream
            if (_pendingMessages.isNotEmpty && streamMessages.isNotEmpty) {
              _pendingMessages.removeWhere((p) {
                return streamMessages.any((s) =>
                    s.type == p.type &&
                    s.senderId == _myUserId &&
                    s.audioDurationMs == p.audioDurationMs &&
                    s.timestamp.difference(p.timestamp).inSeconds.abs() < 30);
              });
            }
            // Ajouter les messages en attente à la fin
            allMessages.addAll(_pendingMessages);

            if (streamMessages.isNotEmpty &&
                _olderMessages.isEmpty &&
                streamMessages.first.snapshot != null) {
              _oldestDoc = streamMessages.first.snapshot;
            }

            // Scroll uniquement quand de nouveaux messages arrivent
            if (allMessages.length > _lastMessageCount &&
                _olderMessages.isEmpty) {
              _lastMessageCount = allMessages.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _scrollToBottom();
              });
              _chatService.markAsRead(_chatId, _myUserId);
            } else if (allMessages.length != _lastMessageCount) {
              _lastMessageCount = allMessages.length;
            }

            return Container(
              decoration: hasWallpaper
                  ? BoxDecoration(
                      image: DecorationImage(
                        image: _localWallpaperPath != null
                            ? FileImage(File(_localWallpaperPath!))
                                as ImageProvider
                            : NetworkImage(
                                '$_wallpaperUrl&t=${_wallpaperUrl.hashCode}',
                              ),
                        fit: BoxFit.cover,
                      ),
                    )
                  : BoxDecoration(color: cs.background),
              child: Column(
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _olderMessages.isEmpty &&
                      allMessages.isEmpty)
                    Expanded(
                      child: Center(
                          child: CircularProgressIndicator(color: cs.primary)),
                    )
                  else if (allMessages.isEmpty)
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: cs.surfaceHigh.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Envoie le premier message à ${widget.friendDisplayName} !',
                            style: TextStyle(
                                color: wallpaperTextColor ?? cs.textSecondary,
                                fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: _buildMessageList(
                          allMessages: allMessages,
                          cs: cs,
                          hasWallpaper: hasWallpaper,
                          wallpaperIsDark: _wallpaperIsDark),
                    ),
                  // Barre de suppression en mode sélection
                  if (_selectionMode)
                    _buildSelectionBar(cs, allMessages)
                  else
                    _InputBar(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSend: _send,
                      onPlusPressed: _showPlusMenu,
                      chatId: _chatId,
                      myUserId: _myUserId,
                      chatService: _chatService,
                      onMediaSent: _scrollToBottom,
                      onPendingAudio: _addPendingAudio,
                      cs: cs,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar(MultiplayerColorScheme cs) {
    return AppBar(
      backgroundColor: cs.appBar,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.friendDisplayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Row(
            children: [
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
        // Bouton de sélection dédié sur web
        if (kIsWeb)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Sélectionner des messages',
            onPressed: () => setState(() => _selectionMode = true),
          ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showAppBarMenu,
        ),
      ],
      elevation: 0,
    );
  }

  AppBar _buildSelectionAppBar(MultiplayerColorScheme cs) {
    return AppBar(
      backgroundColor: cs.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        _selectedIds.isEmpty
            ? 'Sélectionner'
            : '${_selectedIds.length} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      elevation: 0,
    );
  }

  Widget _buildSelectionBar(
      MultiplayerColorScheme cs, List<ChatMessage> allMessages) {
    final hasSelection = _selectedIds.isNotEmpty;
    final allMine = hasSelection &&
        allMessages
            .where((m) => _selectedIds.contains(m.id))
            .every((m) => m.senderId == _myUserId);

    return Container(
      color: cs.surface,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasSelection ? _deleteSelectedForMe : null,
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: const Text('Pour moi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.warning,
                side: BorderSide(color: cs.warning.withValues(alpha: 0.6)),
              ),
            ),
          ),
          if (allMine) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasSelection
                    ? () => _deleteSelectedForAll(allMessages)
                    : null,
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Pour tous'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.danger,
                  side: BorderSide(color: cs.danger.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageList({
    required List<ChatMessage> allMessages,
    required MultiplayerColorScheme cs,
    required bool hasWallpaper,
    required bool wallpaperIsDark,
  }) {
    final lastMyIndex =
        allMessages.lastIndexWhere((m) => m.senderId == _myUserId);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: allMessages.length +
          (_hasMoreMessages || _loadingMore ? 1 : 0) +
          (_friendIsTyping && !_selectionMode ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0 && (_hasMoreMessages || _loadingMore)) {
          if (_loadingMore) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                ),
              ),
            );
          }
          return TextButton(
            onPressed: _loadMore,
            child: Text(
              'Charger les messages précédents',
              style: TextStyle(color: cs.primary, fontSize: 13),
            ),
          );
        }

        final msgOffset = (_hasMoreMessages || _loadingMore) ? 1 : 0;

        if (!_selectionMode &&
            _friendIsTyping &&
            index == allMessages.length + msgOffset) {
          return _TypingBubble(cs: cs);
        }

        final msgIndex = index - msgOffset;
        if (msgIndex < 0 || msgIndex >= allMessages.length) {
          return const SizedBox.shrink();
        }
        final msg = allMessages[msgIndex];
        final isMe = msg.senderId == _myUserId;
        final isPending = msg.id.startsWith('pending_');
        final isLastMine = isMe && msgIndex == lastMyIndex;
        final isRead = isLastMine &&
            _friendReadAt != null &&
            _friendReadAt!.isAfter(msg.timestamp);
        final showDelivered = isLastMine && !isRead && !isPending;
        final isSelected = _selectedIds.contains(msg.id);

        return _MessageBubble(
          key: ValueKey(msg.id),
          message: msg,
          isMe: isMe,
          cs: cs,
          hasWallpaper: hasWallpaper,
          wallpaperIsDark: wallpaperIsDark,
          showReceipt: isRead,
          showDelivered: showDelivered,
          friendReadAt: isRead ? _friendReadAt : null,
          selectionMode: _selectionMode,
          isSelected: isSelected,
          onLongPress: () => _enterSelectionMode(msg.id),
          onTap: _selectionMode ? () => _toggleSelection(msg.id) : null,
        );
      },
    );
  }
}

// ─── Typing bubble ────────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.cs});
  final MultiplayerColorScheme cs;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _d1, _d2, _d3;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _d1 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4)));
    _d2 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.6)));
    _d3 = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.8)));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.receivedBubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(_d1.value, cs),
              const SizedBox(width: 4),
              _dot(_d2.value, cs),
              const SizedBox(width: 4),
              _dot(_d3.value, cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(double v, MultiplayerColorScheme cs) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(cs.separator, cs.primary, v),
        ),
      );
}

// ─── Message bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.cs,
    required this.hasWallpaper,
    this.wallpaperIsDark = true,
    this.showReceipt = false,
    this.showDelivered = false,
    this.friendReadAt,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onTap,
  });

  final ChatMessage message;
  final bool isMe;
  final MultiplayerColorScheme cs;
  final bool hasWallpaper;
  final bool wallpaperIsDark;
  final bool showReceipt;
  final bool showDelivered;
  final DateTime? friendReadAt;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  String _formatReadAt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24 && now.day == dt.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Lu à $h:$m';
    }
    const jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const mois = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.'
    ];
    return 'Lu ${jours[dt.weekday - 1]} ${dt.day} ${mois[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe
        ? cs.sentBubble
        : hasWallpaper
            ? cs.receivedBubble.withValues(alpha: 0.92)
            : cs.receivedBubble;

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? cs.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Checkbox côté gauche pour les messages reçus
            if (selectionMode && !isMe)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnimatedScale(
                  scale: selectionMode ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: _SelectionCircle(isSelected: isSelected, cs: cs),
                ),
              ),
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
                        style: TextStyle(
                            fontSize: 11,
                            color: hasWallpaper
                                ? (wallpaperIsDark
                                    ? Colors.white70
                                    : Colors.black54)
                                : cs.textSecondary),
                      ),
                    )
                  else if (showDelivered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, right: 2),
                      child: Text(
                        'Distribué',
                        style: TextStyle(
                            fontSize: 11,
                            color: hasWallpaper
                                ? (wallpaperIsDark
                                    ? Colors.white70
                                    : Colors.black54)
                                : cs.textSecondary),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ),
            ),
            // Checkbox côté droit pour mes messages
            if (selectionMode && isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AnimatedScale(
                  scale: selectionMode ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: _SelectionCircle(isSelected: isSelected, cs: cs),
                ),
              ),
          ],
        ),
      ),
    );

    return bubble;
  }

  Widget _bubbleContent(bool isMe, BuildContext context) {
    final textColor = isMe ? Colors.white : cs.textPrimary;
    final linkColor = isMe ? Colors.white70 : cs.primary;

    switch (message.type) {
      case ChatMessageType.image:
        final radius = BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        );
        return GestureDetector(
          onTap: () => _openFullScreen(context, message.mediaUrl ?? ''),
          child: ClipRRect(
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 180),
              child: Image.network(
                message.mediaUrl ?? '',
                fit: BoxFit.cover,
                width: 220,
                cacheWidth: 440,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        width: 220,
                        height: 140,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
              ),
            ),
          ),
        );

      case ChatMessageType.audio:
        return _AudioBubble(
          mediaUrl: message.mediaUrl ?? '',
          durationMs: message.audioDurationMs ?? 0,
          isMe: isMe,
          cs: cs,
        );

      case ChatMessageType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _LinkifiedText(
            text: message.text,
            textColor: textColor,
            linkColor: linkColor,
          ),
        );
    }
  }
}

// ─── Cercle de sélection ─────────────────────────────────────────────────────

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.isSelected, required this.cs});
  final bool isSelected;
  final MultiplayerColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? cs.primary : Colors.transparent,
        border: Border.all(
          color: isSelected ? cs.primary : cs.textSecondary,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
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
  const _LinkifiedText({
    required this.text,
    required this.textColor,
    required this.linkColor,
  });

  final String text;
  final Color textColor;
  final Color linkColor;

  static final _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

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
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
  const _AudioBubble({
    required this.mediaUrl,
    required this.durationMs,
    required this.isMe,
    required this.cs,
  });

  final String mediaUrl;
  final int durationMs;
  final bool isMe;
  final MultiplayerColorScheme cs;

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
      final url = widget.mediaUrl;
      // Fichier local (pending) vs URL réseau
      final source = url.startsWith('http')
          ? UrlSource(url)
          : kIsWeb
              ? UrlSource(url)
              : DeviceFileSource(url);
      await _player.play(source);
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
    final color = widget.isMe ? Colors.white : widget.cs.primary;
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
    required this.onPendingAudio,
    required this.cs,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final String chatId;
  final String myUserId;
  final PrivateChatService chatService;
  final VoidCallback onMediaSent;
  final void Function(String localPath, int durationMs) onPendingAudio;
  final MultiplayerColorScheme cs;

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
  int _recordDurationMs = 0;
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

      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
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
    _recordDurationMs =
        DateTime.now().difference(_recordStart!).inMilliseconds;
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
    final durationMs = _recordDurationMs;
    await _previewPlayer.stop();
    setState(() {
      _recordState = _RecordState.idle;
      _previewPlaying = false;
    });
    // Optimistic: afficher le message audio immédiatement
    widget.onPendingAudio(path, durationMs);
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
      final source =
          kIsWeb ? UrlSource(_recordPath!) : DeviceFileSource(_recordPath!);
      await _previewPlayer.play(source);
      setState(() => _previewPlaying = true);
    }
  }

  String _fmtSeconds(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return Container(
      color: cs.inputBar,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: _buildContent(cs),
    );
  }

  Widget _buildContent(MultiplayerColorScheme cs) {
    switch (_recordState) {
      case _RecordState.recording:
        return _buildRecordingBar(cs);
      case _RecordState.preview:
        return _buildPreviewBar(cs);
      case _RecordState.idle:
        return _buildIdleBar(cs);
    }
  }

  Widget _buildRecordingBar(MultiplayerColorScheme cs) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 600),
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Icon(Icons.mic, color: cs.danger, size: 24),
          ),
          const SizedBox(width: 10),
          Text(
            _fmtSeconds(_elapsedSeconds),
            style: TextStyle(
                color: cs.danger, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Appuie pour arrêter',
                style: TextStyle(color: cs.textSecondary, fontSize: 12)),
          ),
          GestureDetector(
            onTap: _cancelRecord,
            child:
                Icon(Icons.delete_outline, color: cs.textSecondary, size: 22),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _stopRecord,
            child: Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: cs.danger, shape: BoxShape.circle),
              child: const Icon(Icons.stop, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBar(MultiplayerColorScheme cs) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceHigh,
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
              color: cs.primary,
              size: 34,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.graphic_eq, color: cs.textSecondary, size: 20),
          const SizedBox(width: 4),
          Text(_fmtSeconds(_elapsedSeconds),
              style: TextStyle(color: cs.textSecondary, fontSize: 12)),
          const Spacer(),
          GestureDetector(
            onTap: _cancelRecord,
            child: Icon(Icons.delete_outline, color: cs.danger, size: 22),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendAudio,
            child: Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: cs.success, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleBar(MultiplayerColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // + button
        GestureDetector(
          onTap: widget.onPlusPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add, color: cs.textPrimary, size: 22),
          ),
        ),
        const SizedBox(width: 8),

        // TextField
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
              style: TextStyle(color: cs.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: TextStyle(color: cs.textSecondary, fontSize: 13),
                filled: true,
                fillColor: cs.surfaceHigh,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send / mic button
        if (_hasText)
          GestureDetector(
            onTap: widget.onSend,
            child: Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child:
                  const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
            ),
          )
        else
          GestureDetector(
            onTap: _startRecord,
            child: Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: cs.surfaceHigh, shape: BoxShape.circle),
              child: Icon(Icons.mic, color: cs.primary, size: 20),
            ),
          ),
      ],
    );
  }
}
