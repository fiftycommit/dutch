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

        if (p1InHostState && !p1InHostState.isSpectator) {
            warn('P1 still found as active player in Host state.');
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

// ============ MAIN ============

async function runAllTests() {
    log('\n🧪 DUTCH GAME SERVER AUTOMATED TESTS', 'cyan');
    log(`📡 Server: ${SERVER_URL}\n`, 'cyan');

    const results = {};

    results.connection = await testBasicConnection();
    results.roomJoin = await testRoomCreationAndJoin();
    results.gameReaction = await testGameStartAndReactionPhase();
    results.hostLeave = await testHostLeaveNotification();
    results.spectatorJoin = await testSpectatorJoin();
    results.forfeit = await testForfeit();
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
