// Preuve UI: l'hote quitte pendant une partie active. Les clients restants
// gardent une table jouable et aucun double badge hote visible.
import { chromium } from 'playwright';
import {
  attachLoginProbe,
  createPrivateRoom,
  hasBlockingError,
  hasGameTable,
  isSelfHost,
  joinPrivateRoom,
  login,
  log,
  memorize,
  nudge,
  playOneVisibleTurn,
  seed,
  semanticTexts,
  setReadyAndStart,
} from './multiplayer-flow.mjs';

(async () => {
  const [userA, userB, userC] = await Promise.all([seed('hgA'), seed('hgB'), seed('hgC')]);
  const browser = await chromium.launch({ headless: true });
  const ctxA = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxB = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxC = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A = await ctxA.newPage();
  const B = await ctxB.newPage();
  const C = await ctxC.newPage();
  [A, B, C].forEach(attachLoginProbe);

  await login(A, userA.email, 'A');
  const code = await createPrivateRoom(A);
  await login(B, userB.email, 'B');
  await joinPrivateRoom(B, code);
  await login(C, userC.email, 'C');
  await joinPrivateRoom(C, code);

  await setReadyAndStart(A, [B, C]);
  await memorize(A);
  await memorize(B);
  await memorize(C);
  let tableBefore = false;
  for (let i = 0; i < 40; i++) {
    await B.waitForTimeout(1000);
    await nudge(B);
    await nudge(C);
    tableBefore = (await hasGameTable(B)) && (await hasGameTable(C));
    if (tableBefore) break;
  }
  if (!tableBefore) {
    log('TEXTES B avant depart:', JSON.stringify(await semanticTexts(B)));
    log('TEXTES C avant depart:', JSON.stringify(await semanticTexts(C)));
    throw new Error('table de jeu absente avant depart hote');
  }

  log('>>> A hote quitte pendant la partie');
  await ctxA.close();

  let bTable = false;
  let cTable = false;
  let bError = true;
  let cError = true;
  for (let i = 0; i < 25; i++) {
    await B.waitForTimeout(1000);
    await nudge(B);
    await nudge(C);
    bTable = await hasGameTable(B);
    cTable = await hasGameTable(C);
    bError = await hasBlockingError(B);
    cError = await hasBlockingError(C);
    if (bTable && cTable && !bError && !cError) break;
  }
  log('APRES depart A -- table B:', bTable, 'table C:', cTable, 'erreur B:', bError, 'erreur C:', cError);

  const bHost = await isSelfHost(B);
  const cHost = await isSelfHost(C);
  log('badges hote visibles en partie -- B:', bHost, 'C:', cHost);
  if (bHost && cHost) throw new Error('double badge hote visible apres depart hote');

  const actor = await playOneVisibleTurn([
    { page: B, name: 'B' },
    { page: C, name: 'C' },
  ]);
  log('action apres depart hote par:', actor);

  const ok = bTable && cTable && !bError && !cError && actor !== null;
  await browser.close();
  console.log(ok
    ? '\n✅ PREUVE UI: apres depart de l hote en partie, la table reste stable et une action joueur passe'
    : '\n❌ depart hote en partie: table bloquee, erreur UI ou aucune action possible');
  process.exit(ok ? 0 : 1);
})().catch((error) => {
  console.error('❌', error.message);
  process.exit(1);
});
