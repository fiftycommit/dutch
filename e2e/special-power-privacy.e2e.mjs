import { createRequire } from 'module';

const require = createRequire(new URL('../dutch-server/package.json', import.meta.url));
const { io } = require('socket.io-client');

const SERVER = process.env.E2E_SERVER || 'http://127.0.0.1:3000';
const AUTH = process.env.E2E_AUTH || 'http://127.0.0.1:9099';
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function tokenFor(prefix) {
  const id = Date.now().toString().slice(-7) + Math.floor(Math.random() * 900);
  const username = `${prefix}${id}`;
  const email = `${username}@example.com`;
  const register = await (await fetch(`${SERVER}/api/auth/register-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username,
      displayName: prefix.toUpperCase() + id,
      email,
      password: 'MotDePasse123',
    }),
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
  return exchange.idToken;
}

function connect(idToken, label) {
  return new Promise((resolve, reject) => {
    const socket = io(SERVER, {
      auth: { token: idToken },
      transports: ['websocket'],
      reconnection: false,
    });
    socket._label = label;
    socket._states = [];
    socket._spied = [];
    socket._spyNotifications = [];
    socket._swapNotifications = [];
    socket._jokerNotifications = [];
    socket.on('game:state_update', (data) => socket._states.push(data.gameState));
    socket.on('game:full_state', (data) => socket._states.push(data.gameState));
    socket.on('game:spied_card', (data) => socket._spied.push(data));
    socket.on('special_power:spy_notification', (data) => socket._spyNotifications.push(data));
    socket.on('special_power:swap_notification', (data) => socket._swapNotifications.push(data));
    socket.on('special_power:joker_notification', (data) => socket._jokerNotifications.push(data));
    socket.on('connect', () => resolve(socket));
    socket.on('connect_error', (error) => reject(new Error(`${label} connect: ${error.message}`)));
    setTimeout(() => reject(new Error(`${label} connect timeout`)), 8000);
  });
}

function emitAck(socket, event, data, timeoutMs = 6000) {
  return new Promise((resolve) => {
    socket.emit(event, data, (response) => resolve(response));
    setTimeout(() => resolve(null), timeoutMs);
  });
}

function clearCaptures(...sockets) {
  for (const socket of sockets) {
    socket._states.length = 0;
    socket._spied.length = 0;
    socket._spyNotifications.length = 0;
    socket._swapNotifications.length = 0;
    socket._jokerNotifications.length = 0;
  }
}

function lastState(socket) {
  const state = socket._states.at(-1);
  if (!state) throw new Error(`${socket._label}: aucun gameState capture`);
  return state;
}

function isHidden(card) {
  return card == null || (card.hidden === true && card.value === undefined && card.suit === undefined);
}

function assertRealCard(card, value, context) {
  if (!card || card.hidden === true || card.value !== value) {
    throw new Error(`${context}: carte attendue ${value}, recu ${JSON.stringify(card)}`);
  }
}

function assertHiddenCard(card, context) {
  if (!isHidden(card)) {
    throw new Error(`${context}: carte privee en clair ${JSON.stringify(card)}`);
  }
}

function assertNonSelfHandsHidden(state, selfId, context) {
  for (const player of state.players || []) {
    if (player.id === selfId) continue;
    for (const card of player.hand || []) {
      if (!isHidden(card)) {
        throw new Error(`${context}: main non-self en clair pour ${player.id}: ${JSON.stringify(card)}`);
      }
    }
  }
}

function playerIndex(state, id) {
  const index = (state.players || []).findIndex((player) => player.id === id);
  if (index < 0) throw new Error(`player index introuvable: ${id}`);
  return index;
}

async function forcePower({ actor, roomCode, power, hands }) {
  const ack = await emitAck(actor, 'test:force_special_power', {
    roomCode,
    actorId: actor.id,
    power,
    hands,
  });
  if (!ack?.ok) throw new Error(`force ${power} KO: ${JSON.stringify(ack)}`);
  await wait(700);
}

async function assertPower7(roomCode, actor, other, spectator) {
  clearCaptures(actor, other, spectator);
  await forcePower({
    actor,
    roomCode,
    power: '7',
    hands: {
      [actor.id]: ['R', '2', '3', '4'],
      [other.id]: ['5', '6', '8', '9'],
    },
  });
  clearCaptures(actor, other, spectator);
  const ack = await emitAck(actor, 'game:use_special_power', { roomCode, cardIndex: 0 });
  if (!ack?.ok) throw new Error(`power 7 KO: ${JSON.stringify(ack)}`);
  await wait(900);

  assertRealCard(actor._spied.at(-1)?.card, 'R', 'power7 acteur game:spied_card');
  assertRealCard(lastState(actor).lastSpiedCard, 'R', 'power7 acteur lastSpiedCard');
  assertHiddenCard(lastState(other).lastSpiedCard, 'power7 adversaire lastSpiedCard');
  assertHiddenCard(lastState(spectator).lastSpiedCard, 'power7 spectateur lastSpiedCard');
  if (other._spied.length || spectator._spied.length) throw new Error('power7: game:spied_card envoye hors acteur');
  assertNonSelfHandsHidden(lastState(other), other.id, 'power7 adversaire payload');
  assertNonSelfHandsHidden(lastState(spectator), spectator.id, 'power7 spectateur payload');
}

async function assertPower10(roomCode, actor, other, spectator) {
  clearCaptures(actor, other, spectator);
  await forcePower({
    actor,
    roomCode,
    power: '10',
    hands: {
      [actor.id]: ['2', '3', '4', '5'],
      [other.id]: ['D', '6', '8', '9'],
    },
  });
  const state = lastState(actor);
  const targetPlayerIndex = playerIndex(state, other.id);

  clearCaptures(actor, other, spectator);
  const ack = await emitAck(actor, 'game:use_special_power', {
    roomCode,
    targetPlayerIndex,
    targetCardIndex: 0,
  });
  if (!ack?.ok) throw new Error(`power 10 KO: ${JSON.stringify(ack)}`);
  await wait(900);

  assertRealCard(actor._spied.at(-1)?.card, 'D', 'power10 acteur game:spied_card');
  assertRealCard(lastState(actor).lastSpiedCard, 'D', 'power10 acteur lastSpiedCard');
  assertHiddenCard(lastState(other).lastSpiedCard, 'power10 adversaire lastSpiedCard');
  assertHiddenCard(lastState(spectator).lastSpiedCard, 'power10 spectateur lastSpiedCard');
  if (other._spied.length || spectator._spied.length) throw new Error('power10: game:spied_card envoye hors acteur');
  if (JSON.stringify(other._spyNotifications).includes('"D"')) throw new Error('power10: notification adversaire contient la carte');
  if (JSON.stringify(spectator._spyNotifications).includes('"D"')) throw new Error('power10: notification spectateur contient la carte');
  assertNonSelfHandsHidden(lastState(actor), actor.id, 'power10 acteur payload');
  assertNonSelfHandsHidden(lastState(spectator), spectator.id, 'power10 spectateur payload');
}

async function assertJack(roomCode, actor, other, spectator) {
  clearCaptures(actor, other, spectator);
  await forcePower({
    actor,
    roomCode,
    power: 'V',
    hands: {
      [actor.id]: ['R', '2', '3', '4'],
      [other.id]: ['A', '6', '8', '9'],
    },
  });
  const state = lastState(actor);
  const actorIndex = playerIndex(state, actor.id);
  const otherIndex = playerIndex(state, other.id);

  clearCaptures(actor, other, spectator);
  const ack = await emitAck(actor, 'game:use_special_power', {
    roomCode,
    player1Index: actorIndex,
    card1Index: 0,
    player2Index: otherIndex,
    card2Index: 0,
  });
  if (!ack?.ok) throw new Error(`power V KO: ${JSON.stringify(ack)}`);
  await wait(900);

  if (actor._spied.length || other._spied.length || spectator._spied.length) {
    throw new Error('power V: evenement spied_card inattendu');
  }
  assertHiddenCard(lastState(actor).lastSpiedCard, 'power V acteur lastSpiedCard');
  assertHiddenCard(lastState(other).lastSpiedCard, 'power V adversaire lastSpiedCard');
  assertHiddenCard(lastState(spectator).lastSpiedCard, 'power V spectateur lastSpiedCard');
  assertNonSelfHandsHidden(lastState(actor), actor.id, 'power V acteur payload');
  assertNonSelfHandsHidden(lastState(other), other.id, 'power V adversaire payload');
  assertNonSelfHandsHidden(lastState(spectator), spectator.id, 'power V spectateur payload');
  if (JSON.stringify(other._swapNotifications).includes('"R"') ||
      JSON.stringify(other._swapNotifications).includes('"A"')) {
    throw new Error('power V: notification swap contient une valeur de carte');
  }
}

async function assertJoker(roomCode, actor, other, spectator) {
  clearCaptures(actor, other, spectator);
  await forcePower({
    actor,
    roomCode,
    power: 'JOKER',
    hands: {
      [actor.id]: ['R', '2', '3', '4'],
      [other.id]: ['A', '6', '8', '9'],
    },
  });
  const state = lastState(actor);
  const otherIndex = playerIndex(state, other.id);

  clearCaptures(actor, other, spectator);
  const ack = await emitAck(actor, 'game:use_special_power', {
    roomCode,
    targetPlayerIndex: otherIndex,
  });
  if (!ack?.ok) throw new Error(`power JOKER KO: ${JSON.stringify(ack)}`);
  await wait(900);

  if (actor._spied.length || other._spied.length || spectator._spied.length) {
    throw new Error('power JOKER: evenement spied_card inattendu');
  }
  assertHiddenCard(lastState(actor).lastSpiedCard, 'power JOKER acteur lastSpiedCard');
  assertHiddenCard(lastState(other).lastSpiedCard, 'power JOKER adversaire lastSpiedCard');
  assertHiddenCard(lastState(spectator).lastSpiedCard, 'power JOKER spectateur lastSpiedCard');
  assertNonSelfHandsHidden(lastState(actor), actor.id, 'power JOKER acteur payload');
  assertNonSelfHandsHidden(lastState(spectator), spectator.id, 'power JOKER spectateur payload');
  if (JSON.stringify(other._jokerNotifications).includes('"A"') ||
      JSON.stringify(other._jokerNotifications).includes('"R"')) {
    throw new Error('power JOKER: notification contient une valeur de carte');
  }
}

(async () => {
  const [t1, t2, ts] = await Promise.all([tokenFor('pp1'), tokenFor('pp2'), tokenFor('pps')]);
  const p1 = await connect(t1, 'p1');
  const p2 = await connect(t2, 'p2');
  const spectator = await connect(ts, 'spectator');

  const created = await emitAck(p1, 'room:create', {
    settings: {
      gameMode: 'quick',
      numberOfPlayers: 2,
      isPublic: false,
      minPlayers: 2,
      maxPlayers: 4,
      fillBots: false,
      reactionTimeMs: 1000,
    },
    clientId: 'power-privacy-host',
  });
  const roomCode = created?.room?.id || created?.roomCode;
  if (!roomCode) throw new Error(`create room KO: ${JSON.stringify(created)}`);

  const joined = await emitAck(p2, 'room:join', { roomCode, clientId: 'power-privacy-guest' });
  if (!joined?.success) throw new Error(`join p2 KO: ${JSON.stringify(joined)}`);
  await emitAck(p1, 'room:ready', { roomCode, ready: true });
  await emitAck(p2, 'room:ready', { roomCode, ready: true });
  const started = await emitAck(p1, 'room:start_game', { roomCode, fillBots: false });
  if (started && started.success === false) throw new Error(`start KO: ${JSON.stringify(started)}`);
  await wait(1200);
  await emitAck(p1, 'player:ready', { roomCode });
  await emitAck(p2, 'player:ready', { roomCode });
  await wait(1200);
  const specJoin = await emitAck(spectator, 'room:join', { roomCode, clientId: 'power-privacy-spec' });
  if (!specJoin?.success) throw new Error(`join spectator KO: ${JSON.stringify(specJoin)}`);
  await wait(1200);

  await assertPower7(roomCode, p1, p2, spectator);
  console.log('power 7 payload privacy OK');
  await assertPower10(roomCode, p1, p2, spectator);
  console.log('power 10 / lastSpiedCard payload privacy OK');
  await assertJack(roomCode, p1, p2, spectator);
  console.log('power V payload privacy OK');
  await assertJoker(roomCode, p1, p2, spectator);
  console.log('power JOKER payload privacy OK');

  p1.close();
  p2.close();
  spectator.close();
  console.log('\n✅ PREUVE PAYLOAD: lastSpiedCard + pouvoirs 7/10/V/JOKER restent privés dans les vrais payloads Socket.IO');
})().catch((error) => {
  console.error('❌', error.message);
  process.exit(1);
});
