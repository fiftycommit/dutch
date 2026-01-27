# Mode multijoueur en ligne - Statut et architecture (mise a jour: 27 janvier 2026)

Ce document remplace l'ancien plan long et sert de reference courte, a jour, pour ce qui est deja implemente et ce qui reste a faire.

## Resume rapide

Le multijoueur tourne maintenant sur une architecture serveur propre (RoomManager + handlers + TimerManager) avec:
- autorite serveur
- deduplication par `clientId` (rejoin propre)
- presence/focus + verification "toujours la"
- systeme "pret" (ready)
- remplissage par bots au moment du start (pas au create)
- chat de lobby
- cleanup des rooms (TTL + joueurs stale/deconnectes)
- tests serveur + Flutter en place

Important: pour que le cleanup stale fonctionne, il faut redeployer/redemarrer le serveur.

---

## Architecture actuelle

### Serveur (Node.js + Socket.IO)

Structure:
- `dutch-server/src/server.ts`
- `dutch-server/src/index.ts`
- `dutch-server/src/services/RoomManager.ts`
- `dutch-server/src/services/TimerManager.ts`
- `dutch-server/src/handlers/connectionHandler.ts`
- `dutch-server/src/handlers/roomHandler.ts`
- `dutch-server/src/handlers/gameHandler.ts`

Principes:
- Le serveur est autoritaire (validation des actions).
- L'etat envoye aux clients est personnalise (cartes cachees pour les autres joueurs).
- Le timer de reaction est calcule cote serveur, avec ancrage temps + grace.

### Client (Flutter)

Pieces principales:
- `lib/services/multiplayer_service.dart`
- `lib/providers/multiplayer_game_provider.dart`
- `lib/screens/multiplayer_menu_screen.dart`
- `lib/screens/multiplayer_lobby_screen.dart`
- `lib/screens/multiplayer_game_screen.dart`
- `lib/widgets/presence_check_overlay.dart`

Principes:
- `MultiplayerService` gere le transport Socket.IO et le ping.
- `MultiplayerGameProvider` centralise l'etat multijoueur pour l'UI.
- Le client conserve un `clientId` persistant pour eviter les doublons au rejoin.

---

## Fonctionnalites deja implementees

### 1) Presence, focus, stale, cleanup

Cote serveur (`RoomManager`):
- `presence:focus` met a jour le focus.
- `client:ping` met a jour `lastSeenAt` via `touchPlayer`.
- detection stale:
  - `stalePlayerMs` (defaut 15s)
  - `cleanupIntervalMs` (defaut 10s)
- cleanup d'une room si:
  - TTL depasse, ou
  - plus aucun joueur considere "connecte/stale"

Consequence attendue:
- si tu fermes un onglet, la room peut rester visible ~20-30 secondes,
  puis elle doit disparaitre (si plus personne n'est la).

Champs clefs cote serveur:
- `Player.connected`
- `Player.focused`
- `Player.lastSeenAt`
- `Room.expiresAt`

### 2) Ready system (pret)

Objectif: on n'est pas pret par defaut.

Cote serveur:
- nouvel evenement `room:ready`
- `Player.ready`
- `startGame` exige:
  - l'hote pret
  - au moins `minPlayers` joueurs humains prets

Cote client:
- bouton "Passer pret" dans le lobby
- blocage du start si pas assez de joueurs prets

### 3) Bots au moment du start

Changement produit:
- on ne configure plus "fillBots" au create
- si moins de `maxPlayers` connectes au moment du start:
  - popup cote hote
  - "Oui, bots" ou "Non"

Cote serveur:
- `startGame(roomCode, { fillBots })`

### 4) Chat de lobby

Cote serveur:
- `chat:send` -> `chat:message`
- limitation simple: message trimme et coupe a 240 chars

Cote client:
- panneau chat dans le lobby
- affichage "Vous" pour ses messages

---

## Evenements reseau importants (actuels)

Room:
- `room:create`
- `room:join`
- `room:ready`
- `room:start_game`
- `room:leave`

Presence:
- `client:ping`
- `presence:focus`
- `presence:ack`
- `presence:update`
- `presence:check`

Chat:
- `chat:send`
- `chat:message`

Jeu:
- `game:draw_card`
- `game:replace_card`
- `game:discard_card`
- `game:take_from_discard`
- `game:call_dutch`
- `game:attempt_match`
- `game:use_special_power`
- `game:complete_swap`
- `game:skip_special_power`
- `game:state_update`

---

## UI/UX actuelle (nouveau flow)

### Ecran multijoueur

Le flow est maintenant:
1) Choisir:
   - "Creer une partie"
   - "Rejoindre une partie"
2) Puis formulaire adapte:
   - Creer: nom + mode (rapide / tournoi)
   - Rejoindre: nom + code

Implementation:
- `lib/screens/multiplayer_menu_screen.dart`

### Lobby

Le lobby inclut:
- code room
- liste joueurs + statut (pret, hote, presence)
- bouton "Passer pret"
- bouton start cote hote
- popup bots si table incomplete
- chat

Implementation:
- `lib/screens/multiplayer_lobby_screen.dart`

---

## Tests (a garder verts)

### Flutter

Commandes:
- `flutter analyze`
- `flutter test`

Tests ajoutes:
- `test/multiplayer_game_settings_test.dart`
- `test/multiplayer_game_provider_test.dart`

### Serveur

Commande:
- `cd dutch-server && npm test`

Runner:
- `dutch-server/package.json` -> `npm run build && node --test dist/__tests__/*.test.js`

Tests ajoutes:
- `dutch-server/src/__tests__/roomManager.multiplayer.test.ts`
  - minPlayers / fillBots
  - timeout -> presence check -> spectateur
  - cleanup TTL
  - cleanup si tout le monde deco

---

## Points d'attention / debug rapide

### "Je ferme l'onglet et la room existe encore"

Verifier dans cet ordre:
1) Le serveur a bien ete redeploye/redemarre.
2) Attendre ~30 secondes (stale + cleanup).
3) Regarder `/rooms` apres ce delai.

Si besoin, on peut ajouter un endpoint debug type `/rooms/debug` avec
`connected / lastSeenAt / stale` pour valider en prod.

---

## Prochaines etapes recommandees (shortlist)

1) Ajouter un endpoint debug `/rooms/debug` (admin only).
2) Rendre le chat un peu plus robuste:
   - rate limit
   - historique limite par room
3) Ajouter tests serveurs supplementaires:
   - rejoin par `clientId` apres stale
   - host qui deco -> nouveau host
4) Ajuster la charte graphique si necessaire via le Theme global (plutot que par ecran).

---

## Reference: fichiers modifies recemment

Serveur:
- `dutch-server/src/services/RoomManager.ts`
- `dutch-server/src/handlers/roomHandler.ts`
- `dutch-server/src/handlers/connectionHandler.ts`
- `dutch-server/src/models/Player.ts`
- `dutch-server/src/models/Room.ts`
- `dutch-server/src/__tests__/roomManager.multiplayer.test.ts`
- `dutch-server/package.json`

Client:
- `lib/services/multiplayer_service.dart`
- `lib/providers/multiplayer_game_provider.dart`
- `lib/screens/multiplayer_menu_screen.dart`
- `lib/screens/multiplayer_lobby_screen.dart`
- `lib/screens/multiplayer_game_screen.dart`
- `lib/widgets/presence_check_overlay.dart`

