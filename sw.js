const CACHE = 'worktracker-v1.51';
const SHELL = [
  './index.html',
  './app.html',
  './style.css',
  './config.js',
  './auth.js',
  './app.js',
  './manifest.json',
  './icons/icon.svg',
  './icons/Proagrar_LOGO.png',
  './icons/Proagrar_icon.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = e.request.url;

  // Always network-first for Supabase and CDN
  if (url.includes('supabase.co') || url.includes('cdn.jsdelivr.net')) {
    e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
    return;
  }

  // Network-first for HTML and JS — always picks up code changes when online.
  // cache: 'no-store' bypasses the browser's own HTTP cache, not just ours —
  // otherwise a Cache-Control header from GitHub Pages can make fetch()
  // silently return a stale response with no real network round-trip.
  if (url.endsWith('.html') || url.endsWith('.js')) {
    e.respondWith(
      fetch(e.request, { cache: 'no-store' })
        .then(res => {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // Cache-first for CSS, icons, manifest
  e.respondWith(
    caches.match(e.request).then((cached) => cached ?? fetch(e.request))
  );
});
