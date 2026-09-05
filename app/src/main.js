// 骨架路由：hash 决定显示哪一页。
// 今天/回顾/设置带底部导航；静坐是全屏页，进去就把导航藏掉。

import { closeOverlays, initOverlays } from './overlay.js';
import * as review from './pages/review.js';
import * as settings from './pages/settings.js';
import * as today from './pages/today.js';

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

window.addEventListener('hashchange', render);
initOverlays();
today.init();
review.init();
// 清空 / 导入会动到今天页正在显示的那天，让它整页重来。
settings.init(today.reset);
trackKeyboard();
render();
