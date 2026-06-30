# Dutch'78

Jeu de cartes de mémoire et stratégie en Flutter/Dart. Une partie oppose un joueur humain à des bots, de 2 à 6 joueurs au total.

**Jouer en ligne : [dutch-game.me](https://dutch-game.me)**

## Fonctionnalités

- Modes Partie rapide et Tournoi (trois manches, le dernier est éliminé à chaque tour)
- Phase de mémorisation au début de la manche, puis révélation animée après un Dutch
- Défausse collective avec fenêtre de réaction et pénalité en cas d'erreur
- Pouvoirs spéciaux interactifs (7, 10, Valet, Joker)
- Bots à comportements distincts et matchmaking adaptatif (SBMM) basé sur le RP
- Trois profils, statistiques, rangs et réglages avancés
- Mode multijoueur en ligne via un serveur Socket.IO, avec état partagé sur Redis : une partie reprend même après un redéploiement

## Déroulement d'une partie

1. Choisissez un profil, puis un mode (Rapide ou Tournoi).
2. Mémorisez deux cartes au début de la manche.
3. À votre tour, piochez, puis remplacez une carte ou jetez-la.
4. Si la carte défaussée a un pouvoir, vous pouvez l'activer.
5. Après chaque défausse, la phase de réaction permet à tout le monde de matcher.
6. Annoncez « Dutch » avant de piocher si vous pensez avoir le score le plus bas.

## Règles express

- Objectif : finir avec le score le plus faible possible.
- Chaque joueur commence avec quatre cartes cachées. La main peut grandir après une pénalité.
- Défausse collective : si vous avez une carte de même valeur que la défausse, vous pouvez la poser. Une erreur coûte une carte de pénalité.
- En cas d'égalité, le joueur qui a crié « Dutch » l'emporte.

### Cartes spéciales (activées à la défausse)

- 7 : regarder une de vos cartes.
- 10 : espionner une carte adverse.
- Valet : échanger une carte avec un adversaire.
- Joker : mélanger la main d'un adversaire.

### Valeur des cartes

| Carte | Points |
| --- | --- |
| Joker / Roi rouge (cœur, carreau) | 0 |
| As | 1 |
| 2 à 10 | Valeur faciale |
| Valet | 11 |
| Dame | 12 |
| Roi noir (pique, trèfle) | 13 |

## Bots et classement

- Trois comportements : Flash (rapide), Hunter (agressif), Tactique (équilibré).
- Niveau manuel (Facile, Moyen, Difficile) ou mode adaptatif SBMM.
- Classement RP par profil (Bronze, Argent, Or, Platine) et historique de parties.

## Réglages

- Vitesse de réaction de la défausse collective.
- Méthode de mélange : Détendu, Tactique ou Challenger (branchée sur `ShuffleStrategy`).
- Effets sonores, vibrations, SBMM.

## Mélange et pioche

La méthode de mélange règle la part de chance. Détendu mélange de façon totalement aléatoire, Tactique lisse les extrêmes, et Challenger rend les mauvaises cartes plus accessibles à la pioche. Une stratégie ML expérimentale est présente mais non entraînée ; elle s'active dans le code via `Difficulty.mix`.

## Installation et lancement

Prérequis : Flutter et Dart en version 3.x.

```bash
flutter pub get
flutter run
```

Pour lancer dans le navigateur :

```bash
flutter run -d chrome
```

### Push web (FCM)

`FCM_WEB_VAPID_KEY` est une clé publique, sans risque côté client. Ne jamais committer de clé privée (service account JSON, clé API SMTP, etc.).

1. Copier `env/web.example.json` vers `env/web.local.json`.
2. Renseigner `FCM_WEB_VAPID_KEY` dans `env/web.local.json`.
3. Lancer en local :

```bash
flutter run -d chrome --dart-define-from-file=env/web.local.json
```

Pour le déploiement (`.github/workflows/deploy-server.yml`), la clé est fournie par le secret GitHub `FCM_WEB_VAPID_KEY` et injectée au build via `--dart-define`, sans passer par le repo.

### Serveur multijoueur

```bash
cd dutch-server
npm install
npm run dev
```

## Structure du projet

```
lib/
├── main.dart
├── core/ (di, interfaces, service_locator)
├── models/ (playing_card, player, game_state, game_settings)
├── providers/ (game_provider, settings_provider, multiplayer_game_provider)
├── router/ (app_router)
├── screens/
│   ├── game/ (setup, memorization, game, results, dutch_reveal)
│   ├── menu/ (main, rules, settings, stats, ai_profile)
│   ├── multiplayer/ (menu, lobby, game)
│   └── shared/
├── widgets/ (dialogs, game, multiplayer, ui)
├── services/
│   ├── game/ (game_logic, bot_ai, shuffle_strategy, rp_calculator)
│   ├── learning/ (bot_training, player_learning, ghost_clone)
│   ├── matchmaking/
│   ├── multiplayer/
│   └── ui/ (sound, haptic, stats, emotes, orientation)
└── utils/ (screen_utils.dart)

dutch-server/
└── src/ (serveur Socket.IO et logique multijoueur)
```

## Tech stack

Application (Flutter / Dart) :
- Provider pour l'état, go_router pour la navigation
- Firebase : Auth (Google Sign-In), Firestore, Storage, Cloud Messaging, App Check
- shared_preferences et flutter_secure_storage pour le stockage local
- socket_io_client / http pour le temps réel et les appels serveur
- audioplayers, flutter_svg

Serveur (`dutch-server/`) :
- Node.js / TypeScript, Express
- Socket.IO, avec adaptateur Redis pour partager l'état entre instances
- firebase-admin, rate limiting

Déployé sur un VPS derrière nginx. Le build web et le serveur sont livrés via GitHub Actions (`deploy-server.yml`).

## Crédits

Développé par Max M'BEY.

Merci à EL Roy de m'avoir fait découvrir le jeu, à Irfat pour les tests, et à Leon pour son aide sur le design de la page d'accueil.
