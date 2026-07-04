// Mesure des rebuilds par zone (RebuildProbe) avec DEUX vrais clients et du vrai
// trafic socket, contre les émulateurs. Pré-crée 2 comptes via l'API, connecte
// A et B via l'UI, A crée un salon privé, B le rejoint, les deux passent prêts,
// A lance ; puis échantillonne les 4 zones (gametable/roomcode/presence/buttons)
// + screen_body via les logs console `[REBUILD_PROBE]` (build avec ?rebuildprobe=1).
//
// LIMITE (voir DEV-EMULATORS.md / journal) : la table de jeu n'a pas de Semantics
// et le jeu est au tour par tour — il se fige sur le tour d'un humain inactif, et
// les bots n'avancent pas la partie. On atteint donc de façon fiable le DÉMARRAGE
// de partie (mémorisation) mais pas une partie ACTIVE soutenue. Les déclencheurs
// haute fréquence visés par le fix (timer de réaction 30 ms, countdown de présence)
// ne se produisent qu'en jeu actif : ce harnais ne peut pas les exercer, seul le
// test unitaire (fake provider, ticks scriptés) le peut. Ce script sert de socle
// réutilisable pour de futurs tests E2E multi.
//
// Config : E2E_URL (défaut http://localhost:8081/), E2E_SERVER (défaut :3000).
// Prérequis : émulateurs + serveur (npm run dev:emulators) + build web avec
// --dart-define=ENABLE_SEMANTICS=true USE_FIREBASE_EMULATOR=true DEV_SERVER_URL=...

import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap, boxByLabel, waitBox, inputBox } from './flutter-semantics.mjs';

const URL = process.env.E2E_URL || 'http://localhost:8081/';
const SERVER = process.env.E2E_SERVER || 'http://localhost:3000';
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

async function seed() {
  const id = Date.now().toString().slice(-8);
  const email = `rb${id}@example.com`;
  const r = await fetch(`${SERVER}/api/auth/register-password`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: `rb${id}`, displayName: `RB${id}`, email, password: 'MotDePasse123' }),
  });
  if (r.status !== 201) throw new Error('seed HTTP ' + r.status);
  return email;
}

function attach(page) {
  page._probe = [];
  page.on('console', m => { const t = m.text(); if (t.includes('[REBUILD_PROBE]')) { try { page._probe.push(JSON.parse(t.slice(t.indexOf('{')))); } catch {} } });
  page._loginOk = false;
  page.on('response', r => { if (r.url().includes('/api/auth/login-password') && r.status() === 200) page._loginOk = true; });
}
const sample = (page) => page._probe.at(-1) || { screen_body: 0, gametable: 0, roomcode: 0, presence: 0, buttons: 0 };

async function login(page, email, who) {
  for (let a = 1; a <= 6 && !page._loginOk; a++) {
    await page.goto(URL + '?rebuildprobe=1', { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await openMultiplayerAuth(page);
    await fillField(page, "E-mail ou nom d'utilisateur", email);
    await fillField(page, 'Mot de passe', 'MotDePasse123');
    await tap(page, await boxByText(page, /^SE CONNECTER$/));
    for (let i = 0; i < 8 && !page._loginOk; i++) await page.waitForTimeout(1000);
  }
  if (!page._loginOk) throw new Error(who + ' login KO');
  await page.waitForTimeout(2500);
}

async function createRoom(page) {
  await tap(page, await waitBox(page, () => boxByText(page, /Créer un salon/))); await page.waitForTimeout(2000);
  await tap(page, await waitBox(page, () => boxByText(page, /Salon Privé/))); await page.waitForTimeout(2000);
  await tap(page, await waitBox(page, () => boxByText(page, /CRÉER LE SALON/))); await page.waitForTimeout(4000);
  return page.evaluate(() => {
    for (const e of document.querySelectorAll('flt-semantics')) { const t = (e.textContent || '').trim(); if (/^[A-Z0-9]{8}$/.test(t)) return t; }
    return null;
  });
}

async function joinRoom(page, code) {
  await tap(page, await waitBox(page, () => boxByText(page, /Rejoindre un salon/))); await page.waitForTimeout(2500);
  const priv = await boxByText(page, /Salon Privé|privé/i); if (priv) { await tap(page, priv); await page.waitForTimeout(2500); }
  const inp = await inputBoxFirst(page); if (inp) { await page.mouse.click(inp.x, inp.y); await page.waitForTimeout(600); await page.keyboard.insertText(code); await page.waitForTimeout(500); }
  const j = await boxByText(page, /REJOINDRE|Valider/i); if (j) { await tap(page, j); await page.waitForTimeout(4000); }
}
const inputBoxFirst = (page) => page.evaluate(() => { const e = document.querySelector('input'); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });

async function ready(page) { const r = await boxByText(page, /Passer pret|Passer prêt/i); if (r) { await tap(page, r); await page.waitForTimeout(1500); } }

async function launch(page) {
  const l = await boxByText(page, /Lancer|Démarrer/i);
  if (l) { await tap(page, l); await page.waitForTimeout(1800); const c = await boxByText(page, /^Lancer$/i); if (c) await tap(page, c); }
  await page.waitForTimeout(10000);
}
// Mémorisation : clic pixel (table sans sémantique) sur 2 des 4 cartes.
async function pickMemo(page) {
  for (let i = 0; i < 25; i++) { if (await boxByText(page, /CHOISIS 2 CARTES/i)) break; await page.waitForTimeout(700); }
  for (const [x, y] of [[245, 540], [548, 540]]) { await page.mouse.click(x, y); await page.waitForTimeout(500); }
  const ch = await boxByText(page, /CHOISIS 2 CARTES/i); if (ch) await tap(page, ch);
  await page.waitForTimeout(1500);
}

(async () => {
  const emailA = await seed(), emailB = await seed();
  const browser = await chromium.launch({ headless: true });
  const A = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  const B = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  attach(A); attach(B);

  await login(A, emailA, 'A');
  const code = await createRoom(A);
  log('code salon =', code);
  if (!code) throw new Error('pas de code');
  await login(B, emailB, 'B');
  await joinRoom(B, code);
  await ready(B); await ready(A);
  await A.waitForTimeout(2000);
  await launch(A);
  await pickMemo(A); await pickMemo(B);
  await A.waitForTimeout(2000);

  log('=== échantillonnage (20 x 1s) ===');
  for (let i = 1; i <= 20; i++) { await A.waitForTimeout(1000); log(`t+${i}s A:`, JSON.stringify(sample(A)), '| B:', JSON.stringify(sample(B))); }
  log('FINAL A:', JSON.stringify(sample(A)), '| B:', JSON.stringify(sample(B)));
  await browser.close();
})().catch(e => { console.error('❌', e.message); process.exit(1); });
