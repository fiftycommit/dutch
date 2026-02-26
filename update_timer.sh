#!/bin/bash
# Updating GameLogic.ts to add a delay parameter to startReactionPhase
sed -i '' 's/private static startReactionPhase(gameState: GameState): void {/private static startReactionPhase(gameState: GameState, delayMs: number = 0): void {\
    gameState.phase = GamePhase.reaction;\
    \/\/ Si on a un d\xc3\xa9lai (ex: suite \xc3\xa0 un pouvoir sp\xc3\xa9cial), on d\xc3\xa9marre le timestamp de r\xc3\xa9action dans le futur\
    gameState.reactionStartTime = new Date(Date.now() + delayMs);/g' /Users/maxmbey/projets/dutch/dutch-server/src/services/GameLogic.ts

# Updating startReactionPhase calls inside GameLogic.ts to pass a delay if it's from a special power
sed -i '' "s/this.startReactionPhase(gameState);/const isFromPower = gameState.isWaitingForSpecialPower === false \&\& gameState.specialCardToActivate === null;\
    this.startReactionPhase(gameState, isFromPower ? 3500 : 0);/g" /Users/maxmbey/projets/dutch/dutch-server/src/services/GameLogic.ts

