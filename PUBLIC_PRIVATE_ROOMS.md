# Système de Rooms Publiques et Privées

Ce document décrit le système de matchmaking public/privé pour le mode multijoueur.

## 🎮 Vue d'Ensemble

Le jeu propose maintenant deux modes de jeu en ligne :
- **Mode Public** : Matchmaking rapide avec des joueurs aléatoires
- **Mode Privé** : Parties entre amis avec code de room

## 📱 Interface Utilisateur

### Écran de Sélection de Mode
**Fichier** : `lib/screens/multiplayer_mode_selection_screen.dart`

Deux cartes interactives avec animations :
- **Partie Publique** (icône 🌐, couleur bleue)
  - Badge "RAPIDE"
  - Description : "Rejoignez une partie rapide avec des joueurs aléatoires"
  
- **Partie Privée** (icône 🔒, couleur verte)
  - Badge "AMIS"
  - Description : "Créez ou rejoignez une partie avec vos amis"

### Écran de Matchmaking Public
**Fichier** : `lib/screens/public_matchmaking_screen.dart`

**Fonctionnalités** :
- Animation de recherche (rotation + pulse)
- Timer de recherche (format MM:SS)
- Compteur de joueurs (X/4)
- Bouton d'annulation
- Navigation automatique vers le lobby quand une partie est trouvée

**Animations** :
- Icône de recherche rotative
- Effet de pulse sur l'icône
- Ombre lumineuse bleue

## 🔧 Architecture Technique

### Modèle GameSettings
**Fichier** : `lib/models/game_settings.dart`

Nouveaux paramètres ajoutés :
```dart
bool isPublic;           // true = room publique, false = privée
int numberOfPlayers;     // Nombre de joueurs souhaités (2-4)
```

### Provider MultiplayerGameProvider
**Fichier** : `lib/providers/multiplayer_game_provider.dart`

Nouvelles méthodes :

#### `joinPublicRoom()`
Logique de matchmaking automatique :
1. Récupère la liste des rooms publiques disponibles
2. Si une room existe → Rejoint la première disponible
3. Sinon → Crée une nouvelle room publique
4. Gère les erreurs et l'état de connexion

```dart
Future<void> joinPublicRoom() async {
  final publicRooms = await _multiplayerService.getPublicRooms();
  
  if (publicRooms != null && publicRooms.isNotEmpty) {
    await joinRoom(roomCode: publicRooms.first['code']);
  } else {
    await createRoom(settings: GameSettings(isPublic: true));
  }
}
```

#### `getPublicRooms()`
Récupère la liste des rooms publiques disponibles :
```dart
Future<List<Map<String, dynamic>>?> getPublicRooms() async {
  return await _multiplayerService.getPublicRooms();
}
```

### Service MultiplayerService
**Fichier** : `lib/services/multiplayer_service.dart`

**Méthode à implémenter côté serveur** :

```dart
Future<List<Map<String, dynamic>>?> getPublicRooms() async {
  // Appel API au serveur pour récupérer les rooms publiques
  // Format attendu :
  // [
  //   {
  //     'code': 'ABC123',
  //     'players': 2,
  //     'maxPlayers': 4,
  //     'gameMode': 'quick',
  //     'host': 'PlayerName'
  //   }
  // ]
}
```

## 🖥️ Modifications Serveur Nécessaires

### Endpoints à Créer

#### GET `/api/rooms/public`
Retourne la liste des rooms publiques disponibles
```json
{
  "rooms": [
    {
      "code": "ABC123",
      "players": 2,
      "maxPlayers": 4,
      "gameMode": "quick",
      "host": "Player1",
      "createdAt": "2026-01-29T20:00:00Z"
    }
  ]
}
```

#### POST `/api/rooms/create`
Paramètre supplémentaire : `isPublic: boolean`

#### Logique Serveur
```javascript
// Gestion des rooms publiques
const publicRooms = new Map();

// Créer une room
socket.on('room:create', (data) => {
  const { settings, playerName } = data;
  const roomCode = generateRoomCode();
  
  if (settings.isPublic) {
    publicRooms.set(roomCode, {
      code: roomCode,
      players: 1,
      maxPlayers: settings.numberOfPlayers,
      gameMode: settings.gameMode,
      host: playerName,
      createdAt: new Date()
    });
  }
  
  // ... reste de la logique
});

// Récupérer les rooms publiques
socket.on('rooms:getPublic', (callback) => {
  const available = Array.from(publicRooms.values())
    .filter(room => room.players < room.maxPlayers)
    .sort((a, b) => b.players - a.players); // Rooms les plus remplies en premier
  
  callback({ rooms: available });
});

// Nettoyer les rooms vides/expirées
setInterval(() => {
  const now = new Date();
  for (const [code, room] of publicRooms) {
    if (room.players === 0 || 
        now - room.createdAt > 5 * 60 * 1000) { // 5 minutes
      publicRooms.delete(code);
    }
  }
}, 60000); // Toutes les minutes
```

## 🎯 Flow Utilisateur

### Mode Public
```
1. Menu Principal → "Multijoueur"
2. Sélection de Mode → "Partie Publique"
3. Écran de Matchmaking
   ├─ Recherche en cours...
   ├─ Timer actif
   └─ Compteur de joueurs
4. Partie trouvée → Lobby
5. Démarrage automatique quand 4 joueurs
```

### Mode Privé (Existant)
```
1. Menu Principal → "Multijoueur"
2. Sélection de Mode → "Partie Privée"
3. Choix : Créer ou Rejoindre
4. Si Créer → Génération de code
5. Si Rejoindre → Saisie du code
6. Lobby
7. Host démarre manuellement
```

## 🚀 Routes à Ajouter

Dans le router de l'application :

```dart
GoRoute(
  path: '/multiplayer',
  builder: (context, state) => MultiplayerModeSelectionScreen(),
),
GoRoute(
  path: '/multiplayer/public',
  builder: (context, state) => PublicMatchmakingScreen(),
),
GoRoute(
  path: '/multiplayer/private',
  builder: (context, state) => MultiplayerLobbyScreen(), // Écran existant
),
```

## ✨ Fonctionnalités Futures

### Améliorations Possibles
- [ ] **Filtres de recherche** : Par mode de jeu, nombre de joueurs
- [ ] **Liste des rooms publiques** : Afficher toutes les rooms disponibles
- [ ] **Rejoindre une room spécifique** : Cliquer sur une room dans la liste
- [ ] **Estimation du temps d'attente** : Basé sur l'historique
- [ ] **Préférences de matchmaking** : Niveau de compétence similaire
- [ ] **Invitations** : Inviter des amis dans une room publique
- [ ] **Historique des parties** : Voir les parties récentes
- [ ] **Favoris** : Marquer des joueurs comme favoris

### Anti-Abus
- [ ] **Cooldown de création** : Limiter la création de rooms
- [ ] **Report system** : Signaler les comportements inappropriés
- [ ] **Pénalités de déconnexion** : Réduire le MMR en cas d'abandon
- [ ] **Timeout de lobby** : Fermer les lobbies inactifs

## 📊 Métriques à Suivre

Pour optimiser le matchmaking :
- Temps moyen de recherche
- Taux de parties complétées vs abandonnées
- Distribution des tailles de parties (2, 3, 4 joueurs)
- Heures de pointe
- Taux de reconnexion

## 🔐 Sécurité

### Considérations
- **Validation côté serveur** : Vérifier que les rooms publiques respectent les limites
- **Rate limiting** : Limiter les créations/jointures de rooms
- **Sanitization** : Nettoyer les noms de joueurs
- **Anti-spam** : Détecter les comportements abusifs

## 📝 Notes d'Implémentation

### État Actuel
✅ Interface utilisateur créée
✅ Modèle GameSettings mis à jour
✅ Provider avec logique de matchmaking
✅ Écran de recherche avec animations
⏳ Méthode serveur `getPublicRooms` à implémenter
⏳ Routes à ajouter au router
⏳ Tests à créer

### Prochaines Étapes
1. Implémenter `getPublicRooms()` dans `MultiplayerService`
2. Ajouter les routes dans le router
3. Implémenter la logique serveur (Node.js)
4. Tester le flow complet
5. Ajouter des analytics
6. Créer des tests unitaires

## 🎨 Design

### Couleurs
- **Public** : Bleu (`Colors.blue`)
- **Privé** : Vert (`Colors.green`)
- **Recherche** : Bleu avec ombre lumineuse
- **Annulation** : Rouge (`Colors.red.shade700`)

### Animations
- **Pulse** : 1.5s, ease-in-out, reverse
- **Rotation** : 2s, linéaire, infini
- **Scale** : 0.95 → 1.05
- **Transition** : 150ms pour les cartes

## 🧪 Tests Suggérés

```dart
// Test du matchmaking
testWidgets('should navigate to lobby when room found', (tester) async {
  // ...
});

// Test de l'annulation
testWidgets('should cancel matchmaking and go back', (tester) async {
  // ...
});

// Test du timer
test('should increment search duration every second', () {
  // ...
});
```

## 📱 Compatibilité

- ✅ iOS
- ✅ Android  
- ✅ Web
- ✅ macOS

Toutes les plateformes supportées par Flutter sont compatibles.
