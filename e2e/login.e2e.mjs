// Preuve E2E : Playwright pilote l'app Flutter web (CanvasKit) par sélecteurs
// sémantiques, de bout en bout, contre les émulateurs Firebase.
//
// Le compte de test est pré-créé via l'API serveur (fiable), puis la connexion
// se fait via l'UI (menu → multijoueur → formulaire de connexion → SE CONNECTER).
// Succès = le serveur répond 200 à /api/auth/login-password.
//
// Pré-requis (voir DEV-EMULATORS.md) : émulateurs + serveur (npm run dev:emulators)
// + build web servi avec --dart-define=ENABLE_SEMANTICS=true USE_FIREBASE_EMULATOR=true
// DEV_SERVER_URL=http://localhost:3000.
//
// Config via env : E2E_URL (défaut http://localhost:8081/),
// E2E_SERVER (défaut http://localhost:3000).

import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap } from './flutter-semantics.mjs';

const URL = process.env.E2E_URL || 'http://localhost:8081/';
const SERVER = process.env.E2E_SERVER || 'http://localhost:3000';

async function seedAccount() {
  const id = Date.now().toString().slice(-8);
  const email = `e2e${id}@example.com`;
  const res = await fetch(`${SERVER}/api/auth/register-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: `e2e${id}`, displayName: `E2E ${id}`,
      email, password: 'MotDePasse123',
    }),
  });
  if (res.status !== 201) throw new Error(`seed compte: HTTP ${res.status}`);
  return email;
}

async function run() {
  const email = await seedAccount();
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1400, height: 900 });

  let loginOk = false;
  page.on('response', (r) => {
    if (r.url().includes('/api/auth/login-password') && r.status() === 200) loginOk = true;
  });

  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForTimeout(9000); // démarrage Flutter + montage sémantique

  await openMultiplayerAuth(page);
  await fillField(page, "E-mail ou nom d'utilisateur", email);
  await fillField(page, 'Mot de passe', 'MotDePasse123');
  await tap(page, await boxByText(page, /^SE CONNECTER$/));

  for (let i = 0; i < 12 && !loginOk; i++) await page.waitForTimeout(1000);
  await browser.close();

  if (!loginOk) throw new Error('connexion échouée (pas de login-password 200)');
  console.log(`✅ Connexion E2E réussie via sélecteurs sémantiques (${email})`);
}

run().catch((e) => { console.error('❌', e.message); process.exit(1); });
