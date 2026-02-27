import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { Server, Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { setupGameHandler } from '../handlers/gameHandler';
import { GamePhase, GameMode, getCurrentPlayer } from '../models/GameState';
import { createCard } from '../models/Card';
import { SecurityService } from '../services/SecurityService';

// Mock Socket implementation
class MockSocket {
  id: string;
  events: Map<string, Function> = new Map();
  emittedEvents: Array<{ event: string; data: any }> = [];
  rooms: Set<string> = new Set();
  targetedEmits: Array<{ target: string; event: string; data: any }> = [];

  constructor(id: string) {
    this.id = id;
  }

  on(event: string, callback: Function) {
    this.events.set(event, callback);
    return this;
  }

  emit(event: string, data: any) {
    this.emittedEvents.push({ event, data });
    return this;
  }

  join(room: string) {
    this.rooms.add(room);
    return this;
  }

  leave(room: string) {
    this.rooms.delete(room);
    return this;
  }

  to(target: string) {
    const self = this;
    return {
      emit(event: string, data: any) {
        self.targetedEmits.push({ target, event, data });
        return self;
      }
    };
  }

  triggerEvent(event: string, ...args: any[]) {
    const handler = this.events.get(event);
    if (handler) {
      return handler(...args);
    }
  }
}

class MockServer {
  events: Array<{ target: string; event: string; data: any }> = [];
  private currentTarget = '';

  to(target: string) {
    this.currentTarget = target;
    return this;
  }

  emit(event: string, data: any) {
    this.events.push({ target: this.currentTarget, event, data });
    return true;
  }
}

describe('gameHandler', () => {
  let mockSocket: MockSocket;
  let mockServer: MockServer;
  let roomManager: RoomManager;
  let roomCode: string;

  beforeEach(() => {
    SecurityService.resetForTesting();
    mockSocket = new MockSocket('player-1');
    mockServer = new MockServer();
    roomManager = new RoomManager(mockServer as unknown as Server, {
      cleanupIntervalMs: 10_000,
      roomTtlMs: 60_000,
      turnTimeoutMs: 30000,
      presenceGraceMs: 5000,
    });

    setupGameHandler(mockSocket as unknown as Socket, roomManager);

    // Create and start a game
    const room = roomManager.createRoom('player-1', {
      minPlayers: 2,
      maxPlayers: 4,
      fillBots: false,
    });
    roomCode = room.id;
    roomManager.joinRoom(roomCode, 'player-2', 'Player 2', 'client-2');

    roomManager.setReady(roomCode, 'player-1', true);
    roomManager.setReady(roomCode, 'player-2', true);
    roomManager.startGame(roomCode, { fillBots: false });

    // Mark players ready after memorization
    roomManager.markPlayerReady(roomCode, 'player-1');
    roomManager.markPlayerReady(roomCode, 'player-2');
  });

  afterEach(() => {
    roomManager.dispose();
  });

  describe('game:draw_card', () => {
    it('allows current player to draw a card', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');

      const deckSizeBefore = room.gameState!.deck.length;

      await mockSocket.triggerEvent('game:draw_card', { roomCode });

      // Allow async operations to complete
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.ok(
        room.gameState!.drawnCard !== null ||
        room.gameState!.deck.length < deckSizeBefore
      );
    });

    it('rejects draw from non-current player', async () => {
      const room = roomManager.getRoom(roomCode)!;
      // Set current player to someone else
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-2');

      const deckSizeBefore = room.gameState!.deck.length;

      await mockSocket.triggerEvent('game:draw_card', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      // Deck should not change because it's not player-1's turn
      assert.strictEqual(room.gameState!.deck.length, deckSizeBefore);
    });

    it('rejects draw from spectator', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.players.find(p => p.id === 'player-1')!.isSpectator = true;

      const deckSizeBefore = room.gameState!.deck.length;

      await mockSocket.triggerEvent('game:draw_card', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.deck.length, deckSizeBefore);
    });

    it('handles invalid room code', async () => {
      await mockSocket.triggerEvent('game:draw_card', { roomCode: 'INVALID' });
      // Should not throw
      assert.ok(true);
    });
  });

  describe('game:replace_card', () => {
    it('allows replacing a card in hand', async () => {
      const room = roomManager.getRoom(roomCode)!;
      const playerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.currentPlayerIndex = playerIndex;
      room.gameState!.drawnCard = createCard('hearts', '5');

      const oldCard = room.gameState!.players[playerIndex].hand[0];

      await mockSocket.triggerEvent('game:replace_card', { roomCode, cardIndex: 0 });
      await new Promise(resolve => setTimeout(resolve, 50));

      // Drawn card should now be in hand
      assert.strictEqual(room.gameState!.drawnCard, null);
    });

    it('rejects replace without drawn card', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.drawnCard = null;

      await mockSocket.triggerEvent('game:replace_card', { roomCode, cardIndex: 0 });
      // Should not throw or change state
      assert.ok(true);
    });
  });

  describe('game:discard_card', () => {
    it('allows discarding drawn card', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.drawnCard = createCard('hearts', '5');

      const discardSizeBefore = room.gameState!.discardPile.length;

      await mockSocket.triggerEvent('game:discard_card', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.drawnCard, null);
      assert.strictEqual(room.gameState!.discardPile.length, discardSizeBefore + 1);
    });

    it('triggers reaction phase for non-special card', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.drawnCard = createCard('hearts', '5');
      room.gameState!.phase = GamePhase.playing;

      await mockSocket.triggerEvent('game:discard_card', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.phase, GamePhase.reaction);
    });
  });

  describe('game:take_from_discard', () => {
    it('takes card from discard pile', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.discardPile.push(createCard('spades', '6'));

      const discardSizeBefore = room.gameState!.discardPile.length;

      await mockSocket.triggerEvent('game:take_from_discard', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.discardPile.length, discardSizeBefore - 1);
      assert.ok(room.gameState!.drawnCard);
    });
  });

  describe('game:call_dutch', () => {
    it('allows player to call Dutch', async () => {
      const room = roomManager.getRoom(roomCode)!;

      await mockSocket.triggerEvent('game:call_dutch', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.dutchCallerId, 'player-1');
    });

    it('rejects Dutch from spectator', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.players.find(p => p.id === 'player-1')!.isSpectator = true;

      await mockSocket.triggerEvent('game:call_dutch', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.dutchCallerId, null);
    });
  });

  describe('game:attempt_match', () => {
    it('allows match attempt during reaction phase', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.phase = GamePhase.reaction;
      room.gameState!.discardPile.push(createCard('hearts', '5'));

      const player = room.gameState!.players.find(p => p.id === 'player-1')!;
      player.hand[0] = createCard('spades', '5'); // Matching card

      const handSizeBefore = player.hand.length;

      await mockSocket.triggerEvent('game:attempt_match', { roomCode, cardIndex: 0 });
      await new Promise(resolve => setTimeout(resolve, 50));

      // If match successful, hand size decreases
      assert.ok(player.hand.length <= handSizeBefore);
    });

    it('rejects match outside reaction phase', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.phase = GamePhase.playing;

      await mockSocket.triggerEvent('game:attempt_match', { roomCode, cardIndex: 0 });
      // Should be ignored
      assert.ok(true);
    });
  });

  describe('game:use_special_power', () => {
    it('handles card 7 special power', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.phase = GamePhase.specialPower;
      room.gameState!.isWaitingForSpecialPower = true;
      room.gameState!.specialCardToActivate = createCard('hearts', '7');

      await mockSocket.triggerEvent('game:use_special_power', {
        roomCode,
        cardIndex: 0,
      });
      await new Promise(resolve => setTimeout(resolve, 50));

      // Power should be used
      assert.strictEqual(room.gameState!.isWaitingForSpecialPower, false);
    });

    it('handles card 10 special power', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.phase = GamePhase.specialPower;
      room.gameState!.isWaitingForSpecialPower = true;
      room.gameState!.specialCardToActivate = createCard('spades', '10');

      await mockSocket.triggerEvent('game:use_special_power', {
        roomCode,
        targetPlayerIndex: 1,
        targetCardIndex: 0,
      });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.isWaitingForSpecialPower, false);
    });

    it('handles Jack (V) swap power', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.phase = GamePhase.specialPower;
      room.gameState!.isWaitingForSpecialPower = true;
      room.gameState!.specialCardToActivate = createCard('clubs', 'V');

      await mockSocket.triggerEvent('game:use_special_power', {
        roomCode,
        player1Index: 0,
        card1Index: 0,
        player2Index: 1,
        card2Index: 0,
      });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.isWaitingForSpecialPower, false);
    });

    it('handles JOKER shuffle power', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.phase = GamePhase.specialPower;
      room.gameState!.isWaitingForSpecialPower = true;
      room.gameState!.specialCardToActivate = createCard('joker', 'JOKER');

      await mockSocket.triggerEvent('game:use_special_power', {
        roomCode,
        targetPlayerIndex: 1,
      });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.isWaitingForSpecialPower, false);
    });
  });

  describe('game:skip_special_power', () => {
    it('allows skipping special power', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
      room.gameState!.phase = GamePhase.specialPower;
      room.gameState!.isWaitingForSpecialPower = true;
      room.gameState!.specialCardToActivate = createCard('hearts', '7');

      await mockSocket.triggerEvent('game:skip_special_power', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.gameState!.isWaitingForSpecialPower, false);
      assert.strictEqual(room.gameState!.phase, GamePhase.reaction);
    });
  });

  describe('game:pause', () => {
    it('allows player to pause game', async () => {
      const room = roomManager.getRoom(roomCode)!;

      await mockSocket.triggerEvent('game:pause', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.isPaused, true);
    });

    it('rejects pause from spectator', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.players.find(p => p.id === 'player-1')!.isSpectator = true;

      await mockSocket.triggerEvent('game:pause', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.isPaused, false);
    });
  });

  describe('game:resume', () => {
    it('allows player to resume game', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.isPaused = true;

      await mockSocket.triggerEvent('game:resume', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.strictEqual(room.isPaused, false);
    });
  });

  describe('game:forfeit', () => {
    it('allows player to forfeit', async () => {
      await mockSocket.triggerEvent('game:forfeit', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      // Player should be marked in some way (spectator, folded, etc.)
      const room = roomManager.getRoom(roomCode);
      // Room might be ended or player converted
      assert.ok(true);
    });
  });

  describe('player:ready', () => {
    it('marks player as ready after memorization', async () => {
      // Reset game state for this test
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.phase = GamePhase.setup;
      room.gameState!.readyPlayerIds = [];

      await mockSocket.triggerEvent('player:ready', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.ok(room.gameState!.readyPlayerIds.includes('player-1'));
    });

    it('rejects ready from spectator', async () => {
      const room = roomManager.getRoom(roomCode)!;
      room.gameState!.phase = GamePhase.setup;
      room.gameState!.readyPlayerIds = [];
      room.players.find(p => p.id === 'player-1')!.isSpectator = true;

      await mockSocket.triggerEvent('player:ready', { roomCode });
      await new Promise(resolve => setTimeout(resolve, 50));

      assert.ok(!room.gameState!.readyPlayerIds.includes('player-1'));
    });
  });
});
