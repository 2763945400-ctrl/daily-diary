// Service Worker —— 只有网页版用得上。
//
// ⚠️ 这个文件是**模板**，不直接上线。vite.config.js 里的 diary-sw 插件在构建时
//    把下面两个占位符换成真实值，输出成 dist/sw.js。
//    直接改 dist/sw.js 没有意义，下次构建就被覆盖。
//    它也不走 Vite 的模块管线（没人 import 它），所以**不能写 import**。
//
// 规格第九节的四条预警，逐条对应：
//   ① 缓存名带版本号            → CACHE，版本戳是全部预缓存文件内容的哈希，改一个字就变
//   ② install 全量预缓存，任一文件失败则整次失败 → cache.addAll() 本身就是全有或全无
//   ③ 不调 skipWaiting()        → 全文没有这个调用，新版本只在下次冷启动接管
//   ④ activate 删旧缓存         → 见下

const CACHE = 'diary-__CACHE_VERSION__';
const PRECACHE = __PRECACHE__;
const INDEX = './index.html';

self.addEventListener('install', (event) => {
  // addAll 是全有或全无的：任何一个请求非 2xx 或网络中断，整个 Promise 就 reject，
  // install 失败 —— 这个版本不会进 waiting，也不会在缓存里留下半份文件。
  // 半份缓存比没有缓存更糟：应用能打开但缺 CSS，看着像坏了。
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)));

  // ⚠️ 这里绝对不能加 self.skipWaiting()。
  //    加了的话，用户正写着日记时新版本会当场顶掉旧版本，输入被打断。
  //    代价只是新版本晚一次冷启动生效，完全划算。
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith('diary-') && key !== CACHE)
        .map((key) => caches.delete(key)),
    );

    // clients.claim() 和 skipWaiting() 是两回事，别搞混：
    //   skipWaiting = 「抢在旧版本还开着的时候上位」→ 会打断输入，所以不用
    //   claim       = 「我已经合法上位了，把现有页面接管过来」
    // 真正起作用的只有首次安装那一次（此前没有 SW，activate 立刻就跑）：
    // 有它，第一次访问当场就能离线；没它，得等下一次打开。
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  if (new URL(req.url).origin !== self.location.origin) return;   // 外链一概不接手

  // hash 路由，整个站点只有 index.html 一个真实页面。
  // 任何导航请求都回它 —— 包括直接输入带 #/review 的网址（hash 不会发给服务器）。
  if (req.mode === 'navigate') {
    event.respondWith(serve(INDEX, req));
    return;
  }
  event.respondWith(serve(req, req));
});

/**
 * 缓存优先。产物文件名带内容哈希，缓存里的那份永远是对的，不需要回源校验。
 * 版本更新靠的是「sw.js 变了 → 浏览器装新 SW → 换新缓存名」这条线，不是靠这里。
 */
async function serve(key, req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(key);
  if (hit) return hit;

  // 没进预缓存的东西（图标、favicon）走网络。
  // 离线时 fetch 会抛，得兜住，否则控制台冒未处理的 rejection —— 验收要求 0 报错。
  try {
    return await fetch(req);
  } catch {
    return new Response('', { status: 504, statusText: 'offline' });
  }
}
