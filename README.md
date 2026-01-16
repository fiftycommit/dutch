# Dutch Card Game 🎴

Un jeu de cartes stratégique et de mémoire développé en Flutter/Dart.

## 🎯 Description

Dutch est un jeu de cartes où le but est d'obtenir le score le plus faible possible. Chaque joueur a 4 cartes cachées et doit les mémoriser pour faire les meilleurs choix stratégiques.

### Fonctionnalités principales

✅ **2 modes de jeu**
- Partie Rapide (2-4 joueurs)
- Tournoi (4 joueurs, 3 manches)

✅ **8 personnalités de bots différentes**
- 🤪 Bob le Distrait (Débutant)
- 😅 Sophie la Novice
- 😈 Marco l'Agressif
- 🤓 Julie la Prudente
- 😎 Alex l'Équilibré
- 🧠 Léa la Calculatrice
- 🎯 Chen le Stratège
- 👑 Nadia la Légende

✅ **Cartes spéciales avec pouvoirs**
- 7️⃣ : Regarder une de vos cartes
- 🔟 : Regarder une carte adverse
- 🤵 Valet : Échanger 2 cartes
- 🃏 Joker : Mélanger le jeu d'un adversaire

✅ **Interface style poker réaliste**

## 🚀 Installation

### Prérequis

- Flutter SDK 3.0+ ([Installation](https://docs.flutter.dev/get-started/install))
- Dart SDK 3.0+
- Un émulateur Android/iOS ou un appareil physique

### Étapes

1. **Cloner/Copier les fichiers du projet**

```bash
cd dutch_game
```

2. **Installer les dépendances**

```bash
flutter pub get
```

3. **Générer les fichiers Hive (pour la sauvegarde)**

```bash
flutter pub run build_runner build
```

4. **Lancer l'application**

```bash
# Sur un émulateur/appareil connecté
flutter run

# Pour le web (optionnel)
flutter run -d chrome

# Pour une build release
flutter build apk  # Android
flutter build ios  # iOS
```

## 📱 Utilisation

### Début de partie

1. Sélectionnez un slot de sauvegarde (1, 2 ou 3)
2. Choisissez le mode de jeu :
   - **Partie Rapide** : Une seule manche
   - **Tournoi** : 3 manches avec élimination
3. Configurez vos adversaires (sélection des bots)
4. Lancez la partie !

### Pendant le jeu

**Phase initiale :**
- Sélectionnez 2 cartes à révéler parmi vos 4 cartes

**À votre tour :**
1. Piochez une carte
2. Décidez de :
   - La garder (remplacer une de vos cartes)
   - La défausser
3. Si la carte est spéciale, activez son pouvoir (optionnel)

**Fin de partie :**
- Criez "DUTCH!" quand vous pensez avoir le score le plus bas
- Si vous avez raison → Vous gagnez ! 🏆
- Sinon → Vous êtes éliminé 😢

## 🎮 Règles complètes

### Valeurs des cartes

| Carte | Points |
|-------|--------|
| Roi Rouge ♥ ♦ | 0 |
| Joker 🃏 | 0 |
| As | 1 |
| 2-10 | Valeur faciale |
| Valet | 11 |
| Dame | 12 |
| Roi Noir ♠ ♣ | 13 |

### Objectif

Avoir le score le plus **faible** possible (idéalement 0).

## 🏗️ Architecture du projet

```
lib/
├── main.dart                 # Point d'entrée
├── models/                   # Modèles de données
│   ├── card.dart
│   ├── player.dart
│   ├── game_state.dart
│   └── save_slot.dart
├── providers/                # Gestion d'état (Provider)
│   └── game_provider.dart
├── screens/                  # Écrans de l'app
│   ├── main_menu_screen.dart
│   ├── game_setup_screen.dart
│   ├── game_screen.dart
│   └── results_screen.dart
├── widgets/                  # Composants réutilisables
│   ├── card_widget.dart
│   └── player_hand.dart
└── services/                 # Logique métier
    ├── game_logic.dart
    └── bot_ai.dart
```

## 🛠️ Technologies utilisées

- **Framework** : Flutter 3.24+
- **Langage** : Dart 3.0+
- **Gestion d'état** : Provider
- **Stockage local** : Hive
- **Audio** : audioplayers (à implémenter)

## 📋 TODO / Améliorations futures

### Priorité Haute
- [ ] Implémenter les pouvoirs spéciaux dans l'UI
- [ ] Ajouter le système d'XP et déblocage des bots
- [ ] Implémenter la sauvegarde avec Hive
- [ ] Ajouter les animations de cartes

### Priorité Moyenne
- [ ] Ajouter les effets sonores
- [ ] Intégrer la musique de fond
- [ ] Implémenter la règle de défausse en chaîne
- [ ] Ajouter un tutoriel interactif
- [ ] Améliorer l'IA des bots

### Priorité Basse
- [ ] Multijoueur local
- [ ] Intégration Apple Music/Spotify
- [ ] Thèmes de cartes personnalisables
- [ ] Système d'achievements

## 🐛 Problèmes connus

- Les pouvoirs spéciaux ne sont pas encore implémentés dans l'interface
- Le système de sauvegarde n'est pas encore connecté
- Animations à améliorer
- Sons/musique non implémentés

## 📄 License

Ce projet est sous licence MIT. Libre d'utilisation et de modification.

## 👥 Contributeurs

- Développement initial : Claude (AI Assistant)
- Direction du projet : [Votre nom]

## 🙏 Remerciements

Merci d'avoir choisi de jouer à Dutch ! 🎴

---

**Bon jeu ! 🍀**
# dutch
