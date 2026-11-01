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
  const storage = new Map([['dutch_sw_reloaded_version', '123']]);
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
      keys: async () => [],
      open: async () => ({ put: async () => {} }),
    };
    class Request {
      constructor(url, options) { this.url = url; this.cache = options.cache; }
    }
    vm.runInNewContext(source, {
      self, caches, Request,
      fetch: async (request) => {
        if (request.url.startsWith('/main.dart.js?')) throw new Error('offline');
        return { ok: true };
      },
    });
    let completion;
    install({ waitUntil: (promise) => { completion = promise; } });
    await assert.rejects(completion, /offline/);
    assert.equal(skipped, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('worker reuses unchanged cached resources and fetches changed or missing ones', async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'dutch-sw-reuse-'));
  try {
    writeFileSync(path.join(dir, 'index.html'), 'app');
    writeFileSync(path.join(dir, 'main.dart.js'), 'new main');
    writeFileSync(path.join(dir, 'manifest.json'), 'manifest');
    execFileSync('node', [generator, dir]);
    const source = readFileSync(path.join(dir, 'dutch_service_worker.js'), 'utf8');
    const hashes = JSON.parse(source.match(/const HASHES = (.*);/)[1]);
    let install;
    let skipped = false;
    const fetched = [];
    const copied = [];
    const previous = {
      match: async (key) => {
        if (key === '/__dutch_static_manifest__') {
          return { json: async () => ({ ...hashes, '/main.dart.js': 'old hash' }) };
        }
        if (key === '/manifest.json') return undefined;
        return { key };
      },
    };
    const current = {
      put: async (key) => { copied.push(key); },
    };
    const caches = {
      keys: async () => ['dutch78-static-previous'],
      open: async (name) => name === 'dutch78-static-previous' ? previous : current,
    };
    class Request {
      constructor(url, options) { this.url = url; this.cache = options.cache; }
    }
    class Response {
      constructor(body) { this.body = body; }
    }
    vm.runInNewContext(source, {
      caches, Request, Response,
      fetch: async (request) => {
        fetched.push(request.url.split('?')[0]);
        return { ok: true };
      },
      self: {
        addEventListener: (type, listener) => { if (type === 'install') install = listener; },
        skipWaiting: async () => { skipped = true; },
      },
    });
    let completion;
    install({ waitUntil: (promise) => { completion = promise; } });
    await completion;
    assert.deepEqual(fetched.sort(), ['/main.dart.js', '/manifest.json']);
    assert.ok(copied.includes('/index.html'));
    assert.ok(copied.includes('/__dutch_static_manifest__'));
    assert.equal(skipped, true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
