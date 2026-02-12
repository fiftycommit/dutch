import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SocialProfile {
  final String displayName;
  final String username;
  final bool roomInviteNotificationsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SocialProfile({
    required this.displayName,
    required this.username,
    required this.roomInviteNotificationsEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  SocialProfile copyWith({
    String? displayName,
    String? username,
    bool? roomInviteNotificationsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SocialProfile(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      roomInviteNotificationsEnabled:
          roomInviteNotificationsEnabled ?? this.roomInviteNotificationsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'displayName': displayName,
      'username': username,
      'roomInviteNotificationsEnabled': roomInviteNotificationsEnabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SocialProfile.fromJson(Map<String, dynamic> json) {
    return SocialProfile(
      displayName: (json['displayName'] as String? ?? 'Joueur').trim(),
      username: (json['username'] as String? ?? '').trim(),
      roomInviteNotificationsEnabled:
          json['roomInviteNotificationsEnabled'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class FriendEntry {
  final String username;
  final String displayName;
  final DateTime addedAt;

  const FriendEntry({
    required this.username,
    required this.displayName,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'username': username,
      'displayName': displayName,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory FriendEntry.fromJson(Map<String, dynamic> json) {
    return FriendEntry(
      username: (json['username'] as String? ?? '').trim(),
      displayName: (json['displayName'] as String? ?? 'Ami').trim(),
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

enum FriendRequestDirection {
  incoming,
  outgoing,
}

class FriendRequestEntry {
  final String username;
  final String displayName;
  final DateTime requestedAt;
  final FriendRequestDirection direction;

  const FriendRequestEntry({
    required this.username,
    required this.displayName,
    required this.requestedAt,
    required this.direction,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'username': username,
      'displayName': displayName,
      'requestedAt': requestedAt.toIso8601String(),
      'direction': direction.name,
    };
  }

  factory FriendRequestEntry.fromJson(Map<String, dynamic> json) {
    final directionRaw = (json['direction'] as String? ?? 'outgoing').trim();
    final direction = directionRaw == FriendRequestDirection.incoming.name
        ? FriendRequestDirection.incoming
        : FriendRequestDirection.outgoing;
    return FriendRequestEntry(
      username: (json['username'] as String? ?? '').trim(),
      displayName: (json['displayName'] as String? ?? 'Joueur').trim(),
      requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? '') ??
          DateTime.now(),
      direction: direction,
    );
  }
}

class SocialHubRepository {
  static const String _profileKey = 'social_profile_v1';
  static const String _friendsKey = 'social_friends_v1';
  static const String _friendRequestsKey = 'social_friend_requests_v1';
  static const String _blockedUsersKey = 'social_blocked_users_v1';

  static final RegExp _usernamePattern = RegExp(
    r'^[\p{L}\p{N}._-]{3,20}$',
    unicode: true,
  );
  static final RegExp _usernameCharsPattern = RegExp(
    r'^[\p{L}\p{N}._-]*$',
    unicode: true,
  );

  static bool isValidUsernameFormat(String rawUsername) {
    return _usernamePattern.hasMatch(normalizeUsername(rawUsername));
  }

  static bool containsOnlyAllowedUsernameChars(String rawUsername) {
    return _usernameCharsPattern.hasMatch(rawUsername.toLowerCase());
  }

  static String normalizeUsername(String rawUsername) {
    return rawUsername.trim().toLowerCase();
  }

  Future<SocialProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final jsonMap = json.decode(raw) as Map<String, dynamic>;
      return SocialProfile.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(SocialProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, json.encode(profile.toJson()));
  }

  Future<List<FriendEntry>> getFriends() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_friendsKey) ?? <String>[];
    return rawList
        .map((raw) {
          try {
            return FriendEntry.fromJson(
                json.decode(raw) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<FriendEntry>()
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Future<void> _addFriendFromAcceptedRequest({
    required String username,
    required String displayName,
  }) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsernameFormat(normalized)) {
      throw const FormatException(
        'Nom d utilisateur invalide (3-20 caracteres, lettres/chiffres, ., _, -)',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final friends = await getFriends();
    friends.removeWhere((friend) => friend.username == normalized);
    friends.add(
      FriendEntry(
        username: normalized,
        displayName:
            displayName.trim().isEmpty ? normalized : displayName.trim(),
        addedAt: DateTime.now(),
      ),
    );

    final encoded =
        friends.map((friend) => json.encode(friend.toJson())).toList();
    await prefs.setStringList(_friendsKey, encoded);
  }

  Future<void> removeFriend(String username) async {
    final normalized = normalizeUsername(username);
    final prefs = await SharedPreferences.getInstance();
    final friends = await getFriends();
    friends.removeWhere((friend) => friend.username == normalized);
    final encoded =
        friends.map((friend) => json.encode(friend.toJson())).toList();
    await prefs.setStringList(_friendsKey, encoded);
  }

  Future<List<FriendRequestEntry>> getFriendRequests({
    FriendRequestDirection? direction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_friendRequestsKey) ?? <String>[];
    final requests = rawList
        .map((raw) {
          try {
            return FriendRequestEntry.fromJson(
              json.decode(raw) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<FriendRequestEntry>()
        .toList();

    if (direction == null) {
      return requests;
    }
    return requests.where((request) => request.direction == direction).toList();
  }

  Future<void> addFriendRequest({
    required String username,
    required String displayName,
    required FriendRequestDirection direction,
  }) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsernameFormat(normalized)) {
      throw const FormatException(
        'Nom d utilisateur invalide (3-20 caracteres, lettres/chiffres, ., _, -)',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final requests = await getFriendRequests();
    requests.removeWhere(
      (request) =>
          request.username == normalized && request.direction == direction,
    );
    requests.add(
      FriendRequestEntry(
        username: normalized,
        displayName:
            displayName.trim().isEmpty ? normalized : displayName.trim(),
        requestedAt: DateTime.now(),
        direction: direction,
      ),
    );

    final encoded =
        requests.map((request) => json.encode(request.toJson())).toList();
    await prefs.setStringList(_friendRequestsKey, encoded);
  }

  Future<void> removeFriendRequest({
    required String username,
    required FriendRequestDirection direction,
  }) async {
    final normalized = normalizeUsername(username);
    final prefs = await SharedPreferences.getInstance();
    final requests = await getFriendRequests();
    requests.removeWhere(
      (request) =>
          request.username == normalized && request.direction == direction,
    );
    final encoded =
        requests.map((request) => json.encode(request.toJson())).toList();
    await prefs.setStringList(_friendRequestsKey, encoded);
  }

  Future<void> acceptIncomingRequest(String username) async {
    final normalized = normalizeUsername(username);
    final incoming = await getFriendRequests(
      direction: FriendRequestDirection.incoming,
    );
    final match = incoming.where((request) => request.username == normalized);
    if (match.isEmpty) {
      return;
    }

    final request = match.first;
    await _addFriendFromAcceptedRequest(
        username: request.username, displayName: request.displayName);
    await removeFriendRequest(
      username: request.username,
      direction: FriendRequestDirection.incoming,
    );
  }

  Future<List<String>> getBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_blockedUsersKey) ?? <String>[];
  }

  Future<void> blockUser(String username) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsernameFormat(normalized)) {
      throw const FormatException('Nom d utilisateur invalide');
    }

    final prefs = await SharedPreferences.getInstance();
    final blocked = await getBlockedUsers();
    if (!blocked.contains(normalized)) {
      blocked.add(normalized);
    }
    await prefs.setStringList(_blockedUsersKey, blocked);
    await removeFriend(normalized);
  }

  Future<void> unblockUser(String username) async {
    final normalized = normalizeUsername(username);
    final prefs = await SharedPreferences.getInstance();
    final blocked = await getBlockedUsers();
    blocked.removeWhere((entry) => entry == normalized);
    await prefs.setStringList(_blockedUsersKey, blocked);
  }

  Future<bool> isUsernameAvailableLocally(
    String username, {
    String? exceptUsername,
  }) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsernameFormat(normalized)) {
      return false;
    }
    final reserved = await getReservedUsernames(exceptUsername: exceptUsername);
    return !reserved.contains(normalized);
  }

  Future<Set<String>> getReservedUsernames({
    String? exceptUsername,
  }) async {
    final except =
        exceptUsername == null ? null : normalizeUsername(exceptUsername);

    final reserved = <String>{};

    final profile = await getProfile();
    if (profile != null && profile.username.isNotEmpty) {
      reserved.add(normalizeUsername(profile.username));
    }

    final friends = await getFriends();
    reserved.addAll(
      friends.map((friend) => normalizeUsername(friend.username)),
    );

    final requests = await getFriendRequests();
    reserved.addAll(
      requests.map((request) => normalizeUsername(request.username)),
    );

    final blockedUsers = await getBlockedUsers();
    reserved.addAll(
      blockedUsers.map(normalizeUsername),
    );

    if (except != null && except.isNotEmpty) {
      reserved.remove(except);
    }

    reserved.removeWhere((value) => value.isEmpty);
    return reserved;
  }

  Future<void> clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    await prefs.remove(_friendsKey);
    await prefs.remove(_friendRequestsKey);
    await prefs.remove(_blockedUsersKey);
  }
}
