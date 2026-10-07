#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const buildDir = path.resolve(process.argv[2] || 'build/web');
const outputFile = path.join(buildDir, 'dutch_service_worker.js');

const excludedFiles = new Set([
  'flutter_service_worker.js',
  'dutch_service_worker.js',
]);

const excludedExtensions = new Set([
  '.map',
]);

async function listFiles(dir, prefix = '') {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const relativePath = path.posix.join(prefix, entry.name);
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      files.push(...await listFiles(fullPath, relativePath));
      continue;
    }

    if (!entry.isFile()) {
      continue;
    }

    if (entry.name.startsWith('.') ||
        excludedFiles.has(entry.name) ||
        excludedExtensions.has(path.extname(entry.name))) {
      continue;
    }

    files.push(relativePath);
  }

  return files;
}

function toResourcePath(file) {
  return `/${file}`;
}

async function buildVersion(files) {
  const hash = createHash('sha256');

  for (const file of files) {
    const fullPath = path.join(buildDir, file);
    const fileStat = await stat(fullPath);
    hash.update(file);
    hash.update(String(fileStat.size));

    if (fileStat.size <= 1024 * 1024) {
      hash.update(await readFile(fullPath));
    }
  }

  return hash.digest('hex').slice(0, 16);
}

// Deferred screens must match main.dart.js, even when a CDN/browser cached
// the old chunk at its unversioned URL.
const deferredFiles = (await listFiles(buildDir)).filter(file => /^main\.dart\.js_\d+\.part\.js$/.test(file));
if (deferredFiles.length > 0) {
  const mainPath = path.join(buildDir, 'main.dart.js');
  let main = await readFile(mainPath, 'utf8');
  for (const file of deferredFiles) {
    const content = await readFile(path.join(buildDir, file));
    const hash = createHash('sha256').update(content).digest('hex').slice(0, 16);
    const versioned = file.replace('.part.js', `.${hash}.part.js`);
    if (!main.includes(`"${file}"`)) throw new Error(`Missing deferred reference: ${file}`);
    main = main.replaceAll(`"${file}"`, `"${versioned}"`);
    await rename(path.join(buildDir, file), path.join(buildDir, versioned));
  }
  await writeFile(mainPath, main);
}

// CanvasKit JS and WASM must always come from the same Flutter build.
// Their original URLs can remain cached for a year by browsers/CDNs.
const canvasKitFiles = (await listFiles(buildDir)).filter(file => file.startsWith('canvaskit/')).sort();
if (canvasKitFiles.length > 0) {
  const rendererHash = createHash('sha256');
  for (const file of canvasKitFiles) {
    rendererHash.update(file);
    rendererHash.update(await readFile(path.join(buildDir, file)));
  }
  const rendererDir = `canvaskit-${rendererHash.digest('hex').slice(0, 16)}`;
  const bootstrapPath = path.join(buildDir, 'flutter_bootstrap.js');
  const bootstrap = await readFile(bootstrapPath, 'utf8');
  if (!bootstrap.includes('canvasKitBaseUrl: "/canvaskit/"')) {
    throw new Error('Missing CanvasKit base URL in Flutter bootstrap');
  }
  try {
    await rename(path.join(buildDir, 'canvaskit'), path.join(buildDir, rendererDir));
  } catch (error) {
    if (error.code !== 'ENOTEMPTY' && error.code !== 'EEXIST') throw error;
    // An incremental Flutter build recreated an identical renderer. Its
    // content-addressed destination already exists from the previous build.
    await rm(path.join(buildDir, 'canvaskit'), { recursive: true });
  }
  await writeFile(bootstrapPath, bootstrap.replace(
    'canvasKitBaseUrl: "/canvaskit/"', `canvasKitBaseUrl: "/${rendererDir}/"`,
  ));
}

const files = (await listFiles(buildDir)).sort();
const version = await buildVersion(files);
const resources = Array.from(new Set([
  '/',
  ...files.map(toResourcePath),
])).sort();

const serviceWorker = `'use strict';

const CACHE_PREFIX = 'dutch78-static-';
const CACHE_NAME = 'dutch78-static-${version}';
const RESOURCES = new Set(${JSON.stringify(resources, null, 2)});
const CORE = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/manifest.json',
  '/assets/AssetManifest.bin',
  '/assets/AssetManifest.bin.json',
  '/assets/FontManifest.json'
].filter((resource) => RESOURCES.has(resource));
const NETWORK_ONLY_PREFIXES = [
  // Handler Firebase Auth (popup Google) proxifié par nginx : jamais l'index SPA.
  '/__/',
  '/api/',
  '/socket.io/',
  '/health',
  '/rooms',
  '/public-rooms',
  '/room',
  '/friends',
  '/chat',
  '/sbmm',
  '/bot-learning',
  '/player-learning',
  '/notifications'
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cacheResources(cache, CORE);
    await cacheResources(cache, Array.from(RESOURCES));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames
      .filter((cacheName) => cacheName.startsWith(CACHE_PREFIX) && cacheName !== CACHE_NAME)
      .map((cacheName) => caches.delete(cacheName)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  if (request.method !== 'GET') {
    return;
  }

  const url = new URL(request.url);
  if (url.origin !== self.location.origin || shouldUseNetworkOnly(url)) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(cacheFirst('/index.html', request));
    return;
  }

  const resourcePath = normalizeResourcePath(url);
  if (RESOURCES.has(resourcePath)) {
    event.respondWith(cacheFirst(resourcePath, request));
  }
});

async function cacheResources(cache, resources) {
  const uniqueResources = Array.from(new Set(resources));
  for (let index = 0; index < uniqueResources.length; index += 20) {
    const chunk = uniqueResources.slice(index, index + 20);
    await Promise.all(chunk.map(async (resource) => {
      try {
        await cache.add(resource);
      } catch (_) {
        // Keep install resilient if an optional generated resource disappears between builds.
      }
    }));
  }
}

async function cacheFirst(resourcePath, request) {
  const cache = await caches.open(CACHE_NAME);
  const cachedResponse = await cache.match(resourcePath);

  if (cachedResponse) {
    return cachedResponse;
  }

  const response = await fetch(request);
  if (response && response.ok) {
    await cache.put(resourcePath, response.clone());
  }
  return response;
}

function normalizeResourcePath(url) {
  let pathname = url.pathname;
  if (pathname === '/') {
    return '/';
  }
  return pathname;
}

function shouldUseNetworkOnly(url) {
  return NETWORK_ONLY_PREFIXES.some((prefix) => url.pathname.startsWith(prefix));
}
`;

await writeFile(outputFile, serviceWorker);
console.log(`Generated ${outputFile} with ${resources.length} cached resources (dutch78-static-${version})`);
