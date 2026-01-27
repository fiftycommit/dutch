'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"manifest.json": "d4a2352be5752cec10b0c1cecd812c5d",
"index.html": "a873a210cf3e353eb777dd1d60d29894",
"/": "a873a210cf3e353eb777dd1d60d29894",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "067c72c3109027dd953ceb6878f4c41e",
"assets/assets/images/cards/01-carreau.svg": "b7bdf24403b03b407421a37a5e40e59e",
"assets/assets/images/cards/R-pique.svg": "7c6e4d41a5743819f001992db7698fb5",
"assets/assets/images/cards/04-coeur.svg": "21ada87679ed4c6d610f4253a3f0ca6f",
"assets/assets/images/cards/06-trefle.svg": "5e187ecfd710784842275ffe707fd472",
"assets/assets/images/cards/01-coeur.svg": "a1768cd75869021ef0fd6ac3621a4414",
"assets/assets/images/cards/07-carreau.svg": "81c9e24e57fc7d4465daaf0c055dc053",
"assets/assets/images/cards/03-pique.svg": "522fdf611c93a8cb5aa9c81c5bce0c82",
"assets/assets/images/cards/08-carreau.svg": "1b7231515d3f113ab4ed5a6e84b14ddf",
"assets/assets/images/cards/10-carreau.svg": "e440f14b688fe5cb534974800fbd03bf",
"assets/assets/images/cards/D-pique.svg": "6e3c14a14ebe6499ae0aab8af25fe66c",
"assets/assets/images/cards/05-trefle.svg": "c4cb5c9606f59fe793109cc66c1ef428",
"assets/assets/images/cards/10-pique.svg": "456ccd71db15ef49ff078dd5d73241ba",
"assets/assets/images/cards/04-trefle.svg": "bffbfbf8727318b5afdfbb0856f71f9d",
"assets/assets/images/cards/07-pique.svg": "071fe5f20ebee83533181608ef53143e",
"assets/assets/images/cards/R-carreau.svg": "62f20ffbc00710938e11d971c35ff0d7",
"assets/assets/images/cards/05-carreau.svg": "f0a0d69db9826c9ccbf2525c73bd30f2",
"assets/assets/images/cards/V-carreau.svg": "5979f93be68e49d6ce87bf0e636dcd39",
"assets/assets/images/cards/03-coeur.svg": "e9e098181dd3bf9e48cca379b4acc43e",
"assets/assets/images/cards/06-pique.svg": "0d50e5beed265d631525eaf2d572e35e",
"assets/assets/images/cards/V-trefle.svg": "45acad4a6b4f6c6a5570146fa0039f8b",
"assets/assets/images/cards/03-carreau.svg": "4a89d64f7de2da7698656e66a128cf4c",
"assets/assets/images/cards/07-coeur.svg": "570c709b4d9d580fbb0717becc0cc728",
"assets/assets/images/cards/V-pique.svg": "135313050cf5785eb09d864048ebba27",
"assets/assets/images/cards/06-carreau.svg": "2e782b4fcec727d55220203834161c77",
"assets/assets/images/cards/01-trefle.svg": "a369ed7fe13d50c516c362296cf3b36c",
"assets/assets/images/cards/D-carreau.svg": "193c6a42e1f094d0d08a93bf215271f3",
"assets/assets/images/cards/01-pique.svg": "64eafd4c2c6c938a2312d13686faff73",
"assets/assets/images/cards/02-pique.svg": "eb8c9d47ede2b7a126742db16b1c8a61",
"assets/assets/images/cards/joker-rouge.svg": "8be85f86ba8062085227d822873f0133",
"assets/assets/images/cards/07-trefle.svg": "1a8bfecb4f6950e6422fac7a1e5adc7a",
"assets/assets/images/cards/10-trefle.svg": "71f57bf46628a88cc4c7860a4072e2ff",
"assets/assets/images/cards/09-carreau.svg": "841d56bd9037540795915f89ebfd3982",
"assets/assets/images/cards/03-trefle.svg": "79f75a9005810d6b15e3c35fbcda6f53",
"assets/assets/images/cards/R-trefle.svg": "aedf6f8167ff9f629d7c10716510cc58",
"assets/assets/images/cards/02-carreau.svg": "c2080abc662e69c642d830ef7565a91a",
"assets/assets/images/cards/08-coeur.svg": "979976ed658b85fd671de79202dda8ea",
"assets/assets/images/cards/R-coeur.svg": "72f4bfd2c16212692062f753e2b4e609",
"assets/assets/images/cards/09-pique.svg": "ab261510f3b68f7dc72b865ec1dc5f8e",
"assets/assets/images/cards/dos-bleu.svg": "ce694455a515c5c0064f2f8d303a9858",
"assets/assets/images/cards/08-trefle.svg": "1cf27ceacb63e512d8f74085f8bfd5c4",
"assets/assets/images/cards/09-coeur.svg": "6f1dca874555a64d3b3d8ddd91c9259e",
"assets/assets/images/cards/05-pique.svg": "5bc74cfa91e72c8d3138aed585a83a8d",
"assets/assets/images/cards/V-coeur.svg": "7fe868208722b33c0ca8b852a13cf8aa",
"assets/assets/images/cards/05-coeur.svg": "3820721afc7a857b08a7336f7b50f255",
"assets/assets/images/cards/04-pique.svg": "37de1dfcaa7c8b189ed5ce22f70b1fec",
"assets/assets/images/cards/02-trefle.svg": "c816c2c294f9c4988cdfc338cc5a9ef3",
"assets/assets/images/cards/D-coeur.svg": "b79de1978d37de41770d86a09836eea4",
"assets/assets/images/cards/D-trefle.svg": "4a7c78b7cbf7613704b08359bbe82130",
"assets/assets/images/cards/08-pique.svg": "bd8e5ac8882cae19680ee0b14cea1e54",
"assets/assets/images/cards/back.svg": "03a190b7f9a1af8017555aa1054752d0",
"assets/assets/images/cards/04-carreau.svg": "d10028864a9adcb5c8b2d890357ee812",
"assets/assets/images/cards/06-coeur.svg": "31f328bccb2e69742a4cb1f5705805bc",
"assets/assets/images/cards/02-coeur.svg": "0861d63be092fb712958b3d76e0a30b0",
"assets/assets/images/cards/09-trefle.svg": "dcc5f4874cb97ca5802c6e4591edce3c",
"assets/assets/images/cards/joker-noir.svg": "44c5c08d6428bdb39dc20f0227e05781",
"assets/assets/images/cards/10-coeur.svg": "3883b6fe74f0e88fc882722700c4e173",
"assets/fonts/MaterialIcons-Regular.otf": "19370dcd5bad0ff0793f466b85d7e4ad",
"assets/NOTICES": "c0480021a7ca35c0986b871c74975614",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin": "b3c296989d07e983c0bc995c6a141ddd",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter_bootstrap.js": "c9dba2935018711112f86764671fc814",
"version.json": "7bf9a2beddd340869244059b9a3d8466",
"main.dart.js": "f5ee7503d1c10d479d61a65655123897"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
