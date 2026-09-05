// 回顾页。设计稿 frame ②：上面月历卡，下面记录卡按日期从新到旧。
//
// 规格第七节明写 streak 已删除：顶部**不显示连续天数**。这是有意的功能差异，
// 不是漏做 —— 断一天就成心理负担，这个产品鼓励的是「想记就记」。
//
// 日历点击行为（2026-09-05 用户拍板，B 方案）：点有记录的日子直接开详情浮层；
// 没记录的那格是 disabled，点了不响应。

import {
  formatTitle, monthGrid, monthLabel, monthOf, sameMonth, shiftMonth, thisMonth, todayKey,
} from '../day.js';
import { allEntries } from '../db.js';
import { closeOverlays, openOverlay } from '../overlay.js';

const el = (id) => document.getElementById(id);

let entries = [];        // 新→旧，allEntries() 就是这个方向
let byDate = new Map();
let month = null;
let urls = [];           // 建过的 object URL，重建列表前要还回去，不然切几次页就漏一批

/* ── 载入 ─────────────────────────────────────────────────── */

export async function activate() {
  entries = await allEntries();
  byDate = new Map(entries.map((e) => [e.date, e]));
  month = thisMonth();   // 每次进页面都回到当月，不留在上次翻到哪儿
  render();
}

function render() {
  releaseUrls();
  const empty = entries.length === 0;
  // 一个一个点都没有的日历没信息量，空库时整页只留空状态。
  el('cal-card').hidden = empty;
  el('review-empty').hidden = !empty;
  renderCalendar();
  el('entry-list').replaceChildren(...entries.map(entryCard));
}

/* ── 月历 ─────────────────────────────────────────────────── */

function renderCalendar() {
  if (entries.length === 0) return;

  const { blanks, days } = monthGrid(month);
  const today = todayKey();

  el('cal-month').textContent = monthLabel(month);
  // 两头都封住：往后没有未来的记录，往前全是空月，翻下去只是白翻。
  el('cal-next').disabled = sameMonth(month, thisMonth());
  el('cal-prev').disabled = sameMonth(month, monthOf(entries[entries.length - 1].date));

  const cells = [];
  for (let i = 0; i < blanks; i += 1) {
    const blank = document.createElement('div');
    blank.className = 'cal-cell';
    cells.push(blank);
  }
  for (const { key, day } of days) cells.push(dayCell(key, day, key === today));
  el('cal-grid').replaceChildren(...cells);
}

function dayCell(key, day, isToday) {
  const entry = byDate.get(key);

  const cell = document.createElement('button');
  cell.type = 'button';
  cell.className = 'cal-cell';
  cell.disabled = !entry;
  if (entry) {
    cell.setAttribute('aria-label', `${formatTitle(key)}，有记录`);
    cell.onclick = () => openDetail(entry);
  }

  const num = document.createElement('span');
  num.className = isToday ? 'cal-day is-today' : 'cal-day';
  num.textContent = day;

  const dot = document.createElement('span');
  dot.className = entry ? 'cal-dot has' : 'cal-dot';

  cell.append(num, dot);
  return cell;
}

function shift(delta) {
  if (!month) return;
  month = shiftMonth(month, delta);
  renderCalendar();      // 只重画日历，不动列表 —— 免得照片重新加载闪一下
}

/* ── 记录列表 ─────────────────────────────────────────────── */

function entryCard(entry) {
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'tl-card';
  card.onclick = () => openDetail(entry);

  const main = document.createElement('div');
  main.className = 'tl-main';

  const date = document.createElement('div');
  date.className = 'tl-date';
  date.textContent = formatTitle(entry.date);

  const text = document.createElement('div');
  text.className = 'tl-text';
  text.textContent = entry.text;   // textContent 不是 innerHTML —— 用户写的东西不当 HTML 解析

  main.append(date, text);
  card.append(main);

  if (entry.photo) {
    const img = document.createElement('img');
    img.className = 'tl-photo';
    img.alt = '';                  // 纯装饰，日期和正文已经说明了这是哪天
    img.loading = 'lazy';          // 记录多了以后别一次解码上百张缩略图
    img.decoding = 'async';
    img.src = objectUrl(entry.photo);
    card.append(img);
  }
  return card;
}

/* ── 详情浮层（只读）──────────────────────────────────────── */

function openDetail(entry) {
  el('detail-date').textContent = formatTitle(entry.date);

  const photo = el('detail-photo');
  photo.hidden = !entry.photo;
  if (entry.photo) photo.src = objectUrl(entry.photo);

  el('detail-text').textContent = entry.text;
  openOverlay('entry-sheet');
}

/* ── object URL 记账 ──────────────────────────────────────── */

function objectUrl(blob) {
  const url = URL.createObjectURL(blob);
  urls.push(url);
  return url;
}

function releaseUrls() {
  for (const url of urls) URL.revokeObjectURL(url);
  urls = [];
}

/* ── 接线 ─────────────────────────────────────────────────── */

export function init() {
  el('cal-prev').addEventListener('click', () => shift(-1));
  el('cal-next').addEventListener('click', () => shift(1));
  el('detail-close').addEventListener('click', closeOverlays);
}
