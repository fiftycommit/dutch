# Changelog - Dutch Server

## [2025-01-26] - Port de la logique de jeu

### Ajouts

#### Services de jeu (`src/services/`)
- **GameLogic.ts** (~330 lignes)
  - Initialisation de partie
  - Gestion de la pioche et de la défausse
  - Actions de jeu (piocher, remplacer, matcher, etc.)
  - Pouvoirs spéciaux (7, 10, Valet, Joker)
  - Appel Dutch et fin de partie
  - Logique strictement identique au client Flutter

- **BotDifficulty.ts** (~90 lignes)
  - Définition des 4 niveaux de difficulté (Bronze, Argent, Or, Platine)
  - Paramètres de comportement des bots
  - Conversion MMR → Difficulté
  - Conversion Rang → Difficulté

- **BotAI.ts** (~1100 lignes)
  - Intelligence artificielle complète des bots
  - 3 comportements : Fast, Aggressive, Balanced
  - 3 phases de jeu : Exploration, Optimization, Endgame
  - Gestion de la mémoire des bots (mentalMap, dutchHistory, consecutiveBadDraws)
  - Stratégie pour l'appel Dutch avec calcul d'audacité et de confiance
  - Décision de garde/défausse de cartes
  - Matching en réaction
  - Stratégies pour l'utilisation des pouvoirs spéciaux
  - Match à l'aveugle pour les niveaux Or/Platine
  - Prise en compte du mode Tournoi avec pression selon le score cumulé

- **index.ts**
  - Exports centralisés des services

- **example.ts**
  - Exemple d'utilisation des services
  - Simulation d'une partie avec 1 humain et 2 bots
  - Démonstration des méthodes principales

- **README.md**
  - Documentation complète des services
  - Guide d'utilisation
  - Exemples de code
  - Différences avec le client Flutter

### Caractéristiques techniques

- **Langage** : TypeScript avec typage strict
- **Compatibilité** : Logique identique au client Flutter (Dart)
- **Architecture** : Séparation claire des responsabilités
  - Models : Structures de données partagées client/serveur
  - Services : Logique métier côté serveur uniquement
- **Mémoire des bots** : Gérée dans une Map interne à BotAI (non transmise aux clients)
- **Async/Await** : Gestion asynchrone pour les délais de réflexion des bots

### Adaptations Dart → TypeScript

1. **Random** : `Random()` → `Math.random()`
2. **Types** : Utilisation de TypeScript pour le typage
3. **Async** : `Future` → `Promise`
4. **Arrays** : Méthodes natives JS au lieu des extensions Dart
5. **Enums** : Compatibles entre les deux langages

### Éléments non portés (spécifiques au client)

- Sons et vibrations (UI)
- Dialogs et notifications visuelles (UI)
- Provider/State management (remplacé par Socket.IO)
- Fonctions de rendu et d'affichage

### Statistiques

- **Lignes de code** : ~1727 lignes (TypeScript)
- **Fichiers créés** : 6 fichiers
- **Taux de port** : 100% de la logique métier portée
- **Tests** : Exemple fonctionnel validé

### Prochaines étapes suggérées

1. Intégrer GameLogic et BotAI dans `index.ts` pour le serveur Socket.IO
2. Créer les handlers pour les actions de jeu
3. Gérer la synchronisation multi-joueurs
4. Ajouter la gestion des salles de jeu
5. Implémenter le système de matchmaking (SBMM)
6. Ajouter des tests unitaires
