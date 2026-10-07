import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const generator = fileURLToPath(new URL('../generate-pwa-service-worker.mjs', import.meta.url));

test('Deferred screen references and cached resources use versioned chunk URLs', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-deferred-'));
  try {
    writeFileSync(path.join(dir, 'index.html'), 'app');
    writeFileSync(path.join(dir, 'main.dart.js'), 'deferredPartUris:["main.dart.js_1.part.js"]');
    writeFileSync(path.join(dir, 'main.dart.js_1.part.js'), 'screen version 1');
    execFileSync('node', [generator, dir]);
    const main = readFileSync(path.join(dir, 'main.dart.js'), 'utf8');
    const file = main.match(/"(.*?)"/)[1];
    assert.match(file, /^main\.dart\.js_1\.[a-f0-9]{16}\.part\.js$/);
    assert.equal(readFileSync(path.join(dir, file), 'utf8'), 'screen version 1');
    assert.ok(readFileSync(path.join(dir, 'dutch_service_worker.js'), 'utf8').includes('/' + file));
    execFileSync('node', [generator, dir]);
    assert.equal(readFileSync(path.join(dir, 'main.dart.js'), 'utf8'), main);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
