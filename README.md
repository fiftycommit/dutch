# DUTCH' 78 🎴

Jeu de cartes de mémoire et stratégie en Flutter/Dart. Une partie oppose 1 joueur humain à 3 bots.

## ✨ Points forts

- Modes Partie rapide et Tournoi (3 manches avec élimination du dernier)
- Phase de mémorisation dédiée + révélation animée après un Dutch
- Défausse collective avec fenêtre de réaction et pénalités en cas d'erreur
- Pouvoirs spéciaux interactifs (7, 10, Valet, Joker)
- Bots à comportements distincts + SBMM basé sur votre RP
- 3 profils, statistiques, rangs et réglages avancés

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
- Méthode de mélange : Détendu / Tactique / Challenger.
- Effets sonores, vibrations, SBMM.

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

## 🗂️ Structure du projet

```
lib/
├── main.dart
├── models/ (card, player, game_state, game_settings)
├── providers/ (game_provider, settings_provider)
├── screens/
│   ├── splash_screen.dart
│   ├── main_menu_screen.dart
│   ├── game_setup_screen.dart
│   ├── memorization_screen.dart
│   ├── game_screen.dart
│   ├── game_screen/center_table.dart
│   ├── dutch_reveal_screen.dart
│   ├── results_screen.dart
│   ├── rules_screen.dart
│   ├── stats_screen.dart
│   └── settings_screen.dart
├── widgets/ (card_widget, player_hand, player_avatar, special_power_dialogs, responsive_dialog)
├── services/ (game_logic, bot_ai, bot_difficulty, stats_service, rp_calculator, sound_service, haptic_service, web_orientation_service)
└── utils/ (screen_utils.dart)
```

## 🧰 Tech stack

- Flutter / Dart
- Provider
- SharedPreferences
- audioplayers
- flutter_svg

## 🙌 Crédits

Réalisé par Max et EL Roy.
