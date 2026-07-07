'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "1a67d67c2b60e96d6822aab37f801047",
"version.json": "9c657deafc0fc254632d3a8b63ce5e22",
"index.html": "4f39f07a188673d3e8ebe47fad985fa0",
"/": "4f39f07a188673d3e8ebe47fad985fa0",
"main.dart.js": "a6d875672ca3c3f978a3d15f9e9dd454",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "e012a17ae96a0f068d1dffb808af7937",
"assets/NOTICES": "c4a8579612f56fc77a194e705b7fc4d7",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "58c6487c7c6599a7e6be6a38d9db3b00",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "da9ed134c59be59f2ac30655e4501a74",
"assets/fonts/MaterialIcons-Regular.otf": "d377b772e456d8926b44b000f86cf1fb",
"assets/assets/tiles/m3.png": "361d9121e53702efc04ed010b3f436f6",
"assets/assets/tiles/%25E7%2599%25BC.png": "3e4868f3ef3f1fb2b34bc3eb809d89b1",
"assets/assets/tiles/m2.png": "914e19c9fa828007c023fc78268f3800",
"assets/assets/tiles/m1.png": "66a3b8f53bdbbda39bc787dd5ac5796c",
"assets/assets/tiles/%25E5%258D%2597.png": "9dafeb2c85b4b62e45b0b8046e50c1bf",
"assets/assets/tiles/m5.png": "00b67b9053b3af329b8c44c6d342de1a",
"assets/assets/tiles/%25E7%2599%25BD.png": "d3f6d2d79d5402fe0f13648b4a670139",
"assets/assets/tiles/m4.png": "379755372b89461ad222ee4a36010b15",
"assets/assets/tiles/m6.png": "8cb7c0e703ed249f73eefa378ac1e1b6",
"assets/assets/tiles/m7.png": "6df9b854d6d724f57e9bd1333b25c52e",
"assets/assets/tiles/s6.png": "8786309b0ac3ec0474ac10610d2392ab",
"assets/assets/tiles/s7.png": "cb68799ac9c755a872caa81b66122316",
"assets/assets/tiles/p9.png": "2c4848fd7f10db93e366a5f8d81b7d2b",
"assets/assets/tiles/s5.png": "3374c7bf54aa71a6b43f1aa9c28d9aa0",
"assets/assets/tiles/s4.png": "95b71388491805ec6922c59f53798f09",
"assets/assets/tiles/p8.png": "3238d32b423fb1d7095dbfb722cf2545",
"assets/assets/tiles/s1.png": "785af86f41a745d99cc4e691284d54b8",
"assets/assets/tiles/s3.png": "de74824da51d9c901630f3762e677380",
"assets/assets/tiles/s2.png": "9998fb4b92999ae834a276f188c12935",
"assets/assets/tiles/p3.png": "0a163f0189ff7fb608fe75ac0aafaa46",
"assets/assets/tiles/%25E8%25A5%25BF.png": "af7d5867e97225db9eb887b4e68c0b8e",
"assets/assets/tiles/p2.png": "ef10f0d25d7233659641ac4d8f5475f2",
"assets/assets/tiles/p1.png": "5c5ef9d4d52b15f6c23ff2567e97bf27",
"assets/assets/tiles/p5.png": "49687246165966e2dd0ea8d5bc63767c",
"assets/assets/tiles/s9.png": "5688d261af839556394ad4c31d8776a3",
"assets/assets/tiles/s8.png": "86bbd3c71bb15c99c7686e5371ce4c98",
"assets/assets/tiles/p4.png": "22e9ecb563338c70f8d682e3ac812331",
"assets/assets/tiles/p6.png": "3c031bd87b7de9886a671ff28037a134",
"assets/assets/tiles/p7.png": "d0f98a689008e95e784c4e07d835913c",
"assets/assets/tiles/%25E6%259D%25B1.png": "54644dd8f3aa68f7d85e76647e1209d7",
"assets/assets/tiles/m9.png": "0445ddf7c09feeff4b473122451b6e70",
"assets/assets/tiles/%25E5%258C%2597.png": "04f3296085099d05a171c03354020b20",
"assets/assets/tiles/m8.png": "3a52441fdf5e18a721c2237fa1ed1898",
"assets/assets/tiles/%25E4%25B8%25AD.png": "fe50a78955f5fde20f574e6225c2d564",
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
