import { chromium } from 'playwright';
import {
  attachLoginProbe,
  createPrivateRoom,
  hasBlockingError,
  hasGameTable,
  joinPrivateRoom,
  login,
  log,
  memorize,
  nudge,
  playOneVisibleTurn,
  seed,
  setReadyAndStart,
  waitForHostUi,
} from './multiplayer-flow.mjs';

async function lobbyHostOfflineDoesNotReturnHost(browser) {
  const userA = await seed('dnla');
  const userB = await seed('dnlb');
  const ctxA = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxB = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A = await ctxA.newPage();
  const B = await ctxB.newPage();
  attachLoginProbe(A);
  attachLoginProbe(B);

  await login(A, userA.email, 'A-lobby');
  const code = await createPrivateRoom(A);
  await login(B, userB.email, 'B-lobby');
  await joinPrivateRoom(B, code);
  const bBefore = await waitForHostUi(B, false, 8000);
  if (bBefore.controls || bBefore.badge) throw new Error('B deja hote avant coupure reseau A');

  log('>>> reseau A OFFLINE en lobby');
  await ctxA.setOffline(true);
  const bAfter = await waitForHostUi(B, true, 35000);
  if (!bAfter.controls || !bAfter.badge) throw new Error('B ne devient pas hote apres offline A en lobby');

  log('>>> reseau A ONLINE en lobby');
  await ctxA.setOffline(false);
  const aAfterReturn = await waitForHostUi(A, false, 35000);
  const bFinal = await waitForHostUi(B, true, 12000);
  if (aAfterReturn.controls || aAfterReturn.badge || !bFinal.controls || !bFinal.badge) {
    throw new Error(`retour A incoherent: A=${JSON.stringify(aAfterReturn)} B=${JSON.stringify(bFinal)}`);
  }

  await ctxA.close();
  await ctxB.close();
  log('degraded lobby OK');
}

async function inGameHostOfflineKeepsGamePlayable(browser) {
  const [userA, userB, userC] = await Promise.all([
    seed('dnga'),
    seed('dngb'),
    seed('dngc'),
  ]);
  const ctxA = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxB = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxC = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A = await ctxA.newPage();
  const B = await ctxB.newPage();
  const C = await ctxC.newPage();
  [A, B, C].forEach(attachLoginProbe);

  await login(A, userA.email, 'A-game');
  const code = await createPrivateRoom(A);
  await login(B, userB.email, 'B-game');
  await joinPrivateRoom(B, code);
  await login(C, userC.email, 'C-game');
  await joinPrivateRoom(C, code);

  await setReadyAndStart(A, [B, C]);
  await memorize(A);
  await memorize(B);
  await memorize(C);

  let tableReady = false;
  for (let i = 0; i < 40; i++) {
    await B.waitForTimeout(800);
    await nudge(B);
    await nudge(C);
    tableReady = (await hasGameTable(B)) && (await hasGameTable(C));
    if (tableReady) break;
  }
  if (!tableReady) throw new Error('table absente avant coupure reseau en partie');

  log('>>> reseau A OFFLINE en partie');
  await ctxA.setOffline(true);
  let bTable = false;
  let cTable = false;
  let bError = true;
  let cError = true;
  for (let i = 0; i < 35; i++) {
    await B.waitForTimeout(1000);
    await nudge(B);
    await nudge(C);
    bTable = await hasGameTable(B);
    cTable = await hasGameTable(C);
    bError = await hasBlockingError(B);
    cError = await hasBlockingError(C);
    if (bTable && cTable && !bError && !cError) break;
  }
  if (!bTable || !cTable || bError || cError) {
    throw new Error(`etat incoherent apres offline A: B table=${bTable} err=${bError}, C table=${cTable} err=${cError}`);
  }

  const actor = await playOneVisibleTurn([
    { page: B, name: 'B-game' },
    { page: C, name: 'C-game' },
  ], 90000);
  if (!actor) throw new Error('aucune action jouable apres coupure reseau hote en partie');

  await ctxA.close();
  await ctxB.close();
  await ctxC.close();
  log('degraded in-game OK, action:', actor);
}

async function rapidReconnectWithLatencyKeepsOnePlayer(browser) {
  const userA = await seed('dnra');
  const userB = await seed('dnrb');
  const ctxA = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxB = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A = await ctxA.newPage();
  const B = await ctxB.newPage();
  attachLoginProbe(A);
  attachLoginProbe(B);

  await login(A, userA.email, 'A-rapid-latency');
  const code = await createPrivateRoom(A);
  await login(B, userB.email, 'B-rapid-latency');
  await joinPrivateRoom(B, code);
  const bBefore = await waitForHostUi(B, false, 8000);
  if (bBefore.controls || bBefore.badge) throw new Error('B deja hote avant reconnexions latencees');

  const cdp = await ctxA.newCDPSession(A);
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: 450,
    downloadThroughput: 48 * 1024,
    uploadThroughput: 24 * 1024,
  });

  for (let i = 0; i < 3; i++) {
    log(`>>> cycle reseau degrade A ${i + 1}/3`);
    await cdp.send('Network.emulateNetworkConditions', {
      offline: true,
      latency: 450,
      downloadThroughput: 48 * 1024,
      uploadThroughput: 24 * 1024,
    });
    await B.waitForTimeout(1200);
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 450,
      downloadThroughput: 48 * 1024,
      uploadThroughput: 24 * 1024,
    });
    await A.waitForTimeout(1800);
    await nudge(A);
    await nudge(B);
  }

  const aHost = await waitForHostUi(A, true, 35000);
  const bHost = await waitForHostUi(B, false, 12000);
  if (!aHost.badge || !aHost.controls || bHost.badge || bHost.controls) {
    throw new Error(`host incoherent apres reconnexion rapide latencee: A=${JSON.stringify(aHost)} B=${JSON.stringify(bHost)}`);
  }
  if (await hasBlockingError(A) || await hasBlockingError(B)) {
    throw new Error('erreur bloquante apres reconnexion rapide avec latence');
  }

  await cdp.detach();
  await ctxA.close();
  await ctxB.close();
  log('degraded rapid reconnect OK');
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    await lobbyHostOfflineDoesNotReturnHost(browser);
    await inGameHostOfflineKeepsGamePlayable(browser);
    await rapidReconnectWithLatencyKeepsOnePlayer(browser);
  } finally {
    await browser.close();
  }
  console.log('\n✅ PREUVE UI réseau dégradé: offline/online hôte en lobby, offline hôte en partie, et reconnexion rapide sous latence restent cohérents');
})().catch((error) => {
  console.error('❌', error.message);
  process.exit(1);
});
