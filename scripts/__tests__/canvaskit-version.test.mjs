import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const generator = fileURLToPath(new URL('../generate-pwa-service-worker.mjs', import.meta.url));

function build(js, wasm, { wasmEntrypoint = false } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-renderer-'));
  try {
    mkdirSync(path.join(dir, 'canvaskit/chromium'), { recursive: true });
    writeFileSync(path.join(dir, 'index.html'), 'app');
    writeFileSync(path.join(dir, 'flutter_bootstrap.js'), 'canvasKitBaseUrl: "/canvaskit/"');
    writeFileSync(path.join(dir, 'canvaskit/chromium/canvaskit.js'), js);
    writeFileSync(path.join(dir, 'canvaskit/chromium/canvaskit.wasm'), wasm);
    writeFileSync(path.join(dir, 'canvaskit/canvaskit.wasm'), 'full');
    writeFileSync(path.join(dir, 'canvaskit/skwasm.wasm'), 'skwasm');
    writeFileSync(path.join(dir, 'canvaskit/skwasm_heavy.wasm'), 'heavy');
    writeFileSync(path.join(dir, 'canvaskit/wimp.js'), 'wimp');
    if (wasmEntrypoint) writeFileSync(path.join(dir, 'main.dart.wasm'), 'app wasm');
    execFileSync('node', [generator, dir]);
    const bootstrap = readFileSync(path.join(dir, 'flutter_bootstrap.js'), 'utf8');
    const base = bootstrap.match(/canvasKitBaseUrl: "(.*?)"/)[1];
    assert.match(base, /^\/canvaskit-[a-f0-9]{16}\/$/);
    assert.equal(readFileSync(path.join(dir, base.slice(1), 'chromium/canvaskit.js'), 'utf8'), js);
    assert.equal(readFileSync(path.join(dir, base.slice(1), 'chromium/canvaskit.wasm'), 'utf8'), wasm);
    const worker = readFileSync(path.join(dir, 'dutch_service_worker.js'), 'utf8');
    assert.ok(worker.includes(base + 'chromium/canvaskit.wasm'));
    assert.ok(worker.includes(base + 'canvaskit.wasm'));
    for (const file of ['skwasm.wasm', 'skwasm_heavy.wasm', 'wimp.js']) {
      assert.equal(worker.includes(base + file), wasmEntrypoint);
    }
    execFileSync('node', [generator, dir]);
    assert.equal(readFileSync(path.join(dir, 'flutter_bootstrap.js'), 'utf8'), bootstrap);
    // Flutter can regenerate the unversioned directory without cleaning the
    // versioned output from a preceding build.
    mkdirSync(path.join(dir, 'canvaskit/chromium'), { recursive: true });
    writeFileSync(path.join(dir, 'canvaskit/chromium/canvaskit.js'), js);
    writeFileSync(path.join(dir, 'canvaskit/chromium/canvaskit.wasm'), wasm);
    writeFileSync(path.join(dir, 'canvaskit/canvaskit.wasm'), 'full');
    writeFileSync(path.join(dir, 'canvaskit/skwasm.wasm'), 'skwasm');
    writeFileSync(path.join(dir, 'canvaskit/skwasm_heavy.wasm'), 'heavy');
    writeFileSync(path.join(dir, 'canvaskit/wimp.js'), 'wimp');
    writeFileSync(path.join(dir, 'flutter_bootstrap.js'), 'canvasKitBaseUrl: "/canvaskit/"');
    execFileSync('node', [generator, dir]);
    assert.equal(readFileSync(path.join(dir, 'flutter_bootstrap.js'), 'utf8'), bootstrap);
    return base;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('CanvasKit URLs change when either JS or WASM changes and remain stable otherwise', () => {
  const base = build('js1', 'wasm1');
  assert.equal(base, build('js1', 'wasm1'));
  assert.notEqual(base, build('js2', 'wasm1'));
  assert.notEqual(base, build('js1', 'wasm2'));
});

test('Wasm builds keep their renderer variants available offline', () => {
  build('js', 'wasm', { wasmEntrypoint: true });
});
