// ════════════════════════════════════════════════════════════
//  أواب — Service Worker
//  الهدف: تخزين الـApp Shell (index.html + الأيقونات + المانيفست)
//  محليًا عشان التطبيق يفتح بدون نت. البيانات نفسها (العبادات،
//  السجلات...) بتتخزن في IndexedDB مش هنا — الـSW مسؤول بس عن
//  ملفات التطبيق الثابتة.
//
//  الاستراتيجية:
//  - navigation requests (فتح الصفحة): Network-First مع fallback
//    للنسخة المخزنة لو مفيش نت (عشان دايمًا يجيب أحدث نسخة أول
//    ما يبقى فيه نت، بدل ما يعلق على نسخة قديمة).
//  - باقي الملفات الثابتة من نفس الأصل (same-origin): Cache-First
//    مع تحديث الكاش في الخلفية (stale-while-revalidate بسيط).
//  - أي حاجة من أصل تاني (CDN زي jsdelivr): تسيب المتصفح يتصرف
//    عادي، من غير تدخل من الـSW.
// ════════════════════════════════════════════════════════════

const CACHE_VERSION = 'awwab-v1';
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
  '/apple-touch-icon.png',
  '/favicon-32.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return; // POST/PATCH/DELETE (Supabase writes) تعدي عادي، الـSW ميتدخلش فيها
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // مش أصل التطبيق (Supabase/CDN...) — سيبها للمتصفح

  // تنقّل بين الصفحات (فتح/تحديث التطبيق نفسه)
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          caches.open(CACHE_VERSION).then((cache) => cache.put('/index.html', res.clone()));
          return res;
        })
        .catch(() => caches.match('/index.html'))
    );
    return;
  }

  // ملفات ثابتة من نفس الأصل: Cache-First + تحديث في الخلفية
  event.respondWith(
    caches.match(req).then((cached) => {
      const fetchPromise = fetch(req)
        .then((res) => {
          if (res && res.ok) caches.open(CACHE_VERSION).then((cache) => cache.put(req, res.clone()));
          return res;
        })
        .catch(() => cached);
      return cached || fetchPromise;
    })
  );
});

// يسمح لصفحة التطبيق تقول للـSW الجديد "خد بالك دلوقتي" بدل ما
// ينتظر إغلاق كل التابات (زر "تحديث الآن" في sw-update-banner)
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
