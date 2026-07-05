// Preuve UI: quand le createur revient apres transfert d'hote, il ne reprend pas
// automatiquement l'hote. B doit garder le badge Hote et les controles.
import { chromium } from 'playwright';
import {
  attachLoginProbe,
  createPrivateRoom,
  hasHostControls,
  isSelfHost,
  joinPrivateRoom,
  login,
  log,
  seed,
  waitForHostUi,
} from './multiplayer-flow.mjs';

(async () => {
  const userA = await seed('crA');
  const userB = await seed('crB');
  const browser = await chromium.launch({ headless: true });
  const ctxA = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const ctxB = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A = await ctxA.newPage();
  const B = await ctxB.newPage();
  attachLoginProbe(A);
  attachLoginProbe(B);

  await login(A, userA.email, 'A');
  const code = await createPrivateRoom(A);
  await login(B, userB.email, 'B');
  await joinPrivateRoom(B, code);

  const bBefore = {
    controls: await hasHostControls(B),
    badge: await isSelfHost(B),
  };
  log('AVANT depart A -- B controles:', bBefore.controls, 'badge:', bBefore.badge);
  if (bBefore.controls || bBefore.badge) throw new Error('B est deja hote avant le depart de A');

  await ctxA.close();
  const bAfterTransfer = await waitForHostUi(B, true);
  log('APRES depart A -- B controles:', bAfterTransfer.controls, 'badge:', bAfterTransfer.badge);
  if (!bAfterTransfer.controls || !bAfterTransfer.badge) {
    throw new Error('B ne devient pas hote apres depart de A');
  }

  const ctxA2 = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const A2 = await ctxA2.newPage();
  attachLoginProbe(A2);
  await login(A2, userA.email, 'A-retour');
  await joinPrivateRoom(A2, code);

  const bFinal = await waitForHostUi(B, true);
  const aFinal = await waitForHostUi(A2, false);
  log('RETOUR A -- B controles:', bFinal.controls, 'badge:', bFinal.badge);
  log('RETOUR A -- A controles:', aFinal.controls, 'badge:', aFinal.badge);

  const ok = bFinal.controls && bFinal.badge && !aFinal.controls && !aFinal.badge;
  await browser.close();
  console.log(ok
    ? '\n✅ PREUVE UI: le createur revenu ne reprend pas l hote; B reste seul hote visible'
    : '\n❌ le createur reprend l hote ou un double hote est visible');
  process.exit(ok ? 0 : 1);
})().catch((error) => {
  console.error('❌', error.message);
  process.exit(1);
});
