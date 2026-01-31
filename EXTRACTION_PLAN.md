# Plan d'extraction de GameProvider (1200 lignes → ~400 lignes)

## Analyse des responsabilités

### 1. **TournamentManager** (~200 lignes)
Responsabilité : Gestion complète des tournois
- `isHumanEliminatedInTournament()`
- `finishTournamentForHuman()`
- `getTournamentRP()`
- `startNextTournamentRound()`
- `_tournamentFinalRanking`
- `_tournamentCumulativeScores`
- `_activeTournamentId`

### 2. **ReactionTimerManager** (~150 lignes)
Responsabilité : Gestion des timers de réaction
- `startReactionPhase()`
- `_pauseReactionTimer()`
- `_resumeReactionTimer()`
- `_endReactionPhase()`
- `pauseReactionTimerForNotification()`
- `resumeReactionTimerAfterNotification()`
- `_reactionTimer`
- `_remainingReactionTimeMs`
- `reactionTimeRemaining`

### 3. **SpecialPowerHandler** (~250 lignes)
Responsabilité : Gestion des pouvoirs spéciaux
- `skipSpecialPower()`
- `useSpecialPower()`
- `completeSwap()`
- `executeLookAtCard()`
- `executeJokerEffect()`
- `_getPowerType()`
- `_getTargetStrategy()`

### 4. **BotOrchestrator** (~150 lignes)
Responsabilité : Orchestration des actions des bots
- `checkIfBotShouldPlay()`
- `_checkAndPlayBotTurn()`
- `_simulateBotReaction()`

### 5. **GameProvider** (reste ~400 lignes)
Responsabilité : Coordination générale et actions de base
- État du jeu
- Actions de base (drawCard, replaceCard, discardDrawnCard, etc.)
- Coordination entre les managers
- Lifecycle (createNewGame, endGame, quitGame, etc.)

## Avantages

1. **Lisibilité** : Chaque classe a une responsabilité claire
2. **Testabilité** : Chaque manager peut être testé indépendamment
3. **Maintenabilité** : Plus facile de trouver et modifier du code
4. **Réutilisabilité** : Les managers peuvent être réutilisés ailleurs
5. **Respect de SRP** : Une classe = une responsabilité

## Structure finale

```
lib/providers/
  ├── game_provider.dart (~400 lignes)
  ├── game_tracking_provider.dart (existant)
  ├── managers/
  │   ├── tournament_manager.dart
  │   ├── reaction_timer_manager.dart
  │   ├── special_power_handler.dart
  │   └── bot_orchestrator.dart
```
