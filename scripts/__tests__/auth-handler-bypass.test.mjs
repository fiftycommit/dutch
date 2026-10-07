// Régression bug "connexion Google → Page non trouvée" : authDomain = dutch-game.me,
// donc la popup Google s'ouvre sur /__/auth/handler (proxifié par nginx vers Firebase).
// Si le service worker répond à cette navigation avec index.html, Flutter affiche
// sa 404 avec le fragment #fac=<jeton App Check> et la connexion n'aboutit jamais.
//
// Pas de navigateur : on exécute le vrai générateur puis le SW produit dans un vm.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const generator = path.resolve(here, '..', 'generate-pwa-service-worker.mjs');
const devWorker = path.resolve(here, '..', '..', 'web', 'dutch_service_worker.js');
const origin = 'https://dutch-game.me';

function generatedWorkerSource() {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-swauth-'));
  try {
    mkdirSync(path.join(dir, 'assets'), { recursive: true });
    writeFileSync(path.join(dir, 'index.html'), '<!doctype html><title>t</title>');
    writeFileSync(path.join(dir, 'main.dart.js'), '// app');
    writeFileSync(path.join(dir, 'assets', 'FontManifest.json'), '[]');
    execFileSync('node', [generator, dir], { stdio: 'pipe' });
    return readFileSync(path.join(dir, 'dutch_service_worker.js'), 'utf8');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Charge le SW et renvoie son handler `fetch`. */
function loadFetchHandler(source) {
  const listeners = {};
  const self = {
    location: { origin },
    addEventListener: (type, fn) => { listeners[type] = fn; },
  };
  vm.runInNewContext(source, { self, URL, caches: {}, fetch: () => {} });
  assert.ok(listeners.fetch, 'handler fetch introuvable dans le service worker');
  return listeners.fetch;
}

/** true si le SW intercepte la navigation vers `pathname`. */
function interceptsNavigation(fetchHandler, pathname) {
  let intercepted = false;
  fetchHandler({
    request: { method: 'GET', mode: 'navigate', url: `${origin}${pathname}` },
    respondWith: (response) => {
      intercepted = true;
      Promise.resolve(response).catch(() => {}); // caches est un faux vide ici
    },
  });
  return intercepted;
}

for (const [label, source] of [
  ['généré (prod)', () => generatedWorkerSource()],
  ['web/ (dev)', () => readFileSync(devWorker, 'utf8')],
]) {
  test(`SW ${label} laisse passer le handler Firebase Auth`, () => {
    const onFetch = loadFetchHandler(source());
    const handler = '/__/auth/handler?apiKey=k&authType=signInViaPopup#fac=jeton';
    assert.equal(interceptsNavigation(onFetch, handler), false);
    assert.equal(interceptsNavigation(onFetch, '/__/auth/iframe'), false);
  });

  test(`SW ${label} sert toujours l'index SPA pour les routes de l'app`, () => {
    const onFetch = loadFetchHandler(source());
    assert.equal(interceptsNavigation(onFetch, '/profil'), true);
  });
}
