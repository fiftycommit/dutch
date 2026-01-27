# Dutch Game Server

Backend Node.js + Socket.IO pour le mode multijoueur du jeu Dutch.

## Installation

```bash
npm install
```

## Configuration

Copier `.env.example` vers `.env` et ajuster les valeurs :

```bash
cp .env.example .env
```

## Développement

Lancer le serveur en mode développement avec hot reload :

```bash
npm run dev
```

## Production

Compiler le TypeScript :

```bash
npm run build
```

Lancer le serveur compilé :

```bash
npm start
```

## Architecture

```
src/
├── index.ts              # Point d'entrée du serveur
├── models/
│   ├── Card.ts           # Modèle PlayingCard
│   ├── Player.ts         # Modèle Player
│   ├── GameState.ts      # État du jeu
│   └── Room.ts           # Room multijoueur
├── services/             # Services métier (à implémenter)
│   ├── RoomManager.ts    # Gestion des rooms
│   ├── GameLogic.ts      # Port des règles du jeu
│   ├── BotAI.ts          # IA des bots
│   └── TimerManager.ts   # Gestion des timers
└── handlers/             # Handlers Socket.IO (à implémenter)
    ├── connectionHandler.ts
    ├── roomHandler.ts
    └── gameHandler.ts
```

## API Socket.IO

### Événements client → serveur

- `room:create` - Créer une room
- `room:join` - Rejoindre une room
- `room:start_game` - Démarrer la partie (hôte uniquement)
- `room:leave` - Quitter une room

### Événements serveur → client

- `room:player_joined` - Un joueur a rejoint
- `game:state_update` - Mise à jour de l'état du jeu
- `game:timer_update` - Mise à jour du timer de réaction

## API REST

- `GET /health` - Santé du serveur
- `GET /rooms` - Liste des rooms actives

## TODO

- [ ] Implémenter GameLogic complet (port depuis Dart)
- [ ] Implémenter BotAI complet (port depuis Dart)
- [ ] Implémenter RoomManager et TimerManager
- [ ] Ajouter gestion des déconnexions
- [ ] Ajouter validation des actions côté serveur
- [ ] Ajouter persistence (MongoDB/PostgreSQL)
- [ ] Ajouter tests unitaires
- [ ] Ajouter rate limiting
