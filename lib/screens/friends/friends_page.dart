import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../utils/ui_constants.dart';
import '../../services/social/friends_api_service.dart';
import '../../core/service_locator.dart';
import '../../core/interfaces/i_haptic_service.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  late final FriendsApiService _friendsApi;
  late final TabController _tabController;

  List<FriendInfo> _friends = [];
  List<FriendRequestInfo> _incomingRequests = [];
  List<FriendRequestInfo> _outgoingRequests = [];
  List<BlockedUserInfo> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    final authProvider = context.read<AuthProvider>();
    _friendsApi = FriendsApiService(authProvider.authService);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _friendsApi.getFriends(),
      _friendsApi.getRequests(),
      _friendsApi.getBlockedUsers(),
    ]);
    if (!mounted) return;
    final friends = results[0] as List<FriendInfo>;
    final requests = results[1] as ({
      List<FriendRequestInfo> incoming,
      List<FriendRequestInfo> outgoing
    });
    final blocked = results[2] as List<BlockedUserInfo>;
    setState(() {
      _friends = friends;
      _incomingRequests = requests.incoming;
      _outgoingRequests = requests.outgoing;
      _blocked = blocked;
      _loading = false;
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? MultiplayerColors.of(context).danger
          : MultiplayerColors.of(context).success,
    ));
  }

  Future<void> _confirmRemoveFriend(FriendInfo friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet ami ?'),
        content: Text('${friend.displayName} sera retiré de ta liste d\'amis.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _friendsApi.removeFriend(friend.userId);
    _showSnackBar(
      result.success
          ? '${friend.displayName} supprimé.'
          : (result.error ?? 'Erreur lors de la suppression.'),
      isError: !result.success,
    );
    if (result.success) unawaited(_loadData());
  }

  Future<void> _confirmBlockFriend(FriendInfo friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquer cet utilisateur ?'),
        content: Text(
            '${friend.displayName} sera bloqué et retiré de ta liste d\'amis.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _friendsApi.blockUser(friend.userId);
    _showSnackBar(
      result.success
          ? '${friend.displayName} bloqué.'
          : (result.error ?? 'Erreur lors du blocage.'),
      isError: !result.success,
    );
    if (result.success) unawaited(_loadData());
  }

  void _openFriendActions(FriendInfo friend) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: MultiplayerColors.of(context).separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFEEF2FF),
                  child: Text(
                    friend.displayName.isNotEmpty
                        ? friend.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  friend.displayName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '@${friend.username}',
                  style: TextStyle(
                      color: MultiplayerColors.of(context).textSecondary,
                      fontSize: 14),
                ),
                const SizedBox(height: 20),
                _BottomSheetAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message',
                  color: MultiplayerColors.of(context).primary,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.push(
                      '/friends/chat/${friend.userId}',
                      extra: friend.displayName,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _BottomSheetAction(
                  icon: Icons.person_remove_outlined,
                  label: 'Supprimer',
                  color: MultiplayerColors.of(context).warning,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    unawaited(_confirmRemoveFriend(friend));
                  },
                ),
                const SizedBox(height: 8),
                _BottomSheetAction(
                  icon: Icons.block_rounded,
                  label: 'Bloquer',
                  color: MultiplayerColors.of(context).danger,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    unawaited(_confirmBlockFriend(friend));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddFriendDialog() async {
    final controller = TextEditingController();
    String? error;
    bool searching = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          Future<void> onSearch() async {
            final username = controller.text.trim();
            if (username.isEmpty) {
              setLocal(() => error = 'Entre un nom d\'utilisateur.');
              return;
            }
            setLocal(() {
              error = null;
              searching = true;
            });
            final result = await _friendsApi.lookupUserByUsername(username);
            if (!dialogCtx.mounted) return;
            if (!result.exists || result.user == null) {
              setLocal(() {
                error = result.error ?? 'Utilisateur introuvable.';
                searching = false;
              });
              return;
            }
            final sendResult =
                await _friendsApi.sendRequest(result.user!.username);
            if (!dialogCtx.mounted) return;
            Navigator.of(dialogCtx).pop();
            _showSnackBar(
              sendResult.success
                  ? 'Demande envoyée à ${result.user!.displayName}.'
                  : (sendResult.error ?? 'Erreur lors de l\'envoi.'),
              isError: !sendResult.success,
            );
            if (sendResult.success) unawaited(_loadData());
          }

          return AlertDialog(
            title: const Text('Ajouter un ami'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              onSubmitted: (_) => searching ? null : onSearch(),
              decoration: InputDecoration(
                prefixText: '@',
                hintText: 'nom_utilisateur',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: searching
                    ? null
                    : () {
                        ServiceLocator().get<IHapticService>().buttonTap();
                        onSearch();
                      },
                child: searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Rechercher'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          color: MultiplayerColors.of(context).background,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                              color: MultiplayerColors.of(context).primary),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _FriendsTab(
                              friends: _friends,
                              onTap: _openFriendActions,
                              onAddFriend: _openAddFriendDialog,
                            ),
                            _RequestsTab(
                              incoming: _incomingRequests,
                              outgoing: _outgoingRequests,
                              friendsApi: _friendsApi,
                              onReload: _loadData,
                              onShowSnackBar: _showSnackBar,
                            ),
                            _BlockedTab(
                              blocked: _blocked,
                              friendsApi: _friendsApi,
                              onReload: _loadData,
                              onShowSnackBar: _showSnackBar,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Material(
                color: MultiplayerColors.of(context).surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () async {
                    final didPop = await Navigator.of(context).maybePop();
                    if (!didPop && mounted) context.go('/multiplayer');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.arrow_back,
                        size: 24,
                        color: MultiplayerColors.of(context).textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Mes Amis',
                style: TextStyle(
                  color: MultiplayerColors.of(context).textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _loadData,
                icon: Icon(Icons.refresh_rounded,
                    color: MultiplayerColors.of(context).primary),
                tooltip: 'Rafraîchir',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: MultiplayerColors.of(context).primary,
            unselectedLabelColor: MultiplayerColors.of(context).textSecondary,
            indicatorColor: MultiplayerColors.of(context).primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              const Tab(
                icon: Icon(Icons.group_outlined, size: 20),
                text: 'Amis',
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_add_outlined, size: 20),
                    const SizedBox(width: 4),
                    const Text('Demandes'),
                    if (_incomingRequests.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_incomingRequests.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(
                icon: Icon(Icons.block_rounded, size: 20),
                text: 'Bloqués',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Onglet Amis
// ─────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({
    required this.friends,
    required this.onTap,
    required this.onAddFriend,
  });

  final List<FriendInfo> friends;
  final void Function(FriendInfo) onTap;
  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_off_outlined,
                size: 64, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            const Text(
              'Aucun ami pour l\'instant.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddFriend,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Ajouter un ami'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: friends.length + 1,
      itemBuilder: (context, index) {
        if (index == friends.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: onAddFriend,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Ajouter un ami'),
              ),
            ),
          );
        }
        final friend = friends[index];
        return _FriendTile(friend: friend, onTap: () => onTap(friend));
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, required this.onTap});

  final FriendInfo friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = MultiplayerColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.separator),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: cs.surfaceHigh,
          child: Text(
            friend.displayName.isNotEmpty
                ? friend.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ),
        title: Text(
          friend.displayName,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: cs.textPrimary),
        ),
        subtitle: Text(
          '@${friend.username}',
          style: TextStyle(color: cs.textSecondary, fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (friend.isOnline)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.success,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: cs.separator),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Onglet Demandes
// ─────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.incoming,
    required this.outgoing,
    required this.friendsApi,
    required this.onReload,
    required this.onShowSnackBar,
  });

  final List<FriendRequestInfo> incoming;
  final List<FriendRequestInfo> outgoing;
  final FriendsApiService friendsApi;
  final Future<void> Function() onReload;
  final void Function(String, {bool isError}) onShowSnackBar;

  Future<void> _accept(BuildContext context, FriendRequestInfo req) async {
    final result = await friendsApi.acceptRequest(req.requestId);
    onShowSnackBar(
      result.success
          ? '${req.displayName} ajouté en ami !'
          : (result.error ?? 'Erreur lors de l\'acceptation.'),
      isError: !result.success,
    );
    if (result.success) unawaited(onReload());
  }

  Future<void> _reject(BuildContext context, FriendRequestInfo req) async {
    final result = await friendsApi.rejectRequest(req.requestId);
    onShowSnackBar(
      result.success
          ? 'Demande refusée.'
          : (result.error ?? 'Erreur lors du refus.'),
      isError: !result.success,
    );
    if (result.success) unawaited(onReload());
  }

  Future<void> _cancel(BuildContext context, FriendRequestInfo req) async {
    final result = await friendsApi.cancelRequest(req.requestId);
    onShowSnackBar(
      result.success
          ? 'Demande annulée.'
          : (result.error ?? 'Erreur lors de l\'annulation.'),
      isError: !result.success,
    );
    if (result.success) unawaited(onReload());
  }

  @override
  Widget build(BuildContext context) {
    if (incoming.isEmpty && outgoing.isEmpty) {
      return Center(
        child: Text(
          'Aucune demande en attente.',
          style: TextStyle(
              color: MultiplayerColors.of(context).textSecondary, fontSize: 16),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (incoming.isNotEmpty) ...[
          const _SectionHeader(label: 'Reçues'),
          ...incoming.map((req) => _RequestTile(
                info: req,
                isIncoming: true,
                onAccept: () => _accept(context, req),
                onRejectOrCancel: () => _reject(context, req),
              )),
          const SizedBox(height: 12),
        ],
        if (outgoing.isNotEmpty) ...[
          const _SectionHeader(label: 'Envoyées'),
          ...outgoing.map((req) => _RequestTile(
                info: req,
                isIncoming: false,
                onAccept: null,
                onRejectOrCancel: () => _cancel(context, req),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: MultiplayerColors.of(context).textSecondary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.info,
    required this.isIncoming,
    required this.onAccept,
    required this.onRejectOrCancel,
  });

  final FriendRequestInfo info;
  final bool isIncoming;
  final VoidCallback? onAccept;
  final VoidCallback onRejectOrCancel;

  @override
  Widget build(BuildContext context) {
    final cs = MultiplayerColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.separator),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.surfaceHigh,
            child: Text(
              info.displayName.isNotEmpty
                  ? info.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.displayName,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.textPrimary)),
                Text('@${info.username}',
                    style: TextStyle(color: cs.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (isIncoming) ...[
            IconButton(
              onPressed: onAccept,
              icon: Icon(Icons.check_circle_outline_rounded, color: cs.success),
              tooltip: 'Accepter',
            ),
            IconButton(
              onPressed: onRejectOrCancel,
              icon: Icon(Icons.cancel_outlined, color: cs.danger),
              tooltip: 'Refuser',
            ),
          ] else
            TextButton(
              onPressed: onRejectOrCancel,
              child: Text('Annuler', style: TextStyle(color: cs.textSecondary)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Onglet Bloqués
// ─────────────────────────────────────────────

class _BlockedTab extends StatelessWidget {
  const _BlockedTab({
    required this.blocked,
    required this.friendsApi,
    required this.onReload,
    required this.onShowSnackBar,
  });

  final List<BlockedUserInfo> blocked;
  final FriendsApiService friendsApi;
  final Future<void> Function() onReload;
  final void Function(String, {bool isError}) onShowSnackBar;

  Future<void> _unblock(BuildContext context, BlockedUserInfo user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Débloquer cet utilisateur ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                ServiceLocator().get<IHapticService>().buttonTap();
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Débloquer')),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await friendsApi.unblockUser(user.userId);
    onShowSnackBar(
      result.success
          ? '${user.displayName} débloqué.'
          : (result.error ?? 'Erreur lors du déblocage.'),
      isError: !result.success,
    );
    if (result.success) unawaited(onReload());
  }

  @override
  Widget build(BuildContext context) {
    if (blocked.isEmpty) {
      return Center(
        child: Text(
          'Aucun utilisateur bloqué.',
          style: TextStyle(
              color: MultiplayerColors.of(context).textSecondary, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: blocked.length,
      itemBuilder: (context, index) {
        final cs = MultiplayerColors.of(context);
        final user = blocked[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.separator),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.danger.withValues(alpha: 0.12),
                child: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.danger,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cs.textPrimary)),
                    Text('@${user.username}',
                        style:
                            TextStyle(color: cs.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _unblock(context, user),
                child: Text('Débloquer', style: TextStyle(color: cs.primary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Widget helper: action dans le bottom sheet
// ─────────────────────────────────────────────

class _BottomSheetAction extends StatelessWidget {
  const _BottomSheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
