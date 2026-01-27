# Plan : Améliorations Multijoueur

## Fonctionnalités à implémenter

### 1. Reconnexion automatique & Retry
- Reconnexion Socket.IO avec backoff exponentiel
- File d'attente des actions pendant la déconnexion
- Rejoindre automatiquement la room après reconnexion
- Indicateur de connexion dans l'UI

### 2. Gestion claire des rooms
- Bouton "Fermer la room" explicite pour l'hôte
- Liste "Mes rooms" pour revenir dans ses rooms ouvertes
- Persistance des room codes dans SharedPreferences
- Quand l'hôte ferme : notification + choix "Devenir hôte" / "Quitter"

### 3. Mode de jeu modifiable dans le lobby
- Retirer le choix Quick/Tournament à la création
- Ajouter un sélecteur dans le lobby (hôte uniquement)
- Broadcast du changement à tous les joueurs

### 4. Classement permanent dans la room
- Scores cumulés par clientId dans la room
- Leaderboard affiché dans le lobby
- Reset uniquement quand la room est fermée

---

## Implémentation détaillée

### Phase 1 : Reconnexion automatique (Client)

**Fichier : `lib/services/multiplayer_service.dart`**

```dart
// Nouvelles propriétés
int _reconnectAttempts = 0;
static const int _maxReconnectAttempts = 5;
Timer? _reconnectTimer;
String? _lastRoomCode; // Pour auto-rejoin
List<Map<String, dynamic>> _pendingActions = []; // File d'attente
ConnectionState _connectionState = ConnectionState.disconnected;

enum ConnectionState { disconnected, connecting, connected, reconnecting }

// Méthode de reconnexion avec backoff
Future<void> _attemptReconnect() async {
  if (_reconnectAttempts >= _maxReconnectAttempts) {
    _connectionState = ConnectionState.disconnected;
    onConnectionStateChanged?.call(_connectionState);
    return;
  }

  _connectionState = ConnectionState.reconnecting;
  onConnectionStateChanged?.call(_connectionState);

  final delay = Duration(seconds: pow(2, _reconnectAttempts).toInt());
  _reconnectAttempts++;

  await Future.delayed(delay);
  await connect();

  if (isConnected && _lastRoomCode != null) {
    await rejoinRoom(_lastRoomCode!);
  }
}
```

**Fichier : `lib/providers/multiplayer_game_provider.dart`**

```dart
// Callback pour l'état de connexion
ConnectionState _connectionState = ConnectionState.disconnected;
ConnectionState get connectionState => _connectionState;

void _onConnectionStateChanged(ConnectionState state) {
  _connectionState = state;
  notifyListeners();
}
```

### Phase 2 : Gestion des rooms (Client + Serveur)

**Fichier : `lib/services/multiplayer_service.dart`**

```dart
// Persistance des rooms
Future<void> _saveMyRoom(String roomCode) async {
  final prefs = await SharedPreferences.getInstance();
  final rooms = prefs.getStringList('my_rooms') ?? [];
  if (!rooms.contains(roomCode)) {
    rooms.add(roomCode);
    await prefs.setStringList('my_rooms', rooms);
  }
}

Future<List<String>> getMyRooms() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('my_rooms') ?? [];
}

Future<void> closeRoom(String roomCode) async {
  _socket?.emit('room:close', {'roomCode': roomCode});
}

Future<void> transferHost(String roomCode, String newHostId) async {
  _socket?.emit('room:transfer_host', {
    'roomCode': roomCode,
    'newHostId': newHostId,
  });
}
```

**Fichier : `dutch-server/src/services/RoomManager.ts`**

```typescript
// Nouvelles méthodes
closeRoom(roomCode: string, socketId: string): { success: boolean; reason?: string } {
  const room = this.rooms.get(roomCode);
  if (!room) return { success: false, reason: 'Room not found' };
  if (room.hostPlayerId !== socketId) return { success: false, reason: 'Not host' };

  // Notifier tous les joueurs
  room.players.forEach(player => {
    if (player.id !== socketId) {
      this.io.to(player.id).emit('room:closed', {
        roomCode,
        hostLeft: true,
        canBecomeHost: player.isHuman && player.connected,
      });
    }
  });

  // Marquer la room comme fermée mais la garder 5 min pour transfert
  room.status = RoomStatus.closing;
  room.closingAt = this.now() + 5 * 60 * 1000;

  return { success: true };
}

transferHost(roomCode: string, requesterId: string): boolean {
  const room = this.rooms.get(roomCode);
  if (!room || room.status !== RoomStatus.closing) return false;

  const requester = room.players.find(p => p.id === requesterId);
  if (!requester || !requester.isHuman || !requester.connected) return false;

  room.hostPlayerId = requesterId;
  room.status = RoomStatus.waiting;
  room.closingAt = undefined;

  this.broadcastPresence(roomCode);
  return true;
}
```

**Fichier : `dutch-server/src/handlers/roomHandler.ts`**

```typescript
// Nouveaux handlers
socket.on('room:close', ({ roomCode }) => {
  const result = roomManager.closeRoom(roomCode, socket.id);
  socket.emit('room:close_result', result);
});

socket.on('room:transfer_host', ({ roomCode }) => {
  const success = roomManager.transferHost(roomCode, socket.id);
  socket.emit('room:transfer_result', { success });
});

socket.on('room:check_active', ({ roomCodes }) => {
  const active = roomManager.checkActiveRooms(roomCodes);
  socket.emit('room:active_list', { rooms: active });
});
```

### Phase 3 : Mode de jeu modifiable

**Fichier : `dutch-server/src/models/Room.ts`**

```typescript
// Le gameMode est déjà dans room.gameMode
// Ajouter une méthode pour le changer
```

**Fichier : `dutch-server/src/services/RoomManager.ts`**

```typescript
setGameMode(roomCode: string, socketId: string, mode: GameMode): boolean {
  const room = this.rooms.get(roomCode);
  if (!room || room.status !== RoomStatus.waiting) return false;
  if (room.hostPlayerId !== socketId) return false;

  room.gameMode = mode;
  this.broadcastPresence(roomCode); // Inclure gameMode dans presence
  return true;
}
```

### Phase 4 : Classement permanent

**Fichier : `dutch-server/src/models/Room.ts`**

```typescript
export interface Room {
  // ... existant
  cumulativeScores: Map<string, number>; // clientId -> score total
}
```

**Fichier : `dutch-server/src/services/RoomManager.ts`**

```typescript
// Dans handleGameEnd
updateCumulativeScores(room: Room) {
  const gameState = room.gameState;
  if (!gameState) return;

  for (const player of gameState.players) {
    if (!player.isHuman) continue;
    const score = this.calculatePlayerScore(player);
    const current = room.cumulativeScores.get(player.clientId) || 0;
    room.cumulativeScores.set(player.clientId, current + score);
  }
}

// Dans broadcastPresence, inclure les scores
```

---

## Nouveaux événements Socket.IO

| Client → Serveur | Description |
|------------------|-------------|
| `room:close` | Hôte ferme la room |
| `room:transfer_host` | Joueur demande à devenir hôte |
| `room:check_active` | Vérifier quelles rooms sont actives |
| `room:set_game_mode` | Changer le mode de jeu |

| Serveur → Client | Description |
|------------------|-------------|
| `room:closed` | Room fermée par l'hôte |
| `room:close_result` | Résultat de la fermeture |
| `room:transfer_result` | Résultat du transfert |
| `room:active_list` | Liste des rooms actives |

---

## Modifications UI

### MultiplayerMenuScreen
- Ajouter section "Mes rooms" avec liste des rooms actives
- Bouton pour rejoindre chaque room

### MultiplayerLobbyScreen
- Remplacer bouton retour par "Quitter" / "Fermer la room" (si hôte)
- Ajouter sélecteur de mode de jeu (hôte)
- Ajouter tableau des scores cumulés
- Indicateur de connexion (vert/orange/rouge)
- Dialog quand l'hôte ferme : "Devenir hôte" / "Quitter"

---

## Ordre d'implémentation

1. **Reconnexion automatique** (client uniquement)
2. **Indicateur de connexion** (UI)
3. **Bouton fermer room + événements serveur**
4. **Transfert d'hôte**
5. **Liste "Mes rooms"**
6. **Mode de jeu modifiable**
7. **Scores cumulés**

---

## Tests à effectuer

1. Couper le WiFi pendant une partie → doit reconnecter
2. Fermer l'app et revenir → doit pouvoir rejoindre sa room
3. Hôte ferme la room → les autres reçoivent notification
4. Joueur devient hôte → la room continue
5. Changer le mode en lobby → tous les joueurs voient le changement
6. Jouer plusieurs parties → scores cumulés affichés
