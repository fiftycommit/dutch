import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const generator = fileURLToPath(new URL('../generate-pwa-service-worker.mjs', import.meta.url));
const bootstrapFile = fileURLToPath(new URL('../../web/flutter_bootstrap.js', import.meta.url));

test('an existing controlled tab reloads once when the worker changes', () => {
  const source = readFileSync(bootstrapFile, 'utf8')
    .replace('{{flutter_js}}', '')
    .replace('{{flutter_build_config}}', '')
    .replace('{{flutter_service_worker_version}}', '123');
  let controllerChange;
  let reloads = 0;
  const storage = new Map();
  const serviceWorker = {
    controller: {},
    addEventListener: (type, listener) => {
      if (type === 'controllerchange') controllerChange = listener;
    },
  };
  vm.runInNewContext(source, {
    navigator: { serviceWorker },
    window: { location: { reload: () => { reloads++; } } },
    sessionStorage: {
      getItem: (key) => storage.get(key),
      setItem: (key, value) => storage.set(key, value),
    },
    _flutter: { loader: { load() {} } },
  });
  controllerChange();
  controllerChange();
  assert.equal(reloads, 1);
});

test('worker does not activate with missing core resources', async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-sw-install-'));
  try {
    writeFileSync(path.join(dir, 'index.html'), 'app');
    writeFileSync(path.join(dir, 'main.dart.js'), 'main');
    execFileSync('node', [generator, dir]);
    const source = readFileSync(path.join(dir, 'dutch_service_worker.js'), 'utf8');
    let install;
    let skipped = false;
    const self = {
      addEventListener: (type, listener) => { if (type === 'install') install = listener; },
      skipWaiting: async () => { skipped = true; },
    };
    const caches = {
      open: async () => ({
        add: async (request) => {
          if (request.url === '/main.dart.js') throw new Error('offline');
        },
      }),
    };
    class Request {
      constructor(url, options) { this.url = url; this.cache = options.cache; }
    }
    vm.runInNewContext(source, { self, caches, Request });
    let completion;
    install({ waitUntil: (promise) => { completion = promise; } });
    await assert.rejects(completion, /offline/);
    assert.equal(skipped, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
