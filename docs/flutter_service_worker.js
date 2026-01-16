'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "7ef27ad3205ba25fd0a35d9d38ae2b74",
"version.json": "7bf9a2beddd340869244059b9a3d8466",
"index.html": "a873a210cf3e353eb777dd1d60d29894",
"/": "a873a210cf3e353eb777dd1d60d29894",
"main.dart.js": "6d8896ee64885de697da625e3095cd91",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "d4a2352be5752cec10b0c1cecd812c5d",
"assets/NOTICES": "c08be01bbeb104eec091d31a1c078cca",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "65d6828b648ba2c71d0682ec536bd32e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "f6a248c47c3893fb5ff4af0aa27f5fff",
"assets/fonts/MaterialIcons-Regular.otf": "f9f0a2a7c5c61a37c56b5d3c86f3db95",
"assets/assets/images/cards/V-coeur.svg": "a96bab9ebb34d5bf20c6fa4625b3918a",
"assets/assets/images/cards/10-trefle.svg": "9098514d3c3755501eba4f6cadc35ff0",
"assets/assets/images/cards/10-coeur.svg": "b495af1ec82348665b23cb32e5881999",
"assets/assets/images/cards/04-coeur.svg": "e1ee2351c742f7b0685989192760dd16",
"assets/assets/images/cards/05-pique.svg": "c79de7d22c428ded4b36331b01441c7a",
"assets/assets/images/cards/01-trefle.svg": "8cfaaa8aaace691fe057740ce7c9f778",
"assets/assets/images/cards/06-carreau.svg": "1034187be1d9604ede9320a68af72d87",
"assets/assets/images/cards/08-pique.svg": "ee506cccb49f3ea2c67f76ae32f746de",
"assets/assets/images/cards/09-coeur.svg": "0cfc252dae7f3bf77cbbae0f9b1bd67d",
"assets/assets/images/cards/04-trefle.svg": "3c88116f42c96de10fd5fcf552163f30",
"assets/assets/images/cards/03-pique.svg": "e49863f82db2b14f8aaba24652762e04",
"assets/assets/images/cards/02-coeur.svg": "e8152727965ab15844366028a8d41f10",
"assets/assets/images/cards/D-pique.svg": "a5accb2053835ac27d13d4d7ca1f27f8",
"assets/assets/images/cards/03-carreau.svg": "5b4c3da3afe864539079f2dcb007bfcd",
"assets/assets/images/cards/09-trefle.svg": "02615682a351b400c334068cbd3ea40e",
"assets/assets/images/cards/V-trefle.svg": "09b84e1d32888e61fb8209f5c8157d8d",
"assets/assets/images/cards/V-carreau.svg": "e6ae1891499125517cacbad057d6ad5b",
"assets/assets/images/cards/V-pique.svg": "3333c796c8f67156d78d44dbff430c71",
"assets/assets/images/cards/09-carreau.svg": "be24282d00edaec52630bb202a9be720",
"assets/assets/images/cards/04-pique.svg": "6cc6524b424b374a89c1c82dcdb318cf",
"assets/assets/images/cards/05-coeur.svg": "6e4306942de4d16a38090f9785817f45",
"assets/assets/images/cards/10-pique.svg": "ab8c4c47b92529644f5237d00e128dea",
"assets/assets/images/cards/08-coeur.svg": "ecbcabefad1c0b4369d4d965537f49c5",
"assets/assets/images/cards/09-pique.svg": "1e14ef6ac4e5c5eac40d79285aa99479",
"assets/assets/images/cards/03-trefle.svg": "35c36426e35d716e77448f703c3c756a",
"assets/assets/images/cards/03-coeur.svg": "14d3fb0a20984b33b1099403d92efbde",
"assets/assets/images/cards/02-pique.svg": "696155026c19a79fbd43de1ae4b17a5b",
"assets/assets/images/cards/05-carreau.svg": "a27b27bd395592d3c3ce6e3f7125842e",
"assets/assets/images/cards/D-coeur.svg": "f6a4a7cd23980e25f1c9f5e184316a67",
"assets/assets/images/cards/06-trefle.svg": "4b920aa6f9f9d71aa0d40247187cccca",
"assets/assets/images/cards/10-carreau.svg": "a56f1a10b8629f76e6d247f169482520",
"assets/assets/images/cards/05-trefle.svg": "8a4a9757fa50c2c1b2cebec3743d57b9",
"assets/assets/images/cards/D-trefle.svg": "541cd0227ca62745ad6f082bd2081e5c",
"assets/assets/images/cards/06-coeur.svg": "19b68ac8270aec0de9c4a007309403b1",
"assets/assets/images/cards/07-pique.svg": "a556402f79b9c3630a47a9693318ba24",
"assets/assets/images/cards/08-trefle.svg": "d5742a2e6cfd93ad60ad044b066581c2",
"assets/assets/images/cards/02-carreau.svg": "53f1a5d591b67cd2f8954db53ae960e4",
"assets/assets/images/cards/R-coeur.svg": "d24db0826b2718b73eb39eebc19cb172",
"assets/assets/images/cards/07-carreau.svg": "a4e79b1f5fa1e0213aa1861b49a892b8",
"assets/assets/images/cards/R-trefle.svg": "5ddfaf6d5cd95e3c4a1de4dd1e7c4f58",
"assets/assets/images/cards/01-pique.svg": "6f7330d9a3a11aa8af57b9d66ee60425",
"assets/assets/images/cards/joker-noir.svg": "3f4a8a4c9ffd391374c3ebc365d4b8c5",
"assets/assets/images/cards/06-pique.svg": "4c1be03395aa298a7ba3f0564b6bc8d4",
"assets/assets/images/cards/07-coeur.svg": "c35be958e931ef5662a69f54dc01f02d",
"assets/assets/images/cards/R-carreau.svg": "11a340f5154af060b7e95363b64dcecf",
"assets/assets/images/cards/07-trefle.svg": "266285060fc3d899e668ea6bd02bd8a9",
"assets/assets/images/cards/D-carreau.svg": "383a3ed45a7554e327580be5b8f223d7",
"assets/assets/images/cards/04-carreau.svg": "9630afeeedb46c28f02271aafc77fe38",
"assets/assets/images/cards/R-pique.svg": "8336e26d4fd05977a36a199746932d44",
"assets/assets/images/cards/01-coeur.svg": "a7771124605b21593be3635e0b117225",
"assets/assets/images/cards/dos-bleu.svg": "947ecd3ff272c0cc89736c1f6590d1b1",
"assets/assets/images/cards/joker-rouge.svg": "0f494e8a2457322cc27bf6225aa4a158",
"assets/assets/images/cards/01-carreau.svg": "30e101aaf8fb4d710c0e83ed0803c20c",
"assets/assets/images/cards/02-trefle.svg": "90eed6a452e452e48d132dcead530316",
"assets/assets/images/cards/08-carreau.svg": "3625052dcabcbf07ed01e5117aff66bb",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01"};
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
