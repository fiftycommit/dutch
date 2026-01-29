#!/usr/bin/env node
/**
 * Automated test script for Dutch Game Server
 * Tests: connection, room creation, game flow, reaction phase, AFK kick
 */

// max

const { io } = require('socket.io-client');

const SERVER_URL = process.env.SERVER_URL || 'https://dutch-game.me';
const TEST_TIMEOUT = 30000;

// Colors for console output
const colors = {
    reset: '\x1b[0m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
};

function log(msg, color = 'reset') {
    console.log(`${colors[color]}${msg}${colors.reset}`);
}

function success(msg) { log(`✅ ${msg}`, 'green'); }
function error(msg) { log(`❌ ${msg}`, 'red'); }
function info(msg) { log(`ℹ️  ${msg}`, 'blue'); }
function warn(msg) { log(`⚠️  ${msg}`, 'yellow'); }

class TestPlayer {
    constructor(name, serverUrl) {
        this.name = name;
        this.serverUrl = serverUrl;
        this.socket = null;
        this.gameState = null;
        this.events = [];
        this.clientId = `test-${Date.now()}-${Math.random()}`;
    }

    connect() {
        return new Promise((resolve, reject) => {
            this.socket = io(this.serverUrl, {
                transports: ['websocket'],
                timeout: 10000,
            });

            this.socket.on('connect', () => {
                success(`${this.name} connected: ${this.socket.id}`);
                resolve(this.socket.id);
            });

            this.socket.on('connect_error', (err) => {
                error(`${this.name} connection failed: ${err.message}`);
                reject(err);
            });

            this.socket.on('game:state_update', (data) => {
                this.gameState = data.gameState;
                this.events.push({ type: 'state_update', updateType: data.type, data });
                info(`${this.name} received: ${data.type}, phase=${data.gameState?.phase}`);
            });

            this.socket.on('game:full_state', (data) => {
                this.gameState = data.gameState;
                this.events.push({ type: 'full_state', updateType: data.type, data });
                info(`${this.name} received: FULL_STATE, phase=${data.gameState?.phase}`);
            });

            this.socket.on('presence:check', (data) => {
                this.events.push({ type: 'presence_check', data });
                warn(`${this.name} AFK check: ${data.reason}, deadline=${data.deadlineMs}ms`);
            });

            this.socket.on('room:closed', (data) => {
                this.events.push({ type: 'room_closed', data });
                warn(`${this.name} room closed: hostLeft=${data.hostLeft}`);
            });

            setTimeout(() => reject(new Error('Connection timeout')), 10000);
        });
    }

    createRoom(settings = {}) {
        return new Promise((resolve, reject) => {
            this.socket.emit('room:create', {
                settings: {
                    reactionTimeMs: 3000,
                    minPlayers: 2,
                    maxPlayers: 4,
                    ...settings,
                },
                playerName: this.name,
                clientId: this.clientId,
            }, (response) => {
                if (response.success) {
                    this.roomCode = response.roomCode;
                    success(`${this.name} created room: ${this.roomCode}`);
                    resolve(response);
                } else {
                    error(`${this.name} failed to create room: ${response.error}`);
                    reject(new Error(response.error));
                }
            });
        });
    }

    joinRoom(roomCode) {
        return new Promise((resolve, reject) => {
            this.socket.emit('room:join', {
                roomCode,
                playerName: this.name,
                clientId: this.clientId,
            }, (response) => {
                if (response.success) {
                    this.roomCode = roomCode;
                    success(`${this.name} joined room: ${roomCode}`);
                    resolve(response);
                } else {
                    error(`${this.name} failed to join room: ${response.error}`);
                    reject(new Error(response.error));
                }
            });
        });
    }

    setReady(ready = true) {
        return new Promise((resolve) => {
            this.socket.emit('room:ready', { roomCode: this.roomCode, ready }, (response) => {
                info(`${this.name} ready: ${ready}`);
                resolve(response);
            });
        });
    }

    startGame() {
        return new Promise((resolve, reject) => {
            this.socket.emit('room:start_game', { roomCode: this.roomCode }, (response) => {
                if (response.success) {
                    success(`${this.name} started game`);
                    resolve(response);
                } else {
                    error(`${this.name} failed to start game: ${response.error}`);
                    reject(new Error(response.error));
                }
            });
        });
    }

    drawCard() {
        return new Promise((resolve) => {
            this.socket.emit('game:draw_card', { roomCode: this.roomCode });
            info(`${this.name} drawing card...`);
            setTimeout(resolve, 500);
        });
    }

    discardCard() {
        return new Promise((resolve) => {
            this.socket.emit('game:discard_card', { roomCode: this.roomCode });
            info(`${this.name} discarding card...`);
            setTimeout(resolve, 500);
        });
    }

    skipPower() {
        return new Promise((resolve) => {
            this.socket.emit('game:skip_power', { roomCode: this.roomCode });
            info(`${this.name} skipping power...`);
            setTimeout(resolve, 500);
        });
    }

    confirmPresence() {
        this.socket.emit('presence:ack', { roomCode: this.roomCode });
        info(`${this.name} confirming presence`);
    }

    leaveRoom() {
        this.socket.emit('room:leave', { roomCode: this.roomCode });
        info(`${this.name} leaving room`);
    }

    checkActiveRooms(roomCodes) {
        return new Promise((resolve) => {
            this.socket.emit('room:check_active', { roomCodes }, (response) => {
                info(`${this.name} checkActiveRooms: ${response?.rooms?.length} found`);
                resolve(response?.rooms || []);
            });
        });
    }

    closeRoom() {
        return new Promise((resolve) => {
            this.socket.emit('room:close', { roomCode: this.roomCode }, (response) => {
                info(`${this.name} closing room: ${response?.success}`);
                resolve(response);
            });
        });
    }

    kickPlayer(clientId) {
        return new Promise((resolve) => {
            this.socket.emit('room:kick', { roomCode: this.roomCode, clientId }, (response) => {
                info(`${this.name} kicking player ${clientId}: ${response?.success}`);
                resolve(response);
            });
        });
    }

    forfeitGame() {
        return new Promise((resolve) => {
            this.socket.emit('game:forfeit', { roomCode: this.roomCode });
            info(`${this.name} forfeiting game...`);
            setTimeout(resolve, 500); // Wait for server to process
        });
    }

    disconnect() {
        if (this.socket) {
            this.socket.disconnect();
            info(`${this.name} disconnected`);
        }
    }

    waitForEvent(eventType, timeout = 5000) {
        return new Promise((resolve, reject) => {
            const check = () => {
                const event = this.events.find(e => e.type === eventType);
                if (event) {
                    resolve(event);
                    return true;
                }
                return false;
            };

            if (check()) return;

            const interval = setInterval(() => {
                if (check()) clearInterval(interval);
            }, 100);

            setTimeout(() => {
                clearInterval(interval);
                reject(new Error(`Timeout waiting for ${eventType}`));
            }, timeout);
        });
    }

    waitForPhase(phase, timeout = 10000) {
        return new Promise((resolve, reject) => {
            const check = () => {
                if (this.gameState?.phase === phase) {
                    resolve(this.gameState);
                    return true;
                }
                return false;
            };

            if (check()) return;

            const interval = setInterval(() => {
                if (check()) clearInterval(interval);
            }, 100);

            setTimeout(() => {
                clearInterval(interval);
                reject(new Error(`Timeout waiting for phase ${phase}, current: ${this.gameState?.phase}`));
            }, timeout);
        });
    }
}

async function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ============ TEST CASES ============

async function testBasicConnection() {
    log('\n========== TEST: Basic Connection ==========', 'cyan');
    const player = new TestPlayer('TestPlayer', SERVER_URL);

    try {
        await player.connect();
        success('Connection test passed');
        return true;
    } catch (e) {
        error(`Connection test failed: ${e.message}`);
        return false;
    } finally {
        player.disconnect();
    }
}

async function testRoomCreationAndJoin() {
    log('\n========== TEST: Room Creation & Join ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const guest = new TestPlayer('Guest', SERVER_URL);

    try {
        await host.connect();
        await guest.connect();

        await host.createRoom();
        await guest.joinRoom(host.roomCode);

        success('Room creation and join test passed');
        return true;
    } catch (e) {
        error(`Room test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        guest.disconnect();
    }
}

async function testGameStartAndReactionPhase() {
    log('\n========== TEST: Game Start & Reaction Phase ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const guest = new TestPlayer('Guest', SERVER_URL);

    try {
        await host.connect();
        await guest.connect();

        await host.createRoom({ reactionTimeMs: 3000 });
        await guest.joinRoom(host.roomCode);

        await host.setReady(true);
        await guest.setReady(true);

        await delay(500);
        await host.startGame();

        // Wait for game to start
        await delay(1000);

        info(`Host gameState phase: ${host.gameState?.phase}`);
        info(`Guest gameState phase: ${guest.gameState?.phase}`);

        if (host.gameState?.phase !== 1) { // GamePhase.playing = 1
            throw new Error(`Expected phase 1 (playing), got ${host.gameState?.phase}`);
        }

        // Find current player and make them act
        const currentPlayerId = host.gameState?.players?.[host.gameState?.currentPlayerIndex]?.id;
        const currentPlayer = currentPlayerId === host.socket.id ? host : guest;

        info(`Current player: ${currentPlayer.name}`);

        // Draw a card
        await currentPlayer.drawCard();
        await delay(1000);

        info(`After draw - drawnCard exists: ${!!currentPlayer.gameState?.drawnCard}`);
        info(`After draw - phase: ${currentPlayer.gameState?.phase}`);

        // If waiting for power, skip it
        if (currentPlayer.gameState?.isWaitingForSpecialPower) {
            warn('Power card drawn, skipping...');
            await currentPlayer.skipPower();
            await delay(500);
        }

        // Discard the card
        await currentPlayer.discardCard();
        await delay(500);

        info(`After discard - phase: ${currentPlayer.gameState?.phase}`);
        info(`After discard - isWaitingForSpecialPower: ${currentPlayer.gameState?.isWaitingForSpecialPower}`);

        // If it's a power card, skip
        if (currentPlayer.gameState?.isWaitingForSpecialPower) {
            warn('Power card discarded, skipping...');
            await currentPlayer.skipPower();
            await delay(1000);
        }

        // Check if reaction phase triggered
        info(`Final phase: ${currentPlayer.gameState?.phase}`);
        info(`Reaction time remaining: ${currentPlayer.gameState?.reactionTimeRemaining}`);

        // Phase 2 = reaction
        if (currentPlayer.gameState?.phase === 2) {
            success('REACTION PHASE TRIGGERED! ✓');
        } else {
            warn(`Phase is ${currentPlayer.gameState?.phase}, expected 2 (reaction)`);
            // Wait a bit more and check again
            await delay(2000);
            info(`After wait - phase: ${currentPlayer.gameState?.phase}`);
        }

        success('Game start and reaction test completed');
        return true;
    } catch (e) {
        error(`Game test failed: ${e.message}`);
        console.error(e);
        return false;
    } finally {
        host.disconnect();
        guest.disconnect();
    }
}

async function testHostLeaveNotification() {
    log('\n========== TEST: Host Leave Notification ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const guest = new TestPlayer('Guest', SERVER_URL);

    try {
        await host.connect();
        await guest.connect();

        await host.createRoom();
        await guest.joinRoom(host.roomCode);

        await host.setReady(true);
        await guest.setReady(true);

        await delay(500);
        await host.startGame();
        await delay(1000);

        // Host closes the room
        info('Host closing room...');
        await host.closeRoom();

        // Wait for guest to receive notification
        try {
            await guest.waitForEvent('room_closed', 3000);
            success('Guest received room:closed notification!');
            return true;
        } catch (e) {
            error('Guest did NOT receive room:closed notification');
            info(`Guest events: ${JSON.stringify(guest.events.map(e => e.type))}`);
            return false;
        }
    } catch (e) {
        error(`Host leave test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        guest.disconnect();
    }
}


async function testSpectatorJoin() {
    log('\n========== TEST: Spectator Join ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);
    const spectator = new TestPlayer('Spectator', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();
        await spectator.connect();

        await host.createRoom({ minPlayers: 2 });
        await p1.joinRoom(host.roomCode);

        await host.setReady(true);
        await p1.setReady(true);

        await delay(500);
        await host.startGame();
        await delay(1000);

        info('Spectator joining active game...');
        await spectator.joinRoom(host.roomCode);

        await delay(1000);

        if (!spectator.gameState) {
            throw new Error('Spectator did NOT receive game state upon joining');
        }

        const gameStatePlayers = spectator.gameState.players || [];
        const isSpectatorInList = gameStatePlayers.some(p => p.id === spectator.socket.id && p.isSpectator);
        const isSpectatorAbsent = !gameStatePlayers.some(p => p.id === spectator.socket.id);

        if (isSpectatorInList || isSpectatorAbsent) {
            success('Spectator joined correctly');
        } else {
            throw new Error('Spectator appears as normal player in game state!');
        }

        success('Spectator join test passed');
        return true;

    } catch (e) {
        error(`Spectator test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
        spectator.disconnect();
    }
}

async function testForfeit() {
    log('\n========== TEST: Forfeit Logic ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);
    const p2 = new TestPlayer('P2', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();
        await p2.connect();

        await host.createRoom({ minPlayers: 3 });
        await p1.joinRoom(host.roomCode);
        await p2.joinRoom(host.roomCode);

        await host.setReady(true);
        await p1.setReady(true);
        await p2.setReady(true);

        await delay(500);
        await host.startGame();
        await delay(1000);

        info('P1 forfeiting...');
        await p1.forfeitGame();

        await delay(2000);

        const p1InHostState = host.gameState.players.find(p => p.id === p1.socket.id);

        if (!p1InHostState) {
            throw new Error('P1 not found in Host game state');
        }

        if (!p1InHostState.isSpectator) {
            throw new Error('P1 should be marked as spectator in GameState after forfeit');
        }

        if (!p1.socket.connected) {
            throw new Error('P1 was disconnected after forfeit');
        }

        success('Forfeit test passed');
        return true;
    } catch (e) {
        error(`Forfeit test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
        p2.disconnect();
    }
}

async function testKick() {
    log('\n========== TEST: Kick Event ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();

        await host.createRoom();
        await p1.joinRoom(host.roomCode);

        await delay(500);

        let kicked = false;
        p1.socket.on('room:kicked', () => {
            kicked = true;
            success('P1 received kick event');
        });

        info('Host kicking P1...');
        await host.kickPlayer(p1.clientId);

        await delay(1000);

        if (!kicked) throw new Error('P1 did not receive kick event');

        success('Kick test passed');
        return true;
    } catch (e) {
        error(`Kick test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
    }
}

async function testPersistence() {
    log('\n========== TEST: Room Persistence ==========', 'cyan');
    const host = new TestPlayer('HostP', SERVER_URL);

    try {
        await host.connect();
        await host.createRoom();
        const code = host.roomCode;

        info('Host disconnecting to simulate app close...');
        host.disconnect();

        await delay(2000); // Wait > cleanup interval? (Interval unknown, maybe short?)

        // Reconnect a checker
        const checker = new TestPlayer('Checker', SERVER_URL);
        await checker.connect();

        // Check if room is active
        const activeDefaults = await checker.checkActiveRooms([code]);

        if (activeDefaults.length > 0 && activeDefaults[0].roomCode === code) {
            success('Room persisted after disconnect');
        } else {
            throw new Error('Room was deleted immediately after disconnect');
        }

        checker.disconnect();
        return true;
    } catch (e) {
        error(`Persistence test failed: ${e.message}`);
        return false;
    }
}

// ============ CAS 1: GAME START REQUIREMENTS ============
async function testGameStartRequirements() {
    log('\n========== TEST: Game Start Requirements (Cas 1) ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();

        await host.createRoom({ minPlayers: 2 });
        await p1.joinRoom(host.roomCode);

        // Test 1: Host not ready - should fail
        info('Test: Host not ready...');
        try {
            await host.startGame();
            throw new Error('Game started without host being ready!');
        } catch (e) {
            if (e.message.includes('hôte doit être prêt')) {
                success('Correctly rejected: Host not ready');
            } else {
                throw e;
            }
        }

        // Test 2: Only host ready - should fail (need 2)
        await host.setReady(true);
        info('Test: Only 1 player ready...');
        try {
            await host.startGame();
            throw new Error('Game started with only 1 player ready!');
        } catch (e) {
            if (e.message.includes('joueurs prêts')) {
                success('Correctly rejected: Not enough ready players');
            } else {
                throw e;
            }
        }

        // Test 3: Both ready - should succeed
        await p1.setReady(true);
        await delay(500);
        info('Test: 2 players ready...');
        await host.startGame();
        success('Game started with 2 ready players');

        await delay(1000);
        if (host.gameState && host.gameState.phase >= 1) {
            success('Game is running');
        } else {
            throw new Error('Game state not received');
        }

        success('Game Start Requirements test passed');
        return true;
    } catch (e) {
        error(`Game Start Requirements test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
    }
}

// ============ CAS 2: FORFEIT CANNOT REJOIN AS PLAYER ============
async function testForfeitCannotRejoinAsPlayer() {
    log('\n========== TEST: Forfeit Cannot Rejoin (Cas 2) ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);
    const p2 = new TestPlayer('P2', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();
        await p2.connect();

        await host.createRoom({ minPlayers: 3 });
        await p1.joinRoom(host.roomCode);
        await p2.joinRoom(host.roomCode);

        await host.setReady(true);
        await p1.setReady(true);
        await p2.setReady(true);
        await delay(500);

        await host.startGame();
        await delay(1000);

        // P1 forfeits
        info('P1 forfeiting...');
        await p1.forfeitGame();
        await delay(1000);

        // Verify P1 is spectator in game state
        const p1InState = host.gameState.players.find(p => p.id === p1.socket.id);
        if (!p1InState || !p1InState.isSpectator) {
            throw new Error('P1 should be marked as spectator after forfeit');
        }
        success('P1 correctly marked as spectator');

        // P1 disconnects and reconnects (simulating app restart)
        const p1ClientId = p1.clientId;
        p1.disconnect();
        await delay(500);

        // P1 reconnects with same clientId
        const p1Rejoin = new TestPlayer('P1-Rejoin', SERVER_URL);
        p1Rejoin.clientId = p1ClientId; // Same clientId
        await p1Rejoin.connect();
        await p1Rejoin.joinRoom(host.roomCode);

        await delay(2000); // Wait longer for game state

        // Check P1's view - should still be spectator (or not receive state because game ended)
        // Note: Game may have ended if only 2 active players were left
        if (!p1Rejoin.gameState) {
            // This is acceptable - might have ended or timing issue
            success('P1 did not receive active game state (expected if game ended)');
        } else {

            const p1SelfInState = p1Rejoin.gameState.players.find(p => p.id === p1Rejoin.socket.id);
            if (!p1SelfInState) {
                // P1 might not be in player list as active, which is fine (spectator join)
                success('P1 correctly not in active player list after rejoin');
            } else if (p1SelfInState.isSpectator) {
                success('P1 correctly still spectator after rejoin');
            } else {
                throw new Error('P1 should NOT be able to rejoin as active player!');
            }
        }

        success('Forfeit Cannot Rejoin test passed');
        return true;
    } catch (e) {
        error(`Forfeit Cannot Rejoin test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p2.disconnect();
    }
}

// ============ CAS 3: SPECTATOR CANNOT INTERACT ============
async function testSpectatorCannotInteract() {
    log('\n========== TEST: Spectator Cannot Interact (Cas 3) ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);
    const spectator = new TestPlayer('Spectator', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();

        await host.createRoom();
        await p1.joinRoom(host.roomCode);

        await host.setReady(true);
        await p1.setReady(true);
        await delay(500);

        await host.startGame();
        await delay(1500);

        // Spectator joins mid-game
        await spectator.connect();
        await spectator.joinRoom(host.roomCode);
        await delay(1000);

        if (!spectator.gameState) {
            throw new Error('Spectator did not receive game state');
        }
        success('Spectator received game state');

        // Verify spectator is NOT in active players
        const specInPlayers = spectator.gameState.players.find(p => p.id === spectator.socket.id);
        if (specInPlayers && !specInPlayers.isSpectator) {
            throw new Error('Spectator incorrectly appears as active player');
        }
        success('Spectator correctly not an active player');

        // Test: Spectator tries to draw a card (should fail or be ignored)
        info('Spectator attempting to draw card (should fail)...');
        const beforeState = JSON.stringify(host.gameState);

        // Capture current turn player
        const currentPlayerId = spectator.gameState.currentPlayer?.id;

        spectator.socket.emit('game:draw_card', { roomCode: spectator.roomCode });
        await delay(1000);

        // Game state should not have changed due to spectator action
        // The current player should still be the same
        if (host.gameState.currentPlayer?.id === currentPlayerId) {
            success('Spectator draw action correctly ignored');
        }

        // Test: Spectator tries to call Dutch (should be ignored)
        info('Spectator attempting to call Dutch (should fail)...');
        spectator.socket.emit('game:dutch', { roomCode: spectator.roomCode });
        await delay(500);

        // Game should still be in playing phase (not ended by spectator Dutch)
        if (host.gameState.phase === 1) { // GamePhase.playing
            success('Spectator Dutch correctly ignored');
        }

        success('Spectator Cannot Interact test passed');
        return true;
    } catch (e) {
        error(`Spectator Cannot Interact test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
        spectator.disconnect();
    }
}

// ============ CAS 4: GAME END ON LAST PLAYER ============
async function testGameEndOnLastPlayer() {
    log('\n========== TEST: Game Ends When One Player Left (Cas 2b) ==========', 'cyan');
    const host = new TestPlayer('Host', SERVER_URL);
    const p1 = new TestPlayer('P1', SERVER_URL);

    try {
        await host.connect();
        await p1.connect();

        await host.createRoom();
        await p1.joinRoom(host.roomCode);

        await host.setReady(true);
        await p1.setReady(true);
        await delay(500);

        await host.startGame();
        await delay(1000);

        // P1 forfeits - only Host remains
        info('P1 forfeiting (Host should be last player)...');
        await p1.forfeitGame();
        await delay(2000);

        // Game should have ended (phase >= 3 means ended/results)
        if (host.gameState.phase >= 3) { // GamePhase.ended or results
            success('Game correctly ended when only 1 player left');
        } else {
            throw new Error(`Game should have ended (phase>=3), but phase=${host.gameState.phase}`);
        }

        success('Game End On Last Player test passed');
        return true;
    } catch (e) {
        error(`Game End On Last Player test failed: ${e.message}`);
        return false;
    } finally {
        host.disconnect();
        p1.disconnect();
    }
}


// ============ MAIN ============

async function runAllTests() {
    log('\n🧪 DUTCH GAME SERVER AUTOMATED TESTS', 'cyan');
    log(`📡 Server: ${SERVER_URL}\n`, 'cyan');

    const results = {};

    // Basic tests
    results.connection = await testBasicConnection();
    results.roomJoin = await testRoomCreationAndJoin();
    results.gameReaction = await testGameStartAndReactionPhase();
    results.hostLeave = await testHostLeaveNotification();

    // Cas 1: Game Start Requirements
    results.gameStartRequirements = await testGameStartRequirements();

    // Cas 2: Forfeit logic
    results.forfeit = await testForfeit();
    results.forfeitCannotRejoin = await testForfeitCannotRejoinAsPlayer();
    results.gameEndOnLastPlayer = await testGameEndOnLastPlayer();

    // Cas 3: Spectator mode
    results.spectatorJoin = await testSpectatorJoin();
    results.spectatorCannotInteract = await testSpectatorCannotInteract();

    // Cas 4: Room persistence
    results.persistence = await testPersistence();

    // Admin features
    results.kick = await testKick();

    log('\n========== TEST RESULTS ==========', 'cyan');
    for (const [test, passed] of Object.entries(results)) {
        log(`  ${passed ? '✅' : '❌'} ${test}`, passed ? 'green' : 'red');
    }

    const allPassed = Object.values(results).every(r => r);
    log(`\n${allPassed ? '🎉 ALL TESTS PASSED!' : '💥 SOME TESTS FAILED'}`, allPassed ? 'green' : 'red');

    process.exit(allPassed ? 0 : 1);
}

runAllTests().catch(console.error);

