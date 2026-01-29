# Nouvelles Fonctionnalités Multijoueur

Ce document décrit les nouvelles fonctionnalités ajoutées au mode multijoueur du jeu Dutch.

## 🎨 Animations de Cartes

### Description
Les cartes ne "téléportent" plus instantanément. Elles glissent maintenant avec des animations fluides lors des transitions.

### Implémentation
- **Widget**: `AnimatedCardTransition` (`lib/widgets/animated_card_transition.dart`)
- **Animations**:
  - Transition de position avec courbe `easeInOutCubic`
  - Effet de scale (agrandissement/rétrécissement)
  - Légère rotation pour un effet naturel
  - Durée: 600ms par défaut

### Utilisation
```dart
AnimatedCardTransition(
  card: playingCard,
  startPosition: Offset(100, 100),
  endPosition: Offset(300, 200),
  size: CardSize.medium,
  isRevealed: true,
  onComplete: () {
    // Action après l'animation
  },
)
```

## 😊 Système d'Émotes

### Description
Les joueurs peuvent envoyer des émotes rapides pour communiquer pendant la partie, ajoutant une dimension sociale au jeu.

### Fonctionnalités
- **12 émotes disponibles**:
  - 😂 Rire
  - 😎 Cool
  - 🤔 Réfléchir
  - 😱 Choqué
  - 🎉 Bravo
  - 😤 Énervé
  - 👍 OK
  - 👎 Pas OK
  - 🔥 Feu
  - 💪 Force
  - 🤷 Bof
  - 😴 Ennui

### Interface
- **Bouton d'émotes**: Icône 😊 en haut à droite de l'écran de jeu
- **Overlay**: Grille 4x3 avec animations d'ouverture/fermeture
- **Affichage**: Les émotes flottent à l'écran avec le nom du joueur pendant 2 secondes

### Implémentation
- **Service**: `EmoteService` (`lib/services/emote_service.dart`)
- **Widget Overlay**: `EmoteOverlay` (`lib/widgets/emote_overlay.dart`)
- **Widget Flottant**: `FloatingEmote` (`lib/widgets/emote_overlay.dart`)

### Utilisation
```dart
// Dans le provider
gameProvider.sendEmote('😂');

// Écouter les émotes
StreamSubscription subscription = gameProvider.emoteStream.listen((emote) {
  print('${emote.playerName} a envoyé ${emote.emoji}');
});
```

## 🔄 Reconnexion Silencieuse

### Description
En cas de coupure réseau brève (<3 secondes), le jeu tente automatiquement de se reconnecter sans interrompre l'expérience du joueur.

### Fonctionnement
1. **Détection**: Perte de connexion détectée
2. **Timer**: Démarrage d'un timer de 3 secondes
3. **Tentative**: Reconnexion automatique en arrière-plan
4. **Succès**: 
   - Si reconnexion < 3s → Reprise transparente
   - Message "✅ Reconnexion silencieuse réussie" dans les logs
5. **Échec**: 
   - Si > 3s → Affichage du dialogue d'erreur classique

### Indicateur Visuel
Pendant la reconnexion, un bandeau bleu s'affiche en haut de l'écran:
```
🔄 Reconnexion en cours...
```

### Implémentation
- **Provider**: `MultiplayerGameProvider._startSilentReconnection()`
- **Timer**: 3 secondes maximum
- **État**: `isSilentReconnecting` (boolean)

### Code
```dart
// Vérifier l'état de reconnexion
if (gameProvider.isSilentReconnecting) {
  // Afficher l'indicateur
}

// Le système gère automatiquement:
// - La détection de déconnexion
// - La tentative de reconnexion
// - Le timeout après 3s
// - La reprise de la partie
```

## 🏆 Mode Compétitif avec MMR/Elo

### Description
Système de classement compétitif basé sur le système Elo, permettant aux joueurs de suivre leur progression et de se mesurer aux autres.

### Caractéristiques

#### Tiers (Rangs)
- **Bronze**: 0-1299 MMR 🥉
- **Argent**: 1300-1599 MMR 🥈
- **Or**: 1600-1899 MMR 🥇
- **Platine**: 1900-2199 MMR 🏆
- **Diamant**: 2200+ MMR 💎

#### Statistiques Suivies
- **MMR** (Match Making Rating): Score Elo
- **Victoires/Défaites**
- **Win Rate** (%)
- **Parties jouées**
- **Série de victoires actuelle**
- **Meilleure série de victoires**
- **Rang global** (position estimée)

### Calcul du MMR

#### Formule de Base (Elo)
```
Nouveau MMR = Ancien MMR + K × (Score Réel - Score Attendu)
```

Où:
- **K = 32** (facteur de volatilité)
- **Score Attendu** = Basé sur la différence de MMR avec les adversaires
- **Score Réel** = Basé sur le classement final:
  - 1er place = 1.0
  - 2e place = 0.66
  - 3e place = 0.33
  - 4e place = 0.0

#### Bonus/Malus
- **+10 MMR** pour une victoire (1ère place)
- **-5 MMR** pour une dernière place
- **MMR plafonné** entre 0 et 3000

### Implémentation

#### Service
```dart
// Récupérer les stats
CompetitiveStats stats = await CompetitiveService.getStats(playerId);

// Mettre à jour après une partie
CompetitiveStats newStats = await CompetitiveService.updateAfterGame(
  playerId: playerId,
  playerRank: 1, // Classement final
  totalPlayers: 4,
  opponentMMRs: [1200, 1150, 1100], // MMR des adversaires
);

// Réinitialiser
await CompetitiveService.resetStats(playerId);
```

#### Widgets
```dart
// Affichage compact
CompetitiveStatsWidget(
  stats: stats,
  compact: true,
)

// Affichage complet
CompetitiveStatsWidget(
  stats: stats,
  compact: false,
)

// Résultat de match
CompetitiveMatchResult(
  mmrChange: 25,
  newStats: newStats,
  playerRank: 1,
  totalPlayers: 4,
)
```

### Intégration avec le Multijoueur

Pour activer le mode compétitif dans une partie multijoueur:

1. **Créer une room compétitive**:
```dart
await gameProvider.createRoom(
  settings: GameSettings(
    gameMode: GameMode.competitive, // Mode compétitif
    // ... autres paramètres
  ),
  playerName: playerName,
);
```

2. **Après la partie**:
```dart
// Le système calcule automatiquement les changements de MMR
// basés sur les MMR de tous les joueurs et le classement final
```

## 📝 Résumé des Améliorations

### Animations
✅ Transitions fluides des cartes (600ms)
✅ Effets de scale et rotation
✅ Animations similaires au mode solo

### Social
✅ 12 émotes expressives
✅ Affichage flottant avec nom du joueur
✅ Interface intuitive (grille 4x3)

### Connexion
✅ Reconnexion automatique < 3s
✅ Indicateur visuel pendant la reconnexion
✅ Pas d'interruption de jeu si succès rapide

### Compétitif
✅ Système Elo complet
✅ 5 tiers de classement
✅ Statistiques détaillées
✅ Calcul intelligent du MMR
✅ Widgets d'affichage prêts à l'emploi

## 🚀 Prochaines Étapes Possibles

### Animations Avancées
- [ ] Particules lors de la défausse
- [ ] Trail de la carte en mouvement
- [ ] Animations spécifiques par pouvoir spécial

### Émotes
- [ ] Émotes personnalisées par joueur
- [ ] Historique des émotes dans le chat
- [ ] Cooldown pour éviter le spam

### Compétitif
- [ ] Saisons compétitives
- [ ] Leaderboard global
- [ ] Récompenses par tier
- [ ] Matchmaking basé sur le MMR

### Reconnexion
- [ ] Sauvegarde d'état pour reconnexion après crash
- [ ] Reconnexion après fermeture de l'app
- [ ] Synchronisation automatique de l'état de jeu
