# Refonte Multijoueur Redis

## Objectif

Supprimer la dépendance du multijoueur à un unique process Node.js en mémoire locale, pour permettre :

- le partage d'état entre plusieurs instances ;
- la reprise d'une room après redémarrage/déploiement ;
- l'émission Socket.IO cross-instance ;
- la suppression du risque de perte sèche d'une partie en cours lors d'un basculement de process.

## Contraintes

- Ne pas casser le gameplay existant.
- Ne pas supposer qu'une simple persistance "best effort" suffit.
- Toute étape doit être validée avant de passer à la suivante.
- Si une hypothèse structurelle devient incertaine, on s'arrête et on la requalifie.

## Plan

- [x] 1. Cartographier toutes les dépendances temps réel actuelles.
- [x] 2. Définir le modèle d'état canonique partagé.
- [x] 3. Introduire Redis et l'adapter Socket.IO.
- [x] 4. Persister et recharger les rooms depuis Redis.
- [x] 5. Remplacer les timers mémoire locale par des deadlines persistées et un scheduler sûr.
- [x] 6. Adapter présence/notifications cross-instance.
- [x] 7. Ajouter des tests de reprise et de cohérence multi-instance.
- [x] 8. Valider build/tests et documenter le résultat.

## Journal

### Étape 0

- Statut : en cours
- Action : création du document de suivi.
- Validation : le plan de refonte est posé avant toute modification d'architecture.

### Étape 1

- Statut : terminé
- Action : cartographie des dépendances temps réel existantes.
- Constat validé :
  - `RoomManager` garde l'état canonique des rooms uniquement en mémoire locale.
  - `TimerManager` repose sur des `setTimeout`/`setInterval` locaux, donc incompatibles avec un ownership flottant entre plusieurs instances.
  - `FriendsService` et une partie des notifications live dépendent de maps locales `onlineUsers` / `userFocused`.
  - `room:my_active` et plusieurs handlers lisent encore l'état directement depuis le `RoomManager` local.
  - La synchro Firestore actuelle sert surtout de registre annexe, pas de source canonique de reprise temps réel.
- Décision :
  - Redis devient la source canonique des rooms live.
  - Les deadlines de timers doivent être persistées dans l'état, puis résolues par un scheduler sûr.
  - La présence cross-instance doit passer par Socket.IO + Redis adapter et/ou Redis, pas par des maps mémoire locales.
- Validation :
  - Les points à refondre sont maintenant identifiés avant introduction de Redis.

### Étape 2

- Statut : terminé
- Action : définition du modèle multi-instance sûr.
- Modèle retenu :
  - Redis devient la source canonique des rooms live.
  - Chaque room est sérialisée dans un snapshot Redis.
  - Toute mutation de room passe sous verrou distribué Redis par `roomCode`.
  - Chaque mutation recharge le snapshot le plus récent avant calcul, puis le réécrit après calcul.
  - Socket.IO utilise un adapter Redis pour diffuser les événements cross-instance.
  - Les timers restent pilotés localement par une instance "owner", mais leur deadline est persistée dans le snapshot.
  - L'ownership d'une room est récupérable si le heartbeat de l'owner devient stale.
- Clés Redis prévues :
  - `multiplayer:room:<ROOM_CODE>` : snapshot canonique de la room.
  - `multiplayer:rooms:index` : index des rooms actives.
  - `multiplayer:lock:room:<ROOM_CODE>` : verrou distribué.
  - `multiplayer:presence:user:<UID>` : état de présence global.
- Validation :
  - Le modèle retenu évite les écritures concurrentes aveugles.
  - Il permet la reprise d'une room après arrêt d'une instance.
  - Il ne repose pas sur Firestore pour le temps réel live.

### Étape 3

- Statut : terminé
- Action : introduction de l'infrastructure Redis activable.
- Modifications validées :
  - ajout d'un `RedisService` avec bootstrap explicite, clients dédiés et arrêt propre ;
  - ajout d'un `SharedRoomStore` pour stocker les snapshots de room, l'index des rooms et les verrous distribués ;
  - ajout d'un codec de sérialisation/désérialisation de `Room` pour `Date` / `Map` / `Set` ;
  - branchement de l'adapter Redis Socket.IO au démarrage du serveur quand Redis est activé ;
  - hydratation initiale du `RoomManager` depuis Redis au boot ;
  - persistance opportuniste des rooms depuis `RoomManager` sans casser le mode local.
- Validation :
  - `npm run build` passe après ajout de Redis et du store partagé.
  - Le serveur peut maintenant démarrer avec ou sans Redis selon la configuration.
  - Aucun changement de règle de gameplay n'a encore été introduit à ce stade.

### Étape 4

- Statut : terminé
- Action : faire de Redis une source de reprise réelle pour les rooms.
- Modifications validées :
  - `RoomManager` hydrate son cache depuis Redis au démarrage ;
  - les lectures importantes peuvent recharger une room depuis le store partagé ;
  - les mutations de room passent par un verrou Redis par `roomCode` ;
  - les suppressions de room nettoient aussi l'index Redis.
- Validation :
  - les handlers `game`, `room` et `connection` qui modifient une room passent par `withRoomMutation(...)` ;
  - les snapshots sont rechargés sans perdre `Date` / `Map` / `Set`.

### Étape 5

- Statut : terminé
- Action : rendre les timers de gameplay récupérables.
- Modifications validées :
  - les callbacks de timeout critiques repassent sous verrou distribué avant mutation ;
  - les deadlines de tour sont reconstituées depuis `turnStartTime + turnTimeoutMs` ;
  - la phase de réaction persiste explicitement `reactionDeadlineAt` ;
  - la pause persistée via `pauseStartTime` est désormais reprogrammée au rechargement ;
  - au chargement d'une room Redis, le serveur reprogramme les timers de tour/réaction encore valides ;
  - si une deadline est déjà dépassée au rechargement, la transition correspondante est exécutée immédiatement ;
  - si une pause est déjà expirée au rechargement, le joueur pausant est expulsé et la room reprend automatiquement.
- Validation :
  - le gameplay ne dépend plus uniquement d'un `setTimeout` vivant dans un process particulier pour les phases principales et la pause forcée.

### Étape 6

- Statut : terminé
- Action : adapter les signaux live cross-instance.
- Modifications validées :
  - chaque socket authentifié rejoint désormais un salon Socket.IO `user:<uid>` ;
  - les invitations de room, demandes d'amis acceptées/reçues et notifications de chat ciblent ce salon utilisateur ;
  - `FriendsService` calcule désormais la présence online via `io.in(userRoom).allSockets()` quand Socket.IO est disponible.
- Validation :
  - les notifications live ne dépendent plus d'une map locale de sockets pour atteindre un utilisateur connecté sur une autre instance.

### Étape 7

- Statut : terminé
- Action : ajouter une couverture ciblée de reprise.
- Modifications validées :
  - ajout d'un test `roomSnapshotCodec.test.ts` pour vérifier la fidélité du snapshot Redis ;
  - ajout d'un test de reprise d'une pause expirée via `hydrateFromSharedStore()` ;
  - conservation de la suite serveur existante comme garde-fou de non-régression.
- Validation :
  - le test de codec valide bien la reprise de `createdAt`, `Map`, `Set` et des champs de timer ;
  - le test de reprise valide qu'une pause expirée redémarre correctement la room après hydratation.

### Étape 8

- Statut : terminé
- Action : validation finale.
- Résultats :
  - `npm run build` : OK
  - `npm test` : OK (`557` tests, `0` échec)
- Conclusion :
  - le serveur peut fonctionner en mode local inchangé ;
  - avec Redis activé, l'état des rooms, les émissions Socket.IO cross-instance et la reprise des timers principaux sont maintenant pris en charge ;
  - la pause et son expiration forcée survivent également à un redémarrage/rechargement via Redis.
