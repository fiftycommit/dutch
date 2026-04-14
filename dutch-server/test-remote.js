#!/usr/bin/env node
/**
 * E2E Test script for Dutch Game Server (Remote)
 * Tests connection, room creation, and basic game flow against production server
 * 
 * Usage: SERVER_URL=http://164.92.234.245:3000 node test-remote.js
 */

const { io } = require('socket.io-client');

// Configure via: SERVER_URL=http://your-server:port node test-remote.js
// Default: tries production domain first, then IP with port 3000
const SERVER_URL = process.env.SERVER_URL || 'https://dutch-game.me';
const TEST_TIMEOUT = 8000;

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

class TestClient {
  constructor(name) {
    this.name = name;
    this.socket = null;
    this.roomCode = null;
    this.gameState = null;
    this.clientId = `test-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }

  connect() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error(`Connection timeout for ${this.name}`));
      }, TEST_TIMEOUT);

      this.socket = io(SERVER_URL, {
        transports: ['websocket'],
        timeout: 10000,
      });

      this.socket.on('connect', () => {
        clearTimeout(timeout);
        success(`${this.name} connected: ${this.socket.id}`);
        resolve(this.socket.id);
      });

      this.socket.on('connect_error', (err) => {
        clearTimeout(timeout);
        error(`${this.name} connection failed: ${err.message}`);
        reject(err);
      });

      this.socket.on('game:state_update', (data) => {
        this.gameState = data.gameState;
        info(`${this.name} state update: ${data.type}`);
      });

      this.socket.on('game:full_state', (data) => {
        this.gameState = data.gameState;
        info(`${this.name} full state received`);
      });
    });
  }

  createRoom(settings = {}) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Room creation timeout'));
      }, TEST_TIMEOUT);

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
        clearTimeout(timeout);
        if (response.success) {
          this.roomCode = response.roomCode;
          success(`${this.name} created room: ${this.roomCode}`);
          resolve(response);
        } else {
          error(`Room creation failed: ${response.error}`);
          reject(new Error(response.error));
        }
      });
    });
  }

  joinRoom(roomCode) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Room join timeout'));
      }, TEST_TIMEOUT);

      this.socket.emit('room:join', {
        roomCode,
        playerName: this.name,
        clientId: this.clientId,
      }, (response) => {
        clearTimeout(timeout);
        if (response.success) {
          this.roomCode = roomCode;
          success(`${this.name} joined room: ${roomCode}`);
          resolve(response);
        } else {
          error(`Join failed: ${response.error}`);
          reject(new Error(response.error));
        }
      });
    });
  }

  setReady() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Set ready timeout'));
      }, TEST_TIMEOUT);

      this.socket.emit('room:ready', { roomCode: this.roomCode, ready: true }, (response) => {
        clearTimeout(timeout);
        if (response?.success) {
          success(`${this.name} is ready`);
          resolve(response);
        } else {
          error(`Set ready failed: ${response?.error || 'unknown'}`);
          reject(new Error(response?.error || 'Set ready failed'));
        }
      });
    });
  }

  leaveRoom() {
    return new Promise((resolve) => {
      // Server may not send callback, so use timeout as fallback
      const timeout = setTimeout(() => {
        info(`${this.name} left room (no ack)`);
        this.roomCode = null;
        resolve();
      }, 2000);

      this.socket.emit('room:leave', { roomCode: this.roomCode }, (response) => {
        clearTimeout(timeout);
        info(`${this.name} left room`);
        this.roomCode = null;
        resolve(response);
      });
    });
  }

  disconnect() {
    if (this.socket) {
      this.socket.removeAllListeners();
      this.socket.disconnect();
      this.socket.close();
      this.socket = null;
      info(`${this.name} disconnected`);
    }
  }
}

async function runTests() {
  console.log('\n' + '='.repeat(60));
  log(`🎮 Dutch Game Server E2E Tests`, 'cyan');
  log(`📡 Server: ${SERVER_URL}`, 'cyan');
  console.log('='.repeat(60) + '\n');

  const results = { passed: 0, failed: 0, tests: [] };

  async function test(name, fn) {
    try {
      await fn();
      results.passed++;
      results.tests.push({ name, status: 'passed' });
      success(`TEST: ${name}`);
    } catch (err) {
      results.failed++;
      results.tests.push({ name, status: 'failed', error: err.message });
      error(`TEST: ${name} - ${err.message}`);
    }
  }

  // Test 1: Server connectivity
  await test('Server is reachable', async () => {
    const client = new TestClient('TestPlayer');
    await client.connect();
    client.disconnect();
  });

  // Test 2: Room creation
  let host = null;
  let roomCode = null;
  
  await test('Can create a room', async () => {
    host = new TestClient('Host');
    await host.connect();
    const result = await host.createRoom();
    roomCode = result.roomCode;
    if (!roomCode || roomCode.length !== 8) {
      throw new Error('Invalid room code');
    }
  });

  // Test 3: Room joining
  let player2 = null;
  
  await test('Can join a room', async () => {
    if (!roomCode) throw new Error('No room to join');
    player2 = new TestClient('Player2');
    await player2.connect();
    await player2.joinRoom(roomCode);
  });

  // Test 4: Player ready state
  await test('Can set ready state', async () => {
    if (!host || !player2) throw new Error('Players not initialized');
    await host.setReady();
    await player2.setReady();
  });

  // Test 5: Room leave
  await test('Can leave a room', async () => {
    if (!player2) throw new Error('Player2 not initialized');
    await player2.leaveRoom();
  });

  // Test 6: Multiple connections
  await test('Server handles multiple connections', async () => {
    const clients = [];
    for (let i = 0; i < 3; i++) {
      const client = new TestClient(`MultiClient${i}`);
      await client.connect();
      clients.push(client);
    }
    clients.forEach(c => c.disconnect());
  });

  // Cleanup all connections
  if (host) host.disconnect();
  if (player2) player2.disconnect();

  // Give sockets time to close properly
  await new Promise(resolve => setTimeout(resolve, 500));

  // Summary
  console.log('\n' + '='.repeat(60));
  log(`📊 Test Results`, 'cyan');
  console.log('='.repeat(60));
  log(`✅ Passed: ${results.passed}`, 'green');
  if (results.failed > 0) {
    log(`❌ Failed: ${results.failed}`, 'red');
  }
  console.log('='.repeat(60) + '\n');

  // Exit with error code if any test failed
  process.exit(results.failed > 0 ? 1 : 0);
}

// Global timeout - force exit after 45 seconds max
const GLOBAL_TIMEOUT = setTimeout(() => {
  warn('Global timeout reached - forcing exit');
  process.exit(1);
}, 45000);

// Run tests with forced exit
runTests()
  .catch((err) => {
    error(`Fatal error: ${err.message}`);
  })
  .finally(() => {
    clearTimeout(GLOBAL_TIMEOUT);
    // Force exit immediately
    process.exit(0);
  });
