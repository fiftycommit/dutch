// Preuve payload client: reconnexions rapides du meme joueur sans duplication,
// sans socket obsolete dans la room et sans migration d'hote incoherente.
import { createRequire } from 'module';

const require = createRequire(new URL('../dutch-server/package.json', import.meta.url));
const { io } = require('socket.io-client');

const SERVER = process.env.E2E_SERVER || 'http://127.0.0.1:3000';
const AUTH = process.env.E2E_AUTH || 'http://127.0.0.1:9099';
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function tokenFor(prefix) {
  const id = Date.now().toString().slice(-7) + Math.floor(Math.random() * 900);
  const username = `${prefix}${id}`;
  const displayName = `${prefix.toUpperCase()}${id}`;
  const email = `${username}@example.com`;
  const register = await (await fetch(`${SERVER}/api/auth/register-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, displayName, email, password: 'MotDePasse123' }),
  })).json();
  if (!register.customToken) throw new Error(`register ${prefix}: ${JSON.stringify(register)}`);
  const exchange = await (await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: register.customToken, returnSecureToken: true }),
    },
  )).json();
  return { idToken: exchange.idToken, displayName };
}

function connect(idToken) {
  return new Promise((resolve, reject) => {
    const socket = io(SERVER, {
      auth: { token: idToken },
      transports: ['websocket'],
      reconnection: false,
    });
    socket.on('connect', () => resolve(socket));
    socket.on('connect_error', (error) => reject(new Error(`connect: ${error.message}`)));
    setTimeout(() => reject(new Error('connect timeout')), 8000);
  });
}

function emitAck(socket, event, data) {
  return new Promise((resolve) => {
    socket.emit(event, data, (response) => resolve(response));
    setTimeout(() => resolve(null), 6000);
  });
}

function assertSinglePlayer(room, displayName, socketId) {
  const matches = (room?.players || []).filter((player) => player.name === displayName);
  if (matches.length !== 1) {
    throw new Error(`duplication joueur ${displayName}: ${matches.length}`);
  }
  if (matches[0].id !== socketId) {
    throw new Error(`socket actif incorrect pour ${displayName}: ${matches[0].id} != ${socketId}`);
  }
}

(async () => {
  const hostUser = await tokenFor('rrh');
  const guestUser = await tokenFor('rrg');
  const host = await connect(hostUser.idToken);
  let guest = await connect(guestUser.idToken);
  const previousGuestSockets = [];

  const created = await emitAck(host, 'room:create', {
    settings: {
      gameMode: 'quick',
      numberOfPlayers: 2,
      isPublic: false,
      minPlayers: 2,
      maxPlayers: 4,
      fillBots: false,
    },
    clientId: 'rapid-host',
  });
  const roomCode = created?.room?.id || created?.roomCode;
  if (!roomCode) throw new Error(`create room KO: ${JSON.stringify(created)}`);
  console.log('room', roomCode, 'host', host.id);

  let join = await emitAck(guest, 'room:join', { roomCode, clientId: 'rapid-guest' });
  if (!join?.success) throw new Error(`join initial KO: ${JSON.stringify(join)}`);
  assertSinglePlayer(join.room, guestUser.displayName, guest.id);
  if (join.room.hostPlayerId !== host.id) throw new Error('host initial incoherent');

  for (let i = 1; i <= 5; i++) {
    previousGuestSockets.push(guest.id);
    guest.close();
    await wait(150);
    guest = await connect(guestUser.idToken);
    join = await emitAck(guest, 'room:join', { roomCode, clientId: 'rapid-guest' });
    if (!join?.success) throw new Error(`rejoin ${i} KO: ${JSON.stringify(join)}`);
    assertSinglePlayer(join.room, guestUser.displayName, guest.id);
    const socketIds = (join.room.players || []).map((player) => player.id);
    const stale = previousGuestSockets.filter((socketId) => socketIds.includes(socketId));
    if (stale.length) throw new Error(`socket obsolete encore actif: ${stale.join(',')}`);
    if (join.room.hostPlayerId !== host.id) throw new Error(`host incoherent apres rejoin ${i}`);
    console.log(`rejoin ${i}: guest actif ${guest.id}, joueurs=${join.room.players.length}`);
  }

  host.close();
  guest.close();
  console.log('\n✅ PREUVE PAYLOAD: 5 reconnexions rapides sans duplication, sans socket obsolete, host stable');
})().catch((error) => {
  console.error('❌', error.message);
  process.exit(1);
});
