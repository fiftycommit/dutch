'use strict';

const CACHE_PREFIX = 'dutch78-static-dev-';
const CACHE_NAME = `${CACHE_PREFIX}fallback`;
const RESOURCES = new Set([
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/manifest.json',
  '/assets/AssetManifest.bin',
  '/assets/AssetManifest.bin.json',
  '/assets/FontManifest.json'
]);
const NETWORK_ONLY_PREFIXES = [
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
  await Promise.all(resources.map(async (resource) => {
    try {
      await cache.add(resource);
    } catch (_) {
      // Local fallback only; production builds generate the full static resource list.
    }
  }));
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
  return url.pathname === '/' ? '/' : url.pathname;
}

function shouldUseNetworkOnly(url) {
  return NETWORK_ONLY_PREFIXES.some((prefix) => url.pathname.startsWith(prefix));
}
