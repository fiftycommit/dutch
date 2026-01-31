# Découpage de GameProvider

## 📊 État actuel
- **1295 lignes** - Trop de responsabilités
- Gère l'état, les timers, le tracking, les bots, les tournois...

## 🎯 Nouveau découpage (3 providers)

### **1. GameStateProvider** (État du jeu)
**Responsabilité** : Gérer l'état du jeu et les actions de jeu

**Variables** :
- `_gameState`
- `_currentContext`
- `isProcessing`
- `statusMessage`
- `shakingCardIndices`
- `_isPaused`
- `_currentSlotId`
- `_playerMMR`
- `_playerWinStreak`
- `_tournamentFinalRanking`

**Méthodes** :
- `startGame()`
- `drawCard()`
- `replaceCard()`
- `discardDrawnCard()`
- `callDutch()`
- `useSpecialPower()`
- `endGame()`
- Gestion des tournois

### **2. GameTimerProvider** (Timers et réactions)
**Responsabilité** : Gérer les timers de réaction et les phases de jeu

**Variables** :
- `_reactionTimer`
- `_currentReactionTimeMs`
- `_remainingReactionTimeMs`
- `reactionTimeRemaining`

**Méthodes** :
- `_startReactionTimer()`
- `_cancelReactionTimer()`
- `_endReactionPhase()`
- Gestion des phases de réaction

### **3. GameTrackingProvider** (Tracking ML)
**Responsabilité** : Gérer le tracking des données pour le ML

**Variables** :
- `_botLearningService`
- `_playerLearningService`
- `_currentGameId`
- `_humanActionCounter`

**Méthodes** :
- `startGameRecording()`
- `recordAction()`
- `endGameRecording()`
- Tracking des actions joueur/bot

## 🔄 Communication entre providers

```dart
// GameStateProvider utilise GameTimerProvider
class GameStateProvider {
  final GameTimerProvider timerProvider;
  final GameTrackingProvider trackingProvider;
  
  GameStateProvider(this.timerProvider, this.trackingProvider);
}
```

## ⚠️ Note importante

**Découpage complexe** : GameProvider est très couplé, le découpage complet nécessiterait de refactoriser beaucoup de code.

**Alternative recommandée** : Garder GameProvider mais extraire seulement GameTrackingProvider pour commencer.

## 💡 Approche progressive

### Phase 1 (Maintenant)
1. Créer les barrel files ✅
2. Extraire **GameTrackingProvider** uniquement
   - Plus simple
   - Moins de risques
   - Déjà préparé avec les services

### Phase 2 (Plus tard)
1. Extraire GameTimerProvider
2. Extraire GameStateProvider
3. Refactoriser les dépendances

---

**Décision** : Je vais créer **GameTrackingProvider** uniquement pour l'instant, c'est le plus découplé et le plus facile à extraire.
