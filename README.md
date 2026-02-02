# DUTCH' 78 🎴

Jeu de cartes de mémoire et stratégie en Flutter/Dart. Une partie oppose 1 joueur humain à des bots (2 à 6 joueurs).

## ✨ Points forts

- Modes Partie rapide et Tournoi (3 manches avec élimination du dernier)
- Phase de mémorisation dédiée + révélation animée après un Dutch
- Défausse collective avec fenêtre de réaction et pénalités en cas d'erreur
- Pouvoirs spéciaux interactifs (7, 10, Valet, Joker)
- Bots à comportements distincts + SBMM basé sur votre RP
- 3 profils, statistiques, rangs et réglages avancés
- Mode multijoueur via serveur Socket.IO (en cours)

## 🕹️ Déroulement d'une partie

1. Choisissez un profil puis un mode (Rapide ou Tournoi).
2. Mémorisez 2 cartes au début de la manche.
3. À votre tour : piochez, puis remplacez une carte ou jetez-la.
4. Si la carte défaussée a un pouvoir, vous pouvez l'activer.
5. Après chaque défausse, la phase "réaction" permet à tout le monde de matcher.
6. Annoncez "DUTCH" avant de piocher si vous pensez avoir le score le plus bas.

## 🎯 Règles express

- Objectif : finir avec le score le plus faible possible.
- Chaque joueur commence avec 4 cartes cachées (la main peut grandir après des pénalités).
- Défausse collective : si vous avez une carte de même valeur que la défausse, vous pouvez la poser. Erreur = carte de pénalité.
- En cas d'égalité, le joueur qui a crié "Dutch" gagne.

### Cartes spéciales (activées quand elles sont défaussées)

- 7️⃣ Regarder une de vos cartes.
- 🔟 Espionner une carte adverse.
- 🤵 Valet : échanger une carte avec un adversaire.
- 🃏 Joker : mélanger la main d'un adversaire.

### Valeur des cartes

| Carte | Points |
| --- | --- |
| Joker / Roi rouge (♥ ♦) | 0 |
| As | 1 |
| 2 à 10 | Valeur faciale |
| Valet | 11 |
| Dame | 12 |
| Roi noir (♠ ♣) | 13 |

## 🤖 Bots & classement

- 3 comportements : Flash (rapide), Hunter (agressif), Tactique (équilibré).
- Niveau manuel (Facile/Moyen/Difficile) ou mode adaptatif SBMM.
- Classement RP par profil (Bronze, Argent, Or, Platine) + historique de parties.

## ⚙️ Réglages

- Vitesse de réaction de la défausse collective.
- Méthode de mélange : Détendu / Tactique / Challenger (branchée sur `ShuffleStrategy`).
- Effets sonores, vibrations, SBMM.

## 🧪 Mélange & pioche (chance)

- Détendu → mélange 100% aléatoire (chance pure).
- Tactique → mélange équilibré (moins d’extrêmes).
- Challenger → pioche exigeante (mauvaises cartes plus accessibles).
- Stratégie ML expérimentale présente (non entraînée, activable via `Difficulty.mix` côté code).

## 🚀 Installation & lancement

### Prérequis

- Flutter SDK 3.x
- Dart SDK 3.x

### Lancer en local

```bash
flutter pub get
flutter run
```

### Web (optionnel)

```bash
flutter run -d chrome
```

### Serveur multijoueur (optionnel)

```bash
cd dutch-server
npm install
npm run dev
```

## 🗂️ Structure du projet

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
└── src/ (Socket.IO server + logique multijoueur)
```

## 🧰 Tech stack

- Flutter / Dart
- Provider
- SharedPreferences
- Hive
- audioplayers
- flutter_svg
- go_router
- socket_io_client / http

Serveur :
- Node.js / TypeScript
- Socket.IO

## 🙌 Crédits

Réalisé par Max et EL Roy.
