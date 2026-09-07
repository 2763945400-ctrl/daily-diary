// 骨架路由：hash 决定显示哪一页。
// 今天/回顾/设置带底部导航；静坐是全屏页，进去就把导航藏掉。

import { getSetting, setSetting } from './db.js';
import { closeOverlays, initOverlays } from './overlay.js';
import { IS_WEB } from './platform.js';
import * as meditate from './pages/meditate.js';
import * as review from './pages/review.js';
import * as settings from './pages/settings.js';
import * as today from './pages/today.js';
import { toast } from './toast.js';

const TABS = ['today', 'review', 'settings'];
const ROUTES = [...TABS, 'meditate'];

const nav = document.getElementById('nav');
const navItems = document.querySelectorAll('.nav-item');

function currentRoute() {
  const name = location.hash.replace(/^#\/?/, '');
  return ROUTES.includes(name) ? name : 'today';
}

function render() {
  const route = currentRoute();

  for (const name of ROUTES) {
    document.getElementById(`page-${name}`).hidden = name !== route;
  }
  for (const item of navItems) {
    item.classList.toggle('is-active', item.dataset.route === route);
  }

  nav.hidden = !TABS.includes(route);
  document.getElementById('capture-fab').hidden = route !== 'today';
  document.body.classList.toggle('is-immersive', route === 'meditate');
  document.getElementById('view').scrollTop = 0;

  today.flush();            // 离开今天页前把没落库的那次写掉
  closeOverlays();
  if (route === 'today') today.activate();
  // 静坐是唯一一个「离开就要停表」的页，所以两头都接
  if (route === 'meditate') meditate.activate();
  else meditate.deactivate();
  if (route === 'review') review.activate();
  if (route === 'settings') settings.activate();
}

// iOS Safari 键盘弹出时不改 innerHeight，只缩 visualViewport（规格第九节）。
// 把键盘高度写进 --kb，浮层靠它抬起来，不然输入框会被键盘盖住。
function trackKeyboard() {
  const vv = window.visualViewport;
  if (!vv) return;
  const sync = () => {
    const inset = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
    document.documentElement.style.setProperty('--kb', `${inset}px`);
  };
  vv.addEventListener('resize', sync);
  vv.addEventListener('scroll', sync);
  sync();
}

/* ── 网页版专属：离线缓存 + 加主屏提示 ─────────────────────── */

/**
 * 注册 Service Worker。只在网页版的**生产构建**里做。
 *
 * dev server 下不注册：Vite 是按模块一个个发的，缓存了反而会拿到过期模块，
 * 改一行代码看不到效果，能查半天。要验缓存请 npm run build + 静态服务器。
 *
 * updateViaCache: 'none' —— 否则 sw.js 自己会被浏览器的普通 HTTP 缓存挡住，
 * 最长 24 小时都发现不了新版本。
 */
function registerServiceWorker() {
  if (!IS_WEB || !import.meta.env.PROD || !('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js', { updateViaCache: 'none' })
      .catch(() => {});   // 注册失败（无痕模式、存储被禁）不影响使用，只是没有离线能力
  });
}

/**
 * iOS 上提示一次「添加到主屏幕」。规格第九节：Safari 标签页和主屏 PWA 的存储
 * 是两套，且标签页那套会被 Safari 按「长期未访问」清掉 —— 对一个只存本地的
 * 日记应用来说这是丢数据。
 *
 * 只提示一次，且已经在主屏运行的不提示。
 */
async function hintAddToHomeScreen() {
  if (!IS_WEB) return;
  if (!/iP(hone|ad|od)/.test(navigator.userAgent)) return;
  // navigator.standalone 是 iOS 独有的；display-mode 兜安卓和以后的 iOS
  if (navigator.standalone === true || matchMedia('(display-mode: standalone)').matches) return;
  if (await getSetting('homeScreenHinted', false)) return;

  // 先落标记再提示：这样即使用户没点「知道了」直接关掉页面，也不会下次再烦一遍
  await setSetting('homeScreenHinted', true);
  toast('建议添加到主屏幕：留在 Safari 标签页里，记录可能被系统清掉', {
    action: '知道了',
    duration: 15_000,
  });
}

window.addEventListener('hashchange', render);
initOverlays();
today.init();
review.init();
meditate.init();
// 清空 / 导入会动到今天页正在显示的那天，让它整页重来。
settings.init(today.reset);
trackKeyboard();
render();
registerServiceWorker();
hintAddToHomeScreen();
