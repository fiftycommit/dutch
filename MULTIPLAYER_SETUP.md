# Configuration Multijoueur - Dutch Game

## Architecture

L'implémentation multijoueur utilise :
- **Backend** : Node.js + TypeScript + Socket.IO
- **Client** : Flutter + socket_io_client

## Fichiers modifiés/créés

### ✅ Phase 1 : Sérialisation (Complétée)

- `lib/models/card.dart` - Ajout toJson/fromJson à PlayingCard
- `lib/models/player.dart` - Ajout toJson/fromJson à Player
- `lib/models/game_state.dart` - Ajout toJson/fromJson à GameState

### ✅ Phase 2 : Backend Node.js (Complétée)

Structure créée :
```
dutch-server/
├── package.json
├── tsconfig.json
├── README.md
└── src/
    ├── index.ts              # Serveur Socket.IO
    └── models/
        ├── Card.ts           # Modèle carte
        ├── Player.ts         # Modèle joueur
        ├── GameState.ts      # État du jeu
        └── Room.ts           # Room multijoueur
```

### ✅ Phase 3 : Client Flutter (Complétée)

- `pubspec.yaml` - Ajout socket_io_client ^2.0.3+1
- `lib/services/multiplayer_service.dart` - Service de connexion Socket.IO

## Démarrer le serveur

```bash
cd dutch-server
npm install
npm run dev
```

Le serveur démarre sur http://localhost:3000

## Tester la connexion

### 1. Lancer le serveur
```bash
cd dutch-server
npm run dev
```

Vous devriez voir :
```
🚀 Dutch Server running on port 3000
📡 Socket.IO ready for connections
```

### 2. Vérifier la santé du serveur
```bash
curl http://localhost:3000/health
```

Réponse attendue :
```json
{"status":"ok","rooms":0}
```

### 3. Tester depuis Flutter

Dans votre code Flutter :
```dart
final multiplayerService = MultiplayerService();

// Connecter
await multiplayerService.connect();

// Créer une room
final roomCode = await multiplayerService.createRoom(
  settings: GameSettings(),
  playerName: 'Test Player',
);

print('Room créée: $roomCode');
```

## API Socket.IO

### Événements client → serveur

| Événement | Données | Description |
|-----------|---------|-------------|
| `room:create` | `{settings, playerName}` | Créer une room |
| `room:join` | `{roomCode, playerName}` | Rejoindre une room |
| `room:start_game` | `{roomCode}` | Démarrer la partie (hôte) |
| `room:leave` | `{roomCode}` | Quitter la room |

### Événements serveur → client

| Événement | Données | Description |
|-----------|---------|-------------|
| `room:player_joined` | `{roomCode, player, playerCount}` | Nouveau joueur |
| `game:state_update` | `{type, gameState, ...}` | Mise à jour du jeu |
| `game:timer_update` | `{reactionTimeRemaining}` | Timer de réaction |

## Prochaines étapes

### À implémenter côté serveur

1. **GameLogic complet** : Porter toute la logique de `lib/services/game_logic.dart`
2. **BotAI** : Porter l'IA des bots depuis `lib/services/bot_ai.dart`
3. **RoomManager** : Gestionnaire centralisé des rooms
4. **TimerManager** : Gestion des timers de réaction synchronisés
5. **Validation** : Vérifier toutes les actions côté serveur

### À implémenter côté client

1. **MultiplayerGameProvider** : Provider pour l'état multijoueur
2. **UI Screens** :
   - MultiplayerMenuScreen (créer/rejoindre)
   - MultiplayerLobbyScreen (salle d'attente)
   - MultiplayerGameScreen (partie en cours)

## Configuration réseau

### Pour tester en local

Le serveur est configuré pour `localhost:3000`. Aucune configuration nécessaire.

### Pour tester sur réseau local (plusieurs appareils)

1. Trouvez l'adresse IP de votre machine :
   ```bash
   # macOS/Linux
   ifconfig | grep "inet "

   # Windows
   ipconfig
   ```

2. Modifiez `lib/services/multiplayer_service.dart` :
   ```dart
   static const String _serverUrl = 'http://YOUR_IP:3000';
   ```

3. Assurez-vous que le firewall autorise le port 3000

### Pour déployer en production

1. Héberger le serveur (Railway, Render, Heroku, AWS, etc.)
2. Obtenir une URL publique (ex: `https://dutch-game.railway.app`)
3. Mettre à jour `_serverUrl` dans le client
4. Configurer CORS correctement côté serveur

## Debugging

### Logs serveur
Le serveur affiche des logs pour chaque événement :
- `Client connected: <socket_id>`
- `Room created: <code> by <player_id>`
- `Player <id> joined room <code>`

### Logs client
Le MultiplayerService affiche des emojis pour suivre les actions :
- 📡 Connexion
- 🎲 Création de room
- 🚪 Rejoindre room
- 🎮 Actions de jeu
- ❌ Erreurs

## Sécurité

### Points d'attention actuels

⚠️ **À sécuriser avant la production** :
- [ ] Restreindre CORS (ne pas laisser `origin: '*'`)
- [ ] Ajouter rate limiting
- [ ] Valider toutes les entrées côté serveur
- [ ] Ajouter authentification (tokens JWT)
- [ ] Chiffrer les communications (HTTPS/WSS)
- [ ] Limiter la taille des rooms
- [ ] Expirer les rooms inactives
- [ ] Gérer les déconnexions brutales

## Dépendances

### Backend
```json
{
  "dependencies": {
    "express": "^5.2.1",
    "socket.io": "^4.8.3",
    "cors": "^2.8.6"
  },
  "devDependencies": {
    "typescript": "^5.9.3",
    "ts-node": "^10.9.2",
    "nodemon": "^3.1.11"
  }
}
```

### Client Flutter
```yaml
dependencies:
  socket_io_client: ^2.0.3+1
```

## Ressources

- [Socket.IO Documentation](https://socket.io/docs/v4/)
- [socket_io_client Flutter](https://pub.dev/packages/socket_io_client)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)

## Support

Pour toute question ou problème :
1. Vérifier les logs serveur et client
2. Tester `/health` endpoint
3. Vérifier la connexion réseau
4. Consulter la documentation Socket.IO
