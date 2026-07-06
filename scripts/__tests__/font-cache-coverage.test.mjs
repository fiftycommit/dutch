// Régression bug "texte invisible hors-ligne" : chaque police déclarée dans
// FontManifest.json doit se retrouver dans les RESOURCES du service worker généré
// par generate-pwa-service-worker.mjs. Si une police est déclarée mais absente du
// build (donc non cachée), l'écran qui l'utilise perd son texte hors-ligne.
//
// Pas de navigateur : on exécute le vrai générateur sur un build factice.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const generator = path.resolve(here, '..', 'generate-pwa-service-worker.mjs');

/** Flutter web sert un asset de FontManifest sous le préfixe `assets/`. */
function servedPath(asset) {
  return `/assets/${asset}`;
}

function fontAssets(manifest) {
  return manifest.flatMap((family) =>
    (family.fonts || [])
      .map((f) => f.asset)
      .filter((a) => typeof a === 'string'));
}

/** Crée un build factice, écrit FontManifest + fichiers de police présents. */
function makeBuild({ manifest, presentAssets }) {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-swfont-'));
  mkdirSync(path.join(dir, 'assets'), { recursive: true });
  writeFileSync(path.join(dir, 'index.html'), '<!doctype html><title>t</title>');
  writeFileSync(path.join(dir, 'main.dart.js'), '// app');
  writeFileSync(
    path.join(dir, 'assets', 'FontManifest.json'),
    JSON.stringify(manifest));
  // Les fichiers de police réellement copiés dans le build sont sous
  // `assets/<assetKey>` (double `assets/` pour les polices projet).
  for (const asset of presentAssets) {
    const full = path.join(dir, 'assets', asset);
    mkdirSync(path.dirname(full), { recursive: true });
    writeFileSync(full, 'FONTDATA');
  }
  return dir;
}

/** Exécute le générateur et renvoie l'ensemble RESOURCES du SW produit. */
function generatedResources(buildDir) {
  execFileSync('node', [generator, buildDir], { stdio: 'pipe' });
  const sw = readFileSync(path.join(buildDir, 'dutch_service_worker.js'), 'utf8');
  const match = sw.match(/const RESOURCES = new Set\((\[[\s\S]*?\])\);/);
  assert.ok(match, 'RESOURCES introuvable dans le service worker généré');
  return new Set(JSON.parse(match[1]));
}

/** Polices déclarées mais absentes des RESOURCES (le bug qu'on veut attraper). */
function uncachedFonts(manifest, resources) {
  return fontAssets(manifest).filter((a) => !resources.has(servedPath(a)));
}

const sampleManifest = [
  { family: 'Roboto', fonts: [
    { asset: 'assets/fonts/Roboto-Regular.ttf' },
    { asset: 'assets/fonts/Roboto-Bold.ttf' },
  ] },
  { family: 'MaterialIcons', fonts: [
    { asset: 'fonts/MaterialIcons-Regular.otf' },
  ] },
];

test('toutes les polices de FontManifest sont dans le cache du SW', () => {
  const dir = makeBuild({
    manifest: sampleManifest,
    presentAssets: fontAssets(sampleManifest),
  });
  try {
    const resources = generatedResources(dir);
    const missing = uncachedFonts(sampleManifest, resources);
    assert.deepEqual(missing, [],
      `Polices déclarées mais non cachées hors-ligne: ${missing.join(', ')}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Test du test : si une police déclarée est absente du build, la vérification
// doit la signaler (sinon le test de régression ne protège rien).
test('détecte une police déclarée mais absente du build', () => {
  const present = fontAssets(sampleManifest).filter(
    (a) => a !== 'assets/fonts/Roboto-Bold.ttf');
  const dir = makeBuild({ manifest: sampleManifest, presentAssets: present });
  try {
    const resources = generatedResources(dir);
    const missing = uncachedFonts(sampleManifest, resources);
    assert.deepEqual(missing, ['assets/fonts/Roboto-Bold.ttf'],
      'la vérification aurait dû repérer la police manquante');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
