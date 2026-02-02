import 'package:flutter/widgets.dart';

/// Gère toutes les notifications du mode multijoueur
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion des notifications
class MultiplayerNotificationManager {
  final VoidCallback _notifyListeners;

  // Room fermée par l'hôte
  bool _roomClosedByHost = false;
  bool get roomClosedByHost => _roomClosedByHost;
  String? _closedRoomCode;
  String? get closedRoomCode => _closedRoomCode;

  // Kick par l'hôte (peut revenir)
  bool _wasKicked = false;
  bool get wasKicked => _wasKicked;
  String? _kickedMessage;
  String? get kickedMessage => _kickedMessage;

  // Ban par l'hôte (définitif)
  bool _wasBanned = false;
  bool get wasBanned => _wasBanned;
  String? _bannedMessage;
  String? get bannedMessage => _bannedMessage;

  // Notification: joueur parti
  bool _playerLeftNotification = false;
  bool get playerLeftNotification => _playerLeftNotification;
  String? _lastPlayerLeftName;
  String? get lastPlayerLeftName => _lastPlayerLeftName;

  // Notification: pouvoir spécial utilisé sur nous
  bool _specialPowerNotification = false;
  bool get specialPowerNotification => _specialPowerNotification;
  String? _specialPowerByName;
  String? get specialPowerByName => _specialPowerByName;
  String? _specialPowerType;
  String? get specialPowerType => _specialPowerType;

  // Notification Valet : notre carte a été échangée
  Map<String, dynamic>? _pendingSwapNotification;
  Map<String, dynamic>? get pendingSwapNotification => _pendingSwapNotification;

  // Notification Joker : nos cartes ont été mélangées
  Map<String, dynamic>? _pendingJokerNotification;
  Map<String, dynamic>? get pendingJokerNotification => _pendingJokerNotification;

  // Notification Espionnage : quelqu'un regarde notre carte
  Map<String, dynamic>? _pendingSpyNotification;
  Map<String, dynamic>? get pendingSpyNotification => _pendingSpyNotification;

  // Erreur
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  MultiplayerNotificationManager({required VoidCallback notifyListeners})
      : _notifyListeners = notifyListeners;

  // ═══════════════════════════════════════════════════════════════════════════
  // ROOM CLOSED
  // ═══════════════════════════════════════════════════════════════════════════

  void handleRoomClosed(Map<String, dynamic> data) {
    _roomClosedByHost = true;
    _closedRoomCode = data['roomCode']?.toString();
    _notifyListeners();
  }

  void acknowledgeRoomClosed() {
    _roomClosedByHost = false;
    _closedRoomCode = null;
  }

  void clearRoomClosedAfterBecomeHost() {
    _roomClosedByHost = false;
    _closedRoomCode = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KICK
  // ═══════════════════════════════════════════════════════════════════════════

  void handleKicked(Map<String, dynamic> data) {
    _wasKicked = true;
    _kickedMessage = data['message']?.toString() ?? 'Vous avez été exclu (vous pouvez revenir)';
    _notifyListeners();
  }

  void acknowledgeKicked() {
    _wasKicked = false;
    _kickedMessage = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAN
  // ═══════════════════════════════════════════════════════════════════════════

  void handleBanned(Map<String, dynamic> data) {
    _wasBanned = true;
    _bannedMessage = data['message']?.toString() ?? 'Vous avez été banni de cette room';
    _notifyListeners();
  }

  void acknowledgeBanned() {
    _wasBanned = false;
    _bannedMessage = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYER LEFT / AFK
  // ═══════════════════════════════════════════════════════════════════════════

  void handlePlayerLeft(Map<String, dynamic> data) {
    _lastPlayerLeftName = data['playerName']?.toString();
    _playerLeftNotification = true;
    _notifyListeners();
    _autoClearAfterDelay(() {
      _playerLeftNotification = false;
      _notifyListeners();
    });
  }

  void handlePlayerAfk(Map<String, dynamic> data) {
    final playerName = data['playerName']?.toString();
    _lastPlayerLeftName = playerName != null ? '$playerName (AFK)' : 'Joueur AFK';
    _playerLeftNotification = true;
    _notifyListeners();
    _autoClearAfterDelay(() {
      _playerLeftNotification = false;
      _notifyListeners();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPECIAL POWERS NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void handleSpecialPowerTargeted(Map<String, dynamic> data) {
    _specialPowerByName = data['byPlayerName']?.toString();
    _specialPowerType = data['powerType']?.toString();
    _specialPowerNotification = true;
    _notifyListeners();
    _autoClearAfterDelay(() {
      _specialPowerNotification = false;
      _notifyListeners();
    });
  }

  void handleSwapNotification(Map<String, dynamic> data) {
    _pendingSwapNotification = data;
    _notifyListeners();
  }

  void handleJokerNotification(Map<String, dynamic> data) {
    _pendingJokerNotification = data;
    _notifyListeners();
  }

  void handleSpyNotification(Map<String, dynamic> data) {
    _pendingSpyNotification = data;
    _notifyListeners();
  }

  void clearSwapNotification() {
    _pendingSwapNotification = null;
    _notifyListeners();
  }

  void clearJokerNotification() {
    _pendingJokerNotification = null;
    _notifyListeners();
  }

  void clearSpyNotification() {
    _pendingSpyNotification = null;
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERROR
  // ═══════════════════════════════════════════════════════════════════════════

  void setError(String? error) {
    _errorMessage = error;
    _notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _roomClosedByHost = false;
    _closedRoomCode = null;
    _wasKicked = false;
    _kickedMessage = null;
    _wasBanned = false;
    _bannedMessage = null;
    _playerLeftNotification = false;
    _lastPlayerLeftName = null;
    _specialPowerNotification = false;
    _specialPowerByName = null;
    _specialPowerType = null;
    _pendingSwapNotification = null;
    _pendingJokerNotification = null;
    _pendingSpyNotification = null;
    _errorMessage = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _autoClearAfterDelay(VoidCallback callback, {int seconds = 3}) {
    Future.delayed(Duration(seconds: seconds), callback);
  }
}
