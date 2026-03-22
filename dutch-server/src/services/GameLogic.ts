import { PlayingCard, createFullDeck, cardMatches } from '../models/Card';
import { Player } from '../models/Player';
import { GameState, GamePhase, PendingMatchPower, addToHistory, getCurrentPlayer, nextPlayer as nextPlayerUtil } from '../models/GameState';
import { HistoryFormatter } from '../utils/HistoryFormatter';

export class GameLogic {
  private static random(): number {
    return Math.random();
  }

  static initializeGame(gameState: GameState): void {
    const deck = createFullDeck();
    gameState.deck = deck;

    // Réinitialiser les mains et mémoires des joueurs
    for (const player of gameState.players) {
      player.hand = [];
      player.knownCards = [];
    }

    gameState.discardPile = [];
    gameState.phase = GamePhase.setup;

    // Mélanger et distribuer
    this.smartShuffle(gameState);
    this.dealCards(gameState);

    // Initialiser la mémoire des bots
    for (const player of gameState.players) {
      if (!player.isHuman) {
        this.initializeBotMemory(player);
      }
    }

    // Retourner la première carte de la défausse
    if (gameState.deck.length > 0) {
      const firstCard = gameState.deck.pop()!;
      gameState.discardPile.push(firstCard);
    }

    // Choisir un joueur aléatoire pour commencer
    if (gameState.players.length > 0) {
      const randomIndex = Math.floor(this.random() * gameState.players.length);
      gameState.currentPlayerIndex = randomIndex;
      const starter = gameState.players[randomIndex];
      console.log(`🎲 Premier joueur : ${starter.name} (index ${randomIndex}/${gameState.players.length})`);
      addToHistory(gameState, HistoryFormatter.formatStartingPlayer(starter.name));
    }
  }

  private static initializeBotMemory(player: Player): void {
    if (player.isHuman || player.hand.length < 2) return;

    // Les bots connaissent leurs 2 premières cartes
    player.knownCards = new Array(player.hand.length).fill(false);
    player.knownCards[0] = true;
    player.knownCards[1] = true;
  }

  static initialReveal(gameState: GameState, selectedIndices: number[]): void {
    const human = gameState.players.find((p) => p.isHuman);
    if (!human) return;

    for (const index of selectedIndices) {
      if (index >= 0 && index < human.knownCards.length) {
        human.knownCards[index] = true;
      }
    }
    addToHistory(gameState, HistoryFormatter.formatInitialMemorization());
  }

  static drawCard(gameState: GameState): void {
    if (gameState.deck.length === 0) {
      this.refillDeck(gameState);
    }

    if (gameState.deck.length > 0) {
      gameState.drawnCard = gameState.deck.pop()!;
      addToHistory(gameState, HistoryFormatter.formatDrawCard(getCurrentPlayer(gameState).name));
    } else {
      this.endGame(gameState);
    }
  }

  static discardDrawnCard(gameState: GameState): void {
    if (!gameState.drawnCard) return;

    const card = gameState.drawnCard;
    gameState.drawnCard = null;
    gameState.discardPile.push(card);

    // Check if card has a special power BEFORE generating the message
    const powerCards = ['7', '10', 'V', 'JOKER'];
    const hasPower = powerCards.includes(card.value);
    addToHistory(gameState, HistoryFormatter.formatDiscardDrawn(getCurrentPlayer(gameState).name, card, hasPower));

    this.checkSpecialPower(gameState, card);

    if (gameState.phase !== GamePhase.specialPower) {
      this.startReactionPhase(gameState);
    }
  }

  static startReactionPhase(gameState: GameState, delayMs: number = 0): void {
    gameState.phase = GamePhase.reaction;
    // Si on a un délai (ex: suite à un pouvoir spécial), on démarre le timestamp de réaction dans le futur
    gameState.reactionStartTime = new Date(Date.now() + delayMs);
  }

  static replaceCard(gameState: GameState, cardIndex: number): void {
    if (!gameState.drawnCard) return;

    const player = getCurrentPlayer(gameState);

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      return;
    }

    const newCard = gameState.drawnCard;
    const oldCard = player.hand[cardIndex];

    player.hand[cardIndex] = newCard;
    player.knownCards[cardIndex] = true;
    gameState.drawnCard = null;

    gameState.discardPile.push(oldCard);
    addToHistory(gameState, HistoryFormatter.formatReplaceDrawn(player.name, oldCard));

    this.checkSpecialPower(gameState, oldCard);

    if (gameState.phase !== GamePhase.specialPower) {
      this.startReactionPhase(gameState);
    }
  }

  static matchCard(gameState: GameState, player: Player, cardIndex: number): boolean {
    if (gameState.discardPile.length === 0) return false;

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      return false;
    }

    const playerCard = player.hand[cardIndex];
    const topDiscard = gameState.discardPile[gameState.discardPile.length - 1];

    if (cardMatches(playerCard, topDiscard)) {
      gameState.discardPile.push(playerCard);

      // Retirer la carte de la main
      player.hand.splice(cardIndex, 1);
      player.knownCards.splice(cardIndex, 1);

      addToHistory(
        gameState,
        HistoryFormatter.formatMatchSuccess(player.name, playerCard)
      );

      if (gameState.phase === GamePhase.reaction) {
        // Pendant la réaction, stocker le pouvoir pour résolution après
        this.addPendingMatchPower(gameState, player, playerCard);
      } else {
        this.checkSpecialPower(gameState, playerCard);
      }

      return true;
    } else {
      addToHistory(
        gameState,
        HistoryFormatter.formatMatchFail(player.name, playerCard, topDiscard)
      );
      this.applyPenalty(gameState, player);
      return false;
    }
  }

  static applyPenalty(gameState: GameState, player: Player): void {
    if (gameState.deck.length === 0) {
      this.refillDeck(gameState);
    }
    if (gameState.deck.length === 0) return;

    const penaltyCard = gameState.deck.pop()!;
    player.hand.push(penaltyCard);
    player.knownCards.push(false);

    addToHistory(gameState, HistoryFormatter.formatPenalty(player.name));
  }

  static lookAtCard(gameState: GameState, target: Player, cardIndex: number): void {
    if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
      // Note: Logic to show card to requester is handled by client/provider
      addToHistory(
        gameState,
        HistoryFormatter.formatPowerSpy(getCurrentPlayer(gameState).name, target.name)
      );
    }
  }

  static swapCards(
    gameState: GameState,
    p1: Player,
    idx1: number,
    p2: Player,
    idx2: number
  ): void {
    if (
      idx1 < 0 ||
      idx1 >= p1.hand.length ||
      idx2 < 0 ||
      idx2 >= p2.hand.length
    ) {
      return;
    }

    const c1 = p1.hand[idx1];
    const c2 = p2.hand[idx2];

    p1.hand[idx1] = c2;
    p2.hand[idx2] = c1;

    if (idx1 < p1.knownCards.length) p1.knownCards[idx1] = false;
    if (idx2 < p2.knownCards.length) p2.knownCards[idx2] = false;

    addToHistory(
      gameState,
      HistoryFormatter.formatPowerSwap(p1.name, idx1, p2.name, idx2)
    );
  }

  static jokerEffect(gameState: GameState, targetPlayer: Player): void {
    // Mélanger la main du joueur cible
    const shuffledHand = [...targetPlayer.hand];
    for (let i = shuffledHand.length - 1; i > 0; i--) {
      const j = Math.floor(this.random() * (i + 1));
      [shuffledHand[i], shuffledHand[j]] = [shuffledHand[j], shuffledHand[i]];
    }
    targetPlayer.hand = shuffledHand;

    // Réinitialiser les connaissances
    targetPlayer.knownCards = new Array(targetPlayer.hand.length).fill(false);

    addToHistory(
      gameState,
      HistoryFormatter.formatPowerJoker(getCurrentPlayer(gameState).name, targetPlayer.name)
    );
  }

  private static checkSpecialPower(gameState: GameState, card: PlayingCard): void {
    // Only cards with actual implemented powers: 7 (spy), 10 (swap), V (exchange), JOKER (shuffle)
    const powerCards = ['7', '10', 'V', 'JOKER'];
    if (powerCards.includes(card.value)) {
      const now = Date.now();
      gameState.phase = GamePhase.specialPower;
      gameState.isWaitingForSpecialPower = true;
      gameState.specialCardToActivate = card;
      gameState.specialPowerPlayerId = null; // currentPlayer par défaut
      gameState.specialPowerStartTime = now;
      // Synchroniser turnStartTime et turnTimeoutMs immédiatement pour que
      // le premier broadcast (ACTION_RESULT) inclue les bonnes valeurs du timer.
      // Sans ça, les joueurs en attente reçoivent l'ancien turnTimeoutMs (90s de la phase playing)
      // au lieu du timeout du pouvoir spécial (60s), ce qui désynchronise leur barre de progression.
      gameState.turnStartTime = now;
      gameState.turnTimeoutMs = 60000; // 60s pour utiliser le pouvoir (synchronisé avec RoomManager.specialPowerTimeoutMs)
    }
  }

  /** Ajoute un pouvoir en attente suite à un match pendant la phase de réaction */
  private static addPendingMatchPower(gameState: GameState, player: Player, card: PlayingCard): void {
    const powerCards = ['7', '10', 'V', 'JOKER'];
    if (powerCards.includes(card.value)) {
      gameState.pendingMatchPowers.push({
        playerId: player.id,
        playerName: player.name,
        card: { ...card },
      });
    }
  }

  static callDutch(gameState: GameState, playerId?: string): void {
    if (gameState.dutchCallerId) return;
    gameState.dutchCallerId = playerId || getCurrentPlayer(gameState).id;
    gameState.phase = GamePhase.dutchCalled;
    const player = gameState.players.find(p => p.id === gameState.dutchCallerId);
    addToHistory(gameState, HistoryFormatter.formatDutchCall(player?.name || 'Joueur'));

    // Stop game immediately (as per user request to match Solo mode)
    this.endGame(gameState);
  }

  // Méthodes supplémentaires pour le serveur multijoueur

  static takeFromDiscard(gameState: GameState): void {
    if (gameState.discardPile.length === 0) return;

    const card = gameState.discardPile.pop()!;
    gameState.drawnCard = card;
    addToHistory(gameState, HistoryFormatter.formatTakeFromDiscard(getCurrentPlayer(gameState).name));
  }

  static attemptMatch(gameState: GameState, playerId: string, cardIndex: number): boolean {
    const player = gameState.players.find(p => p.id === playerId);
    if (!player) return false;

    return this.matchCard(gameState, player, cardIndex);
  }

  /**
   * Utilise un pouvoir spécial - Aligné sur le mode solo
   *
   * @param data Les paramètres dépendent de la carte:
   *   - Carte 7: { cardIndex } - Regarder sa propre carte
   *   - Carte 10: { targetPlayerIndex, targetCardIndex } - Espionner un adversaire
   *   - Carte V: { player1Index, card1Index, player2Index, card2Index } - Échange universel
   *   - JOKER: { targetPlayerIndex } - Mélanger n'importe qui (y compris soi)
   *
   * @returns Informations sur les joueurs affectés pour les notifications
   */
  static useSpecialPower(
    gameState: GameState,
    data: {
      // Pour carte 7 : regarder sa propre carte
      cardIndex?: number;
      // Pour carte 10 : espionner un adversaire
      targetPlayerIndex?: number;
      targetCardIndex?: number;
      // Pour carte V : échange universel
      player1Index?: number;
      card1Index?: number;
      player2Index?: number;
      card2Index?: number;
    }
  ): {
    spiedCard?: PlayingCard;
    affectedPlayers?: Array<{ playerId: string; playerName: string; cardIndex: number; swapPartnerName: string; receivedCardPosition: number }>;
    shuffledPlayer?: { playerId: string; playerName: string };
  } {
    if (gameState.phase !== GamePhase.specialPower || !gameState.specialCardToActivate) {
      return {};
    }

    // Utiliser le joueur pouvoiré (match power) ou le joueur actif (normal)
    const currentPlayer = gameState.specialPowerPlayerId
      ? gameState.players.find(p => p.id === gameState.specialPowerPlayerId) ?? getCurrentPlayer(gameState)
      : getCurrentPlayer(gameState);
    const card = gameState.specialCardToActivate;
    let result: ReturnType<typeof GameLogic.useSpecialPower> = {};

    if (card.value === '7') {
      // Carte 7 : Regarder SA PROPRE carte (comme en solo)
      const cardIndex = data.cardIndex ?? 0;
      if (cardIndex >= 0 && cardIndex < currentPlayer.hand.length) {
        gameState.lastSpiedCard = currentPlayer.hand[cardIndex];
        currentPlayer.knownCards[cardIndex] = true;
        addToHistory(gameState, `${currentPlayer.name} a regardé une de ses cartes.`);
        result.spiedCard = currentPlayer.hand[cardIndex];
      }
    } else if (card.value === '10') {
      // Carte 10 : Espionner une carte adversaire (pas d'échange)
      const targetPlayerIndex = data.targetPlayerIndex ?? 0;
      const targetCardIndex = data.targetCardIndex ?? 0;

      if (targetPlayerIndex >= 0 && targetPlayerIndex < gameState.players.length) {
        const targetPlayer = gameState.players[targetPlayerIndex];
        if (targetCardIndex >= 0 && targetCardIndex < targetPlayer.hand.length) {
          gameState.lastSpiedCard = targetPlayer.hand[targetCardIndex];
          addToHistory(
            gameState,
            `${currentPlayer.name} a espionné une carte de ${targetPlayer.name}.`
          );
          result.spiedCard = targetPlayer.hand[targetCardIndex];
        }
      }
    } else if (card.value === 'V') {
      // Carte V (Valet) : Échange universel entre 2 joueurs quelconques
      const { player1Index, card1Index, player2Index, card2Index } = data;

      if (
        player1Index !== undefined && card1Index !== undefined &&
        player2Index !== undefined && card2Index !== undefined &&
        player1Index >= 0 && player1Index < gameState.players.length &&
        player2Index >= 0 && player2Index < gameState.players.length
      ) {
        const p1 = gameState.players[player1Index];
        const p2 = gameState.players[player2Index];

        if (
          card1Index >= 0 && card1Index < p1.hand.length &&
          card2Index >= 0 && card2Index < p2.hand.length
        ) {
          this.swapCards(gameState, p1, card1Index, p2, card2Index);

          // Retourner les joueurs affectés (sauf celui qui utilise le pouvoir)
          result.affectedPlayers = [];
          if (p1.id !== currentPlayer.id) {
            result.affectedPlayers.push({
              playerId: p1.id,
              playerName: p1.name,
              cardIndex: card1Index,
              swapPartnerName: p2.name,
              receivedCardPosition: card2Index + 1, // position (1-based) chez p2
            });
          }
          if (p2.id !== currentPlayer.id) {
            result.affectedPlayers.push({
              playerId: p2.id,
              playerName: p2.name,
              cardIndex: card2Index,
              swapPartnerName: p1.name,
              receivedCardPosition: card1Index + 1, // position (1-based) chez p1
            });
          }
        }
      }
    } else if (card.value === 'JOKER') {
      // JOKER : Mélanger n'importe qui (y compris soi-même)
      const targetPlayerIndex = data.targetPlayerIndex ?? 0;

      if (targetPlayerIndex >= 0 && targetPlayerIndex < gameState.players.length) {
        const targetPlayer = gameState.players[targetPlayerIndex];
        this.jokerEffect(gameState, targetPlayer);

        // Retourner le joueur affecté (sauf si c'est soi-même)
        if (targetPlayer.id !== currentPlayer.id) {
          result.shuffledPlayer = {
            playerId: targetPlayer.id,
            playerName: targetPlayer.name
          };
        }
      }
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    this.startReactionPhase(gameState);

    return result;
  }

  static skipSpecialPower(gameState: GameState): void {
    // Déterminer le joueur qui avait le pouvoir
    const powerPlayer = gameState.specialPowerPlayerId
      ? gameState.players.find(p => p.id === gameState.specialPowerPlayerId)
      : getCurrentPlayer(gameState);
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.specialPowerPlayerId = null;
    addToHistory(gameState, HistoryFormatter.formatPowerSkip(powerPlayer?.name ?? 'Joueur'));
    this.startReactionPhase(gameState);
  }

  static endGame(gameState: GameState): void {
    gameState.phase = GamePhase.ended;
    for (const player of gameState.players) {
      for (let i = 0; i < player.knownCards.length; i++) {
        player.knownCards[i] = true;
      }
    }
  }

  static nextPlayer(gameState: GameState): void {
    nextPlayerUtil(gameState);
  }

  private static refillDeck(gameState: GameState): void {
    if (gameState.discardPile.length > 1) {
      const top = gameState.discardPile.pop()!;
      gameState.deck.push(...gameState.discardPile);
      gameState.discardPile = [top];

      // Mélanger le nouveau deck
      this.shuffleDeck(gameState.deck);

      addToHistory(
        gameState,
        HistoryFormatter.formatDeckRefill(gameState.deck.length)
      );
    } else {
      if (gameState.dutchCallerId) {
        gameState.phase = GamePhase.dutchCalled;
        addToHistory(gameState, HistoryFormatter.formatEmptyDeckEnd());
      } else {
        this.endGame(gameState);
      }
    }
  }

  private static smartShuffle(gameState: GameState): void {
    // Pour l'instant, on fait un shuffle simple
    // La logique complète de smartShuffle avec les difficultés sera implémentée plus tard
    this.shuffleDeck(gameState.deck);
  }

  private static dealCards(gameState: GameState): void {
    // Distribution simple : 4 cartes par joueur
    for (const player of gameState.players) {
      player.hand = [];
      player.knownCards = [];
      for (let i = 0; i < 4; i++) {
        if (gameState.deck.length > 0) {
          player.hand.push(gameState.deck.pop()!);
          player.knownCards.push(false);
        }
      }
    }
  }

  private static shuffleDeck(deck: PlayingCard[]): void {
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(this.random() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
  }

  private static getCardDisplayName(card: PlayingCard): string {
    if (card.value === 'R') {
      return card.suit === 'hearts' || card.suit === 'diamonds'
        ? 'Roi Rouge'
        : 'Roi Noir';
    }
    if (card.value === 'JOKER') return 'Joker';
    if (card.value === 'A') return 'A';
    if (card.value === 'V') return 'Valet';
    if (card.value === 'D') return 'Dame';
    return card.value;
  }
}
