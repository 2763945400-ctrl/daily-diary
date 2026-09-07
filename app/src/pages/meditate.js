// 静坐页。行为逐条对着 lib/pages/meditate_page.dart 核过（只读没改）：
//   进页面直接开始，用上次的时长并立刻记住
//   **以结束时刻比对真实时间**判定结束，不靠计时器累加 —— 切后台计时器会被压慢
//   改时长 = 从现在重新算（规格第八节「点了重置继续走」）
//   剩余分钟向上取整并夹在 [1, 总时长]，所以最后一分钟一直显示「还剩 1 分钟」
//   钟声**只在结束时响**，开始时不响
//   左上 ✕ 和「提前结束」完全等同：静默退出，不响铃
//   结束后圆环消失、中间显示「慢慢回来」、点屏幕任意处退回

import { playBell, prepare } from '../bell.js';
import { getSetting, setSetting } from '../db.js';

const el = (id) => document.getElementById(id);

export const DEFAULT_MINUTES = 10;
const SETTING_KEY = 'meditationMinutes';

let minutes = DEFAULT_MINUTES;
let endAt = null;
let done = false;
let ticker = null;
let dimTimer = null;
let wakeTap = false;    // 这一下点击是「把画面唤回来」还是真的在操作
let wakeLock = null;

/* ── 进出 ─────────────────────────────────────────────────── */

export async function activate() {
  minutes = await getSetting(SETTING_KEY, DEFAULT_MINUTES);
  await setSetting(SETTING_KEY, minutes);   // 照老版本：进页面就把当前时长记下
  prepare();                                // 趁刚才点进来那一下手势，把音频备好
  start();
  keepAwake();
}

/** 离开这一页就停表。提前结束、左上 ✕、切 tab 走的都是这条。 */
export function deactivate() {
  stopTicker();
  stopDim();
  endAt = null;
  done = false;
  releaseWake();
}

function start() {
  done = false;
  endAt = Date.now() + minutes * 60_000;
  render();
  stopTicker();
  ticker = setInterval(tick, 1000);
  scheduleDim();
}

function stopTicker() {
  clearInterval(ticker);
  ticker = null;
}

/* ── 自动压暗 ─────────────────────────────────────────────── */

const DIM_AFTER = 8000;

/** 亮回来并重新计时。碰屏幕、开始、改时长都走这条。 */
function scheduleDim() {
  clearTimeout(dimTimer);
  el('page-meditate').classList.remove('is-dimmed');
  if (done) return;
  dimTimer = setTimeout(() => el('page-meditate').classList.add('is-dimmed'), DIM_AFTER);
}

function stopDim() {
  clearTimeout(dimTimer);
  dimTimer = null;
  el('page-meditate').classList.remove('is-dimmed');
}

/* ── 走表 ─────────────────────────────────────────────────── */

function tick() {
  if (done || !endAt) return;
  if (Date.now() >= endAt) finish();
  else render();
}

function finish() {
  done = true;
  stopTicker();
  stopDim();        // 铃响了得让人看见「慢慢回来」，这时候不能是暗的
  releaseWake();      // 结束了就别再按着屏幕不让它睡
  render();
  playBell();
}

/** 老版本：(秒/60) 向上取整，夹在 [1, 总时长]。 */
function remainingMinutes() {
  const secs = (endAt - Date.now()) / 1000;
  return Math.min(minutes, Math.max(1, Math.ceil(secs / 60)));
}

function render() {
  el('breath-ring').hidden = done;
  el('med-bottom').hidden = done;
  el('med-label').textContent = done ? '慢慢回来' : `还剩 ${remainingMinutes()} 分钟`;
  for (const button of el('med-opts').children) {
    button.classList.toggle('is-sel', Number(button.dataset.minutes) === minutes);
  }
}

/* ── 屏幕常亮 ─────────────────────────────────────────────── */
/* 拿不到就算了：不支持、用户拒绝、低电量模式都可能失败，静坐照走不受影响。
   ⚠️ 网页拿不到屏幕亮度的控制权，浏览器不给这个 API，只能做到「不息屏」。 */

async function keepAwake() {
  try {
    wakeLock = (await navigator.wakeLock?.request('screen')) ?? null;
  } catch {
    wakeLock = null;
  }
}

function releaseWake() {
  wakeLock?.release?.().catch(() => {});
  wakeLock = null;
}

/* ── 接线 ─────────────────────────────────────────────────── */

export function init() {
  el('med-opts').addEventListener('click', async (event) => {
    const button = event.target.closest('button[data-minutes]');
    if (!button) return;
    const picked = Number(button.dataset.minutes);
    if (picked === minutes) return;         // 照老版本：点当前这个不重置
    minutes = picked;
    await setSetting(SETTING_KEY, picked);
    start();
  });

  // 碰一下就亮回来，并重新开始数 8 秒
  el('page-meditate').addEventListener('pointerdown', () => {
    if (done) return;
    // 每次按下都重新判定，所以「唤醒了但没点到任何按钮」不会把下一次真操作也吞掉
    wakeTap = el('page-meditate').classList.contains('is-dimmed');
    scheduleDim();
  });

  // 压暗时的第一下只负责唤醒，在捕获阶段就吞掉，别让它落到时长按钮或 ✕ 上。
  // CSS 的 pointer-events: none 只挡得住按下那一刻，抬手时画面已经亮回来了，
  // 光靠它会漏 —— 摸黑一碰就把 20 分钟重置成 5 分钟。
  el('page-meditate').addEventListener('click', (event) => {
    if (!wakeTap) return;
    wakeTap = false;
    event.preventDefault();
    event.stopPropagation();
  }, true);

  // 结束后点屏幕任意处退回（老版本就是整页可点）
  el('page-meditate').addEventListener('click', () => {
    if (done) location.hash = '#/today';
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden || !endAt || done) return;
    tick();          // 后台时 setInterval 会被压慢，回前台立刻按真实时间对一次表
    keepAwake();     // 切走时系统会自动松开常亮，回来要重新按住
  });
}
