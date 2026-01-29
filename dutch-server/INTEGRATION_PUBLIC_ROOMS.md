# Intégration des Rooms Publiques - Guide Serveur

Ce document explique comment intégrer le système de rooms publiques dans le serveur Node.js existant.

## 📁 Fichiers Créés

1. **`src/services/publicRoomService.ts`** - Service de gestion des rooms publiques
2. **`src/handlers/publicRoomHandlers.ts`** - Handlers Socket.IO pour les rooms publiques

## 🔧 Intégration dans le Serveur Principal

### Étape 1: Importer les Handlers

Dans votre fichier principal du serveur (probablement `src/server.ts` ou `src/index.ts`), ajoutez :

```typescript
import { 
  setupPublicRoomHandlers,
  onPublicRoomCreated,
  onPublicRoomPlayerJoined,
  onPublicRoomPlayerLeft,
  onPublicRoomClosed,
  isPublicRoom
} from './handlers/publicRoomHandlers';
```

### Étape 2: Configurer les Handlers Socket.IO

Dans la section où vous configurez les événements Socket.IO :

```typescript
io.on('connection', (socket) => {
  console.log(`✅ Client connecté: ${socket.id}`);

  // ... autres handlers existants ...

  // Ajouter les handlers pour les rooms publiques
  setupPublicRoomHandlers(socket, rooms);

  // ... reste du code ...
});
```

### Étape 3: Modifier le Handler de Création de Room

Dans votre handler `room:create`, ajoutez la détection des rooms publiques :

```typescript
socket.on('room:create', async (data, callback) => {
  try {
    const { settings, playerName, clientId } = data;
    const roomCode = generateRoomCode(); // Votre fonction existante
    
    // ... logique de création de room existante ...

    // Si la room est publique, l'ajouter au service
    if (settings.isPublic === true) {
      onPublicRoomCreated(
        roomCode,
        playerName,
        settings.gameMode || 'quick',
        settings.numberOfPlayers || 4
      );
    }

    callback({
      success: true,
      roomCode,
      // ... autres données ...
    });
  } catch (error) {
    console.error('Erreur création room:', error);
    callback({ success: false, error: error.message });
  }
});
```

### Étape 4: Modifier le Handler de Join Room

Mettre à jour le compteur de joueurs pour les rooms publiques :

```typescript
socket.on('room:join', async (data, callback) => {
  try {
    const { roomCode, playerName, clientId } = data;
    
    // ... logique de join existante ...

    const room = rooms.get(roomCode);
    if (room && isPublicRoom(roomCode)) {
      onPublicRoomPlayerJoined(roomCode, room.players.length);
    }

    callback({
      success: true,
      room: roomData,
    });
  } catch (error) {
    console.error('Erreur join room:', error);
    callback({ success: false, error: error.message });
  }
});
```

### Étape 5: Gérer les Déconnexions

Mettre à jour le compteur quand un joueur quitte :

```typescript
socket.on('disconnect', () => {
  // ... logique de déconnexion existante ...

  if (currentRoom && isPublicRoom(currentRoom.code)) {
    const remainingPlayers = currentRoom.players.length;
    
    if (remainingPlayers === 0) {
      onPublicRoomClosed(currentRoom.code);
    } else {
      onPublicRoomPlayerLeft(currentRoom.code, remainingPlayers);
    }
  }
});
```

### Étape 6: Gérer la Fermeture de Room

Quand une room est fermée par l'hôte :

```typescript
socket.on('room:close', (data) => {
  const { roomCode } = data;
  
  // ... logique de fermeture existante ...

  if (isPublicRoom(roomCode)) {
    onPublicRoomClosed(roomCode);
  }
});
```

## 📊 Endpoints API Disponibles

### Socket.IO Events

#### Client → Serveur

**`rooms:getPublic`**
- Description: Récupère la liste des rooms publiques disponibles
- Paramètres: `{}`
- Réponse:
```typescript
{
  success: true,
  rooms: [
    {
      code: "ABC123",
      players: 2,
      maxPlayers: 4,
      gameMode: "quick",
      host: "Player1"
    }
  ]
}
```

**`rooms:stats`**
- Description: Récupère les statistiques des rooms publiques
- Paramètres: `{}`
- Réponse:
```typescript
{
  success: true,
  stats: {
    totalRooms: 5,
    totalPlayers: 12,
    averagePlayersPerRoom: 2.4
  }
}
```

## 🔒 Sécurité et Validation

### Recommandations

1. **Rate Limiting**
```typescript
// Limiter les créations de rooms publiques
const createRoomLimiter = new Map<string, number>();

socket.on('room:create', async (data, callback) => {
  const clientIp = socket.handshake.address;
  const now = Date.now();
  const lastCreate = createRoomLimiter.get(clientIp) || 0;
  
  if (now - lastCreate < 30000) { // 30 secondes
    callback({ 
      success: false, 
      error: 'Veuillez attendre avant de créer une nouvelle room' 
    });
    return;
  }
  
  createRoomLimiter.set(clientIp, now);
  // ... reste de la logique ...
});
```

2. **Validation des Paramètres**
```typescript
if (settings.isPublic) {
  // Vérifier que numberOfPlayers est valide
  if (settings.numberOfPlayers < 2 || settings.numberOfPlayers > 4) {
    callback({ 
      success: false, 
      error: 'Nombre de joueurs invalide (2-4)' 
    });
    return;
  }
}
```

3. **Sanitization des Noms**
```typescript
function sanitizePlayerName(name: string): string {
  return name
    .trim()
    .substring(0, 20)
    .replace(/[<>]/g, ''); // Retirer les caractères dangereux
}
```

## 🧪 Tests

### Test Manuel

1. Démarrer le serveur
2. Ouvrir la console du navigateur
3. Tester la récupération des rooms:

```javascript
socket.emit('rooms:getPublic', {}, (response) => {
  console.log('Rooms publiques:', response);
});
```

### Test Automatisé

Créer un fichier `src/__tests__/publicRooms.test.ts`:

```typescript
import { publicRoomService } from '../services/publicRoomService';

describe('PublicRoomService', () => {
  beforeEach(() => {
    // Reset le service avant chaque test
  });

  test('should add a public room', () => {
    publicRoomService.addPublicRoom('TEST123', 'Player1', 'quick', 4);
    const rooms = publicRoomService.getAvailableRooms();
    expect(rooms).toHaveLength(1);
    expect(rooms[0].code).toBe('TEST123');
  });

  test('should remove full rooms', () => {
    publicRoomService.addPublicRoom('TEST123', 'Player1', 'quick', 4);
    publicRoomService.updatePlayerCount('TEST123', 4);
    const rooms = publicRoomService.getAvailableRooms();
    expect(rooms).toHaveLength(0);
  });

  // ... autres tests ...
});
```

## 📈 Monitoring

### Logs Importants

Le service génère automatiquement des logs:
- `📢 Room publique créée: ABC123 (quick)`
- `👥 Room ABC123: 2/4 joueurs`
- `🗑️ Room publique supprimée: ABC123`
- `🧹 X room(s) publique(s) nettoyée(s)`

### Métriques à Surveiller

```typescript
// Ajouter un endpoint pour les métriques
app.get('/api/metrics/public-rooms', (req, res) => {
  const stats = publicRoomService.getStats();
  res.json({
    ...stats,
    timestamp: new Date().toISOString()
  });
});
```

## 🚀 Déploiement

### Variables d'Environnement

Aucune variable d'environnement supplémentaire n'est requise. Le service fonctionne avec la configuration par défaut.

### Optimisations Production

1. **Ajuster le Timer de Nettoyage**
```typescript
// Dans publicRoomService.ts, modifier:
this.cleanupInterval = setInterval(() => {
  this.cleanup();
}, process.env.NODE_ENV === 'production' ? 30000 : 60000);
```

2. **Limiter le Nombre de Rooms**
```typescript
addPublicRoom(...) {
  if (this.publicRooms.size >= 100) {
    throw new Error('Limite de rooms publiques atteinte');
  }
  // ... reste du code ...
}
```

## 🔄 Migration

Si vous avez déjà des rooms existantes, elles continueront de fonctionner normalement. Le système de rooms publiques est complètement indépendant et ne modifie pas les rooms privées existantes.

## ❓ FAQ

**Q: Que se passe-t-il si le serveur redémarre?**
R: Les rooms publiques sont stockées en mémoire et seront perdues. Les joueurs devront recréer des rooms.

**Q: Peut-on avoir des rooms publiques ET privées en même temps?**
R: Oui, une room est soit publique (isPublic: true) soit privée (isPublic: false). Les deux coexistent sans problème.

**Q: Comment empêcher le spam de création de rooms?**
R: Utilisez le rate limiting suggéré dans la section Sécurité.

**Q: Les rooms publiques expirent-elles?**
R: Oui, après 10 minutes d'inactivité ou si elles sont vides, elles sont automatiquement supprimées.

## 📝 Checklist d'Intégration

- [ ] Importer les handlers dans le serveur principal
- [ ] Configurer `setupPublicRoomHandlers` dans `io.on('connection')`
- [ ] Modifier `room:create` pour détecter `isPublic`
- [ ] Modifier `room:join` pour mettre à jour le compteur
- [ ] Gérer les déconnexions pour les rooms publiques
- [ ] Gérer la fermeture de rooms
- [ ] Ajouter le rate limiting
- [ ] Ajouter la validation des paramètres
- [ ] Tester manuellement
- [ ] Déployer en production
