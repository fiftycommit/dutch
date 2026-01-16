# Spécifications Techniques - Jeu Dutch (Flutter/Dart)

## 1. Vue d'ensemble du projet

### 1.1 Description
Jeu de cartes "Dutch" - un jeu de mémoire et stratégie où le but est d'obtenir le score le plus faible possible en gérant intelligemment ses 4 cartes cachées.

### 1.2 Plateforme cible
- Application mobile (iOS/Android) prioritaire
- Web et Desktop en bonus si le temps le permet

### 1.3 Technologies
- **Framework** : Flutter 3.x
- **Langage** : Dart
- **Gestion d'état** : Provider ou Riverpod
- **Base de données locale** : Hive ou SharedPreferences pour les sauvegardes
- **Audio** : audioplayers package
- **Animations** : Flutter Animation Framework natif

---

## 2. Règles du jeu (version détaillée)

### 2.1 Configuration de base
- **Joueurs** : 2 à 4 joueurs (1 humain + 1 à 3 bots)
- **Deck** : 52 cartes standard + 2 Jokers = 54 cartes
- **Cartes par joueur** : 4 cartes disposées en ligne horizontale

### 2.2 Début de partie
1. Distribution de 4 cartes face cachée à chaque joueur
2. Chaque joueur peut retourner et regarder 2 cartes de son choix (une seule fois au début)
3. Les cartes peuvent être réorganisées à tout moment (sans les regarder)
4. La pioche est placée au centre
5. Une carte de départ est placée dans la défausse

### 2.3 Tour de jeu
**Chaque joueur à son tour :**
1. Pioche une carte
2. Regarde la carte piochée
3. Décide de :
   - **Option A** : Garder la carte piochée
     - Remplace une de ses 4 cartes par la carte piochée
     - La carte remplacée va dans la défausse
   - **Option B** : Défausser directement la carte piochée
     - La carte va dans la défausse (visible par tous)

### 2.4 Cartes spéciales (activées uniquement lors de la défausse)
Quand une carte spéciale est défaussée, le joueur peut choisir d'activer son pouvoir ou non :

- **7** : Regarder une de ses cartes cachées
- **10** : Regarder une carte du jeu d'un adversaire (au choix)
- **Valet (V)** : Échanger deux cartes au choix :
  - Une de ses cartes avec une carte d'un adversaire
  - Ou deux cartes entre deux adversaires
- **Joker** : Mélanger le jeu complet (4 cartes) d'un adversaire au choix

### 2.5 Règle spéciale : Défausse en chaîne
Si un joueur défausse une carte (ex: 4 de cœur) et qu'un autre joueur possède la même valeur (ex: 4 de pique), ce dernier peut immédiatement se débarrasser de sa carte, réduisant ainsi son deck.
**Note** : Fonctionnalité bonus, à implémenter en priorité secondaire.

### 2.6 Fin de partie - "DUTCH!"
- À son tour, un joueur peut crier "DUTCH" au lieu de piocher
- La partie s'arrête immédiatement
- Tous les joueurs révèlent leurs cartes
- Calcul des scores

**Résultats :**
- Si le joueur qui a crié "Dutch" a le score le plus bas → Il gagne
- Si égalité avec le score le plus bas → Le joueur "Dutch" gagne quand même
- Classement : 1er (plus bas score), 2ème, 3ème, 4ème (plus haut score)
- En mode tournoi : Le joueur avec le score le plus élevé est éliminé

### 2.7 Valeurs des cartes
| Carte | Points |
|-------|--------|
| Roi Rouge (Cœur/Carreau) | 0 |
| Joker | 0 |
| As | 1 |
| 2 | 2 |
| 3 | 3 |
| 4 | 4 |
| 5 | 5 |
| 6 | 6 |
| 7 | 7 |
| 8 | 8 |
| 9 | 9 |
| 10 | 10 |
| Valet (V) | 11 |
| Dame (Q) | 12 |
| Roi Noir (Pique/Trèfle) | 13 |

---

## 3. Modes de jeu

### 3.1 Mode Partie Rapide
- Une seule manche
- 2 à 4 joueurs (configurable)
- Pas d'élimination
- Affichage du classement final

### 3.2 Mode Tournoi
- Configuration : 4 joueurs obligatoirement
- Structure :
  - **Manche 1** (Quart de finale) : 4 joueurs → 1 éliminé → 3 restants
  - **Manche 2** (Demi-finale) : 3 joueurs → 1 éliminé → 2 restants
  - **Manche 3** (Finale) : 2 joueurs → 1 gagnant
- **Important** : Chaque manche repart de zéro (comme au football), pas d'accumulation de score entre manches
- Le gagnant d'une manche n'est pas protégé pour la suivante

---

## 4. Architecture technique

### 4.1 Structure du projet (dossiers)
```
lib/
├── main.dart
├── models/
│   ├── card.dart
│   ├── player.dart
│   ├── game_state.dart
│   └── save_slot.dart
├── providers/
│   ├── game_provider.dart
│   └── save_provider.dart
├── screens/
│   ├── splash_screen.dart
│   ├── main_menu_screen.dart
│   ├── save_slot_screen.dart
│   ├── game_setup_screen.dart
│   ├── game_screen.dart
│   └── results_screen.dart
├── widgets/
│   ├── card_widget.dart
│   ├── player_hand.dart
│   ├── deck_widget.dart
│   ├── discard_pile.dart
│   └── action_button.dart
├── services/
│   ├── bot_ai.dart
│   ├── game_logic.dart
│   ├── audio_service.dart
│   └── save_service.dart
├── utils/
│   ├── constants.dart
│   └── card_images.dart
└── assets/
    ├── images/
    │   └── cards/
    ├── sounds/
    └── music/
```

### 4.2 Modèles de données

#### Card
```dart
class Card {
  final String suit; // 'hearts', 'diamonds', 'clubs', 'spades', 'joker'
  final String value; // 'A', '2', ..., '10', 'J', 'Q', 'K', 'JOKER'
  final int points;
  final bool isSpecial;
  
  // Méthodes
  String getImagePath();
  bool isRed();
}
```

#### Player
```dart
class Player {
  final String id;
  final String name;
  final bool isHuman;
  final String? botPersonality; // 'aggressive', 'cautious', 'balanced'
  List<Card?> hand; // 4 cartes (null si défaussée)
  List<bool> knownCards; // true si le joueur connaît la carte
  int currentScore;
  
  // Méthodes
  int calculateScore();
  void revealCard(int index);
}
```

#### GameState
```dart
class GameState {
  List<Player> players;
  List<Card> deck;
  List<Card> discardPile;
  int currentPlayerIndex;
  String gameMode; // 'quick', 'tournament'
  int tournamentRound; // 1, 2, 3
  bool gameEnded;
  
  // Méthodes
  void nextTurn();
  void drawCard();
  void playCard();
}
```

#### SaveSlot
```dart
class SaveSlot {
  final int slotNumber; // 1, 2, 3
  String playerName;
  int totalXP; // Système de progression
  int currentLevel; // Calculé à partir de l'XP
  
  // Stats de tournoi
  int tournamentsWon; // 🏆
  int finalistCount; // 🥈
  int semifinalistCount; // 🥉
  int quarterfinalistCount;
  int tournamentsPlayed;
  
  // Stats générales
  int quickGamesPlayed;
  int quickGamesWon;
  int bestScore; // Record de score le plus bas
  int dutchSuccessCount;
  
  DateTime lastPlayed;
  
  // Bots débloqués
  List<String> unlockedBotTiers; // ['beginner', 'intermediate', 'expert', 'master']
  
  // Méthodes
  int calculateLevel(); // XP → Niveau
  int xpToNextLevel(); // XP restant avant prochain niveau
  bool isBotTierUnlocked(String tier);
}
```

---

## 5. Écrans et flux utilisateur

### 5.1 Splash Screen
- Logo du jeu "Dutch"
- Animation de chargement
- Transition automatique vers Menu Principal

### 5.2 Menu Principal
**Éléments visuels inspirés de l'image Mario :**
- **Slots de sauvegarde** (3 slots en haut)
  - Affichage : Nom du joueur, nombre de pièces/étoiles, dernière partie jouée
  - Boutons : Sélectionner, Effacer, Copier
  - Slot sélectionné mis en évidence (bordure dorée)
  
- **Modes de jeu** (2 gros boutons en bas)
  - "Partie Rapide" (bouton vert)
  - "Tournoi" (bouton doré)

- **Options supplémentaires** (icônes en coin)
  - Paramètres (son, musique, règles)
  - Crédits

### 5.3 Écran de Configuration (avant la partie)
- Sélection du nombre de joueurs (2-4)
- Personnalisation des bots :
  - Bot 1 : "Agressif" (icon 😈) - Crie Dutch rapidement
  - Bot 2 : "Prudent" (icon 🤓) - Joue safe, mémorise bien
  - Bot 3 : "Équilibré" (icon 😎) - Mix des deux
- Bouton "Lancer la partie"

### 5.4 Écran de Jeu Principal

**Layout :**
```
┌─────────────────────────────────────┐
│   Bot 3 (Haut)                      │
│   [🂠][🂠][🂠][🂠]                    │
├───────────────────┬─────────────────┤
│ Bot 1 (Gauche)    │   Bot 2 (Droite)│
│ [🂠]              │              [🂠] │
│ [🂠]       [DECK]  │   [DISCARD]  [🂠] │
│ [🂠]       [🂠]    │     [🂧]     [🂠] │
│ [🂠]              │              [🂠] │
├───────────────────┴─────────────────┤
│   Joueur Humain (Bas)               │
│   [🂱][🂲][🂳][🂴]                    │
│   [Piocher] [DUTCH!]                │
└─────────────────────────────────────┘
```

**Éléments interactifs :**
- **Cartes du joueur** :
  - Tap pour voir la carte (si autorisé)
  - Long press pour réorganiser
  - Indicateur visuel : carte connue vs inconnue
  
- **Pioche (Deck)** :
  - Bouton "Piocher" ou tap direct
  - Animation de retournement
  
- **Défausse (Discard Pile)** :
  - Affiche la dernière carte défaussée
  - Tap pour voir les 8 dernières cartes (carrousel)
  
- **Bouton "DUTCH!"** :
  - Gros bouton rouge visible uniquement au tour du joueur
  - Confirmation popup avant validation

**Affichage d'informations :**
- Tour actuel (indicateur visuel autour du joueur)
- Score estimé du joueur (si cartes connues)
- Nombre de cartes restantes dans la pioche
- Historique des actions (mini-log déroulant)

**Actions spéciales (quand carte spéciale défaussée) :**
- Popup modale avec choix :
  - "Activer le pouvoir"
  - "Passer"
- Interface adaptée selon le pouvoir (sélection de carte, sélection de joueur, etc.)

### 5.5 Écran de Résultats

**Affichage :**
- Classement final avec animations
- Cartes révélées de chaque joueur
- Score détaillé (carte par carte)
- En mode tournoi : Qui est éliminé + passage à la manche suivante

**Boutons :**
- "Rejouer"
- "Menu Principal"
- "Revanche" (même configuration)

---

## 6. Intelligence Artificielle des Bots

### 6.1 Bot "Agressif" 😈
**Comportement :**
- Crie "Dutch" rapidement (score autour de 12-15)
- Prend plus de risques avec les cartes spéciales
- Défausse souvent pour activer des pouvoirs
- Utilise le Joker agressivement (mélange l'adversaire le mieux placé)
- Mémorisation moyenne (70% de précision)

**Stratégie :**
- Priorité aux cartes de faible valeur
- Utilise le 10 pour espionner le leader
- Échange avec le Valet si opportun

### 6.2 Bot "Prudent" 🤓
**Comportement :**
- Attend d'avoir un score très bas avant "Dutch" (score < 8)
- Mémorise parfaitement ses cartes et celles des autres (95% de précision)
- Utilise les cartes spéciales de manière optimale
- Évite les risques inutiles

**Stratégie :**
- Calcule les probabilités de pioche
- Optimise les échanges avec le Valet
- Utilise le 7 stratégiquement pour vérifier ses cartes

### 6.3 Bot "Équilibré" 😎
**Comportement :**
- Mélange entre agressivité et prudence
- Crie "Dutch" à score moyen (autour de 10)
- Mémorisation correcte (85% de précision)
- S'adapte à la situation de jeu

**Stratégie :**
- Joue en fonction du contexte (position dans la partie)
- Utilise les pouvoirs de manière opportuniste
- Équilibre risque/récompense

### 6.4 Système de décision (pour tous les bots)

**Algorithme de base :**
1. **Évaluation du contexte**
   - Score actuel estimé
   - Cartes connues vs inconnues
   - Position des autres joueurs
   - Nombre de tours restants estimé

2. **Décision de pioche/défausse**
   - Si carte piochée < moyenne des cartes connues → Garder
   - Sinon, comparer avec la carte à remplacer (si connue)
   - Facteur aléatoire selon personnalité

3. **Utilisation des pouvoirs**
   - Probabilité d'activation selon personnalité
   - Ciblage intelligent (joueur le plus dangereux)

4. **Décision "Dutch"**
   - Calcul du score estimé
   - Seuil de décision selon personnalité
   - Facteur aléatoire (éviter la prévisibilité)

---

## 7. Système de progression et déblocage de bots

### 7.1 Système d'XP et niveaux
- **Gain d'XP** :
  - Victoire partie rapide : +50 XP
  - Quart de finaliste (tournoi) : +50 XP
  - Demi-finaliste (tournoi) : +100 XP
  - Finaliste (tournoi) : +200 XP
  - Bonus : Premier "Dutch" réussi : +25 XP
  - Bonus : Score parfait (0 points) : +100 XP

- **Paliers de niveaux** (progression exponentielle) :
  - Niveau 1 : 0 XP (début)
  - Niveau 2 : 500 XP
  - Niveau 3 : 1500 XP
  - Niveau 4 : 3000 XP
  - Niveau 5 : 5000 XP
  - Niveau 6 : 7500 XP
  - Niveau 7 : 10500 XP
  - Niveau 8 : 14000 XP
  - Niveau 9 : 18000 XP
  - Niveau 10 : 23000 XP
  - Niveau 10+ : +6000 XP par niveau

### 7.2 Déblocage des tiers de bots

#### Tier 1 : Bots "Débutant" (Niveau 1 - débloqué par défaut)
- **Bob le Distrait** 🤪
  - Mémorisation : 40%
  - Crie Dutch à score élevé (18-25)
  - Oublie souvent ses cartes
  - Utilise mal les cartes spéciales
  
- **Sophie la Novice** 😅
  - Mémorisation : 50%
  - Joue de manière aléatoire
  - Crie Dutch trop tôt ou trop tard
  - Utilise parfois les cartes spéciales

#### Tier 2 : Bots "Intermédiaire" (Niveau 3)
- **Marco l'Agressif** 😈
  - Mémorisation : 70%
  - Crie Dutch rapidement (12-15)
  - Utilise les pouvoirs offensivement
  - Prend des risques calculés

- **Julie la Prudente** 🤓
  - Mémorisation : 85%
  - Attend un score bas (< 8)
  - Optimise les échanges
  - Joue la sécurité

#### Tier 3 : Bots "Expert" (Niveau 5)
- **Alex l'Équilibré** 😎
  - Mémorisation : 90%
  - Score cible : ~10
  - S'adapte à la situation
  - Stratégie mixte

- **Léa la Calculatrice** 🧠
  - Mémorisation : 95%
  - Calcule les probabilités
  - Timing parfait pour Dutch
  - Utilisation optimale des pouvoirs

#### Tier 4 : Bots "Maître" (Niveau 10)
- **Chen le Stratège** 🎯
  - Mémorisation : 98%
  - Prédit les actions des autres
  - Manipulation psychologique (bluff)
  - Timing parfait, jamais prévisible

- **Nadia la Légende** 👑
  - Mémorisation : 99%
  - Joue comme un pro
  - Adaptation instantanée
  - Très difficile à battre

### 7.3 Affichage de la progression
- **Barre d'XP** animée après chaque partie
- **Level up** : Animation + notification
- **Déblocage** : Écran spécial "Nouveau bot débloqué !" avec présentation
- **Tableau de progression** accessible depuis le menu :
  - Niveau actuel
  - XP actuel / XP prochain niveau
  - Tous les bots (verrouillés en grisé avec icône cadenas)
  - Stats détaillées par bot (victoires contre chacun)

---

## 8. Système de Sauvegarde (3 slots style Mario)

### 8.1 Structure des 3 slots
Chaque slot contient :
- **Nom du joueur** (personnalisable)
- **Niveau et XP** (système de progression)
  - +50 XP par victoire en partie rapide
  - +200 XP par victoire en tournoi (finaliste)
  - +100 XP par demi-finaliste
  - +50 XP par quart de finaliste
  - Paliers : Niveau 1 = 0 XP, Niveau 2 = 500 XP, Niveau 3 = 1500 XP, etc.
- **Bots débloqués** :
  - Niveau 1 : Bots "Débutant" (faibles)
  - Niveau 3 : Bots "Intermédiaire" débloqués
  - Niveau 5 : Bots "Expert" débloqués
  - Niveau 10 : Bots "Maître" débloqués (ultra forts)
- **Statistiques de tournoi** :
  - Tournois gagnés (🏆)
  - Finaliste (🥈)
  - Demi-finaliste (🥉)
  - Quart de finaliste
  - Tournois joués
- **Statistiques générales** :
  - Parties jouées (total)
  - Victoires (partie rapide)
  - Ratio victoire
  - Record de score le plus bas (meilleur 0 parfait)
  - Nombre de "Dutch" réussis
- **Date de dernière partie**

### 8.2 Fonctionnalités
- **Copier** : Dupliquer un slot vers un slot vide
- **Effacer** : Réinitialiser un slot (avec confirmation)
- **Sélectionner** : Charger le slot pour jouer
- **Déblocage progressif** : 
  - Affichage visuel des bots verrouillés/débloqués
  - Indication du niveau requis pour débloquer
  - Notification lors du déblocage d'un nouveau niveau de bots

### 8.3 Persistence
- Stockage local avec Hive ou SharedPreferences
- Auto-sauvegarde après chaque partie
- Backup possible (export/import JSON)

---

## 9. Audio et Musique

### 9.1 Effets sonores nécessaires
- **Général** :
  - Tap sur bouton
  - Validation
  - Erreur/Annulation
  
- **Jeu** :
  - Mélange des cartes (shuffle)
  - Pioche d'une carte
  - Défausse d'une carte
  - Retournement de carte
  - Réorganisation de cartes
  
- **Actions spéciales** :
  - Activation pouvoir carte 7
  - Activation pouvoir carte 10
  - Activation pouvoir Valet
  - Activation pouvoir Joker (mélange)
  
- **Événements** :
  - "DUTCH!" (son dramatique)
  - Victoire
  - Défaite
  - Élimination (en tournoi)

### 9.2 Musique de fond
- **Option 1** : Musique intégrée
  - Musique de menu (calme, accueillante)
  - Musique de jeu (tension modérée, rythmée)
  - Musique de victoire (joyeuse)
  
- **Option 2** : Intégration Apple Music/Spotify (bonus)
  - Connexion à l'API de streaming
  - Sélection de playlist
  - Lecture aléatoire pendant le jeu
  - Contrôles de lecture (pause, skip)

### 9.3 Paramètres audio
- Volume effets sonores (0-100%)
- Volume musique (0-100%)
- Activer/Désactiver sons
- Activer/Désactiver musique

---

## 10. Assets nécessaires

### 10.1 Graphismes - Cartes
- **52 cartes standard** (PNG transparent, 200x300px recommandé)
  - 13 cartes x 4 couleurs (Cœur, Carreau, Pique, Trèfle)
- **2 Jokers** (designs différents ou identiques)
- **Dos de carte** (design unique pour la pioche)
- **Placeholder** : Carte vide pour slots vides

**Sources possibles :**
- Création custom (Figma, Illustrator)
- Assets gratuits (OpenGameArt, itch.io)
- Pack de cartes sous licence libre

### 10.2 UI/UX
- Icônes des bots (8 bots au total avec personnalités distinctes)
- Badges de niveau (1-10+)
- Indicateur de bots débloqués/verrouillés
- Boutons (Piocher, Dutch, Activer pouvoir, etc.)
- Backgrounds (table de poker réaliste inspirée des images fournies)
- Animations de particules (victoire, Dutch, level up)
- Indicateurs visuels (tour actuel, carte connue/inconnue)
- Barre d'XP animée
- Médailles/trophées (🏆 🥈 🥉)

### 10.3 Sons
- Bibliothèques gratuites : Freesound.org, OpenGameArt
- Génération avec IA : ElevenLabs (effets), Suno (musique courte)

---

## 11. Animations et transitions

### 11.1 Animations de cartes
- **Pioche** : Carte sort du deck avec rotation 3D
- **Défausse** : Carte glisse vers la pile avec courbe
- **Retournement** : Flip 3D (face cachée → face visible)
- **Échange** (Valet) : Animation de swap avec arc
- **Mélange** (Joker) : Effet de tourbillon sur le deck ciblé
- **Révélation finale** : Toutes les cartes se retournent en séquence

### 11.2 Transitions d'écrans
- Fade in/out entre écrans
- Slide pour les modales
- Bounce pour les popups de victoire
- **Level up** : Animation spéciale (éclat de lumière + confettis)
- **Déblocage de bot** : Révélation avec effet dramatique

### 11.3 Feedback visuel
- Highlight au survol/tap
- Shake pour erreur
- Glow pour carte connue
- Pulse pour bouton "Dutch" (attirer l'attention)

---

## 12. Fonctionnalités bonus (si temps disponible)

### 12.1 Priorité 1 (importantes)
- ✅ Défausse en chaîne (règle spéciale valeurs identiques)
- ✅ Historique détaillé des actions
- ✅ Replay de la partie (revoir les coups joués)
- ✅ Tutoriel interactif pour nouveaux joueurs

### 12.2 Priorité 2 (nice to have)
- Multijoueur local (même appareil, écrans séparés)
- Thèmes de cartes (classique, moderne, néon)
- Succès/Achievements (débloquer avec XP)
- Personnalisation de l'avatar joueur
- Leaderboard local (top 10 des meilleurs scores)
- Stats détaillées par bot (graphiques de progression)

### 12.3 Priorité 3 (future)
- Multijoueur en ligne (Firebase/Supabase)
- Classement mondial
- Système de niveau (XP avec les parties)
- Shop pour acheter skins de cartes avec les pièces

---

## 13. Planning de développement (estimation)

### Phase 1 : Fondations (Semaine 1-2)
- Setup du projet Flutter
- Création des modèles de données
- Implémentation de la logique du jeu de base
- Tests unitaires des fonctions core

### Phase 2 : Interface de base (Semaine 3-4)
- Écrans principaux (menu, jeu, résultats)
- Widgets des cartes et du plateau
- Navigation entre écrans
- UI responsive (mobile)

### Phase 3 : Logique de jeu avancée (Semaine 5)
- Cartes spéciales (7, 10, Valet, Joker)
- Système de "Dutch"
- Mode tournoi
- Calcul des scores

### Phase 4 : IA des bots (Semaine 6)
- Implémentation des 3 personnalités
- Algorithmes de décision
- Tests et équilibrage

### Phase 5 : Sauvegarde et progression (Semaine 7)
- Système de slots (style Mario)
- Persistence des données
- Stats et accumulation de pièces

### Phase 6 : Polish (Semaine 8)
- Animations fluides
- Effets sonores
- Musique de fond
- Optimisation des performances

### Phase 7 : Tests et débogage (Semaine 9)
- Tests complets de gameplay
- Correction de bugs
- Tests utilisateurs (si possible)
- Ajustements finaux

### Phase 8 : Déploiement (Semaine 10)
- Préparation des stores (Google Play, App Store)
- Création des assets marketing (screenshots, description)
- Release beta (TestFlight, Google Play Beta)
- Release publique

**Total estimé : 10 semaines (2,5 mois)**

---

## 14. Checklist de validation avant release

### 14.1 Fonctionnel
- [ ] Toutes les règles du jeu sont correctement implémentées
- [ ] Les 3 bots ont des comportements distincts
- [ ] Mode Partie Rapide fonctionne (2-4 joueurs)
- [ ] Mode Tournoi fonctionne (4 joueurs, 3 manches)
- [ ] Système de sauvegarde (3 slots) opérationnel
- [ ] Toutes les cartes spéciales fonctionnent (7, 10, V, Joker)
- [ ] "Dutch" fonctionne correctement
- [ ] Calcul des scores exact
- [ ] Système d'XP et déblocage de bots fonctionnel
- [ ] 8 bots au total (4 tiers de difficulté)
- [ ] Statistiques de tournoi correctes (🏆 🥈 🥉)

### 14.2 UI/UX
- [ ] Interface intuitive et lisible
- [ ] Responsive sur différentes tailles d'écran
- [ ] Animations fluides (60 FPS minimum)
- [ ] Aucun bug visuel
- [ ] Feedback clair pour chaque action

### 14.3 Audio
- [ ] Tous les effets sonores présents
- [ ] Musique de fond (ou intégration streaming)
- [ ] Volume réglable
- [ ] Pas de craquements/bugs audio

### 13.4 Performance
- [ ] Temps de chargement < 3 secondes
- [ ] Aucun lag pendant le jeu
- [ ] Consommation mémoire raisonnable
- [ ] Consommation batterie optimisée

### 13.5 Tests
- [ ] Testé sur iOS (minimum iPhone 11, iOS 14+)
- [ ] Testé sur Android (minimum Android 8.0+)
- [ ] Aucun crash critique
- [ ] Toutes les fonctionnalités validées

---

## 15. Notes additionnelles

### 15.1 Accessibilité
- Taille de police ajustable
- Contraste suffisant pour les daltoniens
- Support du mode sombre (optionnel)
- Feedback haptique (vibrations) pour les actions importantes

### 15.2 Localisation (bonus)
- Français (priorité 1)
- Anglais (priorité 2)
- Autres langues (futur)

### 15.3 Conformité stores
- Respect des guidelines Apple et Google
- Politique de confidentialité (si données collectées)
- Âge minimum : 4+ (jeu de cartes simple)

---

## 16. Résumé des priorités

**Must-Have (MVP) :**
1. Jeu fonctionnel avec règles complètes
2. 8 bots avec 4 tiers de difficulté distincts
3. Système d'XP et déblocage progressif
4. Mode Partie Rapide + Mode Tournoi
5. Système de sauvegarde (3 slots) avec stats de tournoi
6. Interface style poker réaliste (inspirée des images)
7. Sons basiques

**Should-Have :**
1. Animations fluides (inspirées du poker)
2. Table de poker réaliste avec éclairage
3. Musique de fond
4. Défausse en chaîne (règle bonus)
5. Historique des actions
6. Tutoriel
7. Animation de level up et déblocage

**Could-Have :**
1. Intégration Apple Music/Spotify
2. Multijoueur local
3. Thèmes de cartes
4. Achievements
5. Stats avancées par bot

**Won't-Have (pour v1.0) :**
1. Multijoueur en ligne
2. Classement mondial
3. Shop/Microtransactions

---

**Document de spécifications - Version 2.0**
**Date : 10 Janvier 2026**
**Auteur : Claude & Utilisateur**
**Mises à jour :**
- Ajout du système de progression par XP
- 8 bots répartis sur 4 tiers de difficulté
- Mode tournoi revu (pas d'accumulation entre manches)
- Statistiques de tournoi détaillées (🏆 🥈 🥉)
- Design visuel : style poker réaliste

---

*Ce document est évolutif et sera mis à jour au fur et à mesure du développement.*
