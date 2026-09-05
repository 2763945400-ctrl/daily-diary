// 今天页。形态照设计稿 frame ①：写作卡在上、添加照片在卡内、静坐入口在下。
// （随手记案例 3 那份规格的文字写的是「静坐→写作→照片」，和设计稿相反；
//   协作开发笔记第三节记过这个坑，结论是以设计稿为准。）
//
// 随手记的三条拍板决定（案例 3 第一节）：
//   1. 并入 = 换行追加到正文末尾，不加时间戳/圆点
//   2. 删除不弹确认框，直接删 + 几秒「撤销」
//   3. 捕捉后关闭浮层回主页，不连续记
//
// 正文和照片是自动保存的：停止输入 800ms 后直接写进日记，不是草稿——
// 写进去就算记下了，回顾页立刻看得到。「记下今天」保留为确认手势，
// 点它会把待写的那次立刻落库并给回执。
// （案例 3 规格第 2.4 节原本接受「未保存草稿会丢」，2026-09-05 用户推翻。）

import { formatTime, formatTitle, todayKey } from '../day.js';
import {
  addNote, deleteEntry, deleteNote, getEntry, putEntry, putNote, todaysNotes,
} from '../db.js';
import { compress } from '../photo.js';
import { closeOverlays, openOverlay } from '../overlay.js';
import { toast } from '../toast.js';

const el = (id) => document.getElementById(id);

let dateKey = null;
let photo = null;        // 当前草稿的照片 Blob
let photoUrl = null;     // 预览用的 object URL，换图/清空时要 revoke
let saved = false;       // 进页面时这一天有没有记录，决定按钮写「记下」还是「更新」
let autosaveTimer = null;
let savedText = '';      // 最近一次落库的正文，flush 靠它判断有没有变化

/* ── 载入 ─────────────────────────────────────────────────── */

/** 每次切到今天页都跑一遍 —— 跨过日界再回来时日期要自己翻篇。 */
export async function activate() {
  const key = todayKey();
  if (key === dateKey) {
    await refreshPending();
    return;
  }

  dateKey = key;
  el('today-date').textContent = formatTitle(dateKey);

  const entry = await getEntry(dateKey);
  saved = entry !== null;
  el('entry-text').value = entry?.text ?? '';
  savedText = entry?.text ?? '';
  setPhoto(entry?.photo ?? null);
  autoGrow();
  syncSaveButton();
  await refreshPending();
}

function syncSaveButton() {
  el('save-entry').textContent = saved ? '更新今天' : '记下今天';
}

/**
 * 库被清空或导入过之后，这一页缓存的内容就不作数了 —— 整页重来。
 * 不重置的话：清空之后切回今天，输入框里还留着刚被删掉的正文，
 * 再敲一个字就把它原样写回库里去了。
 */
export async function reset() {
  clearTimeout(autosaveTimer);   // 待写的那次别在重载之后才落库
  autosaveTimer = null;
  dateKey = null;                // 逼 activate() 走完整重载，不走「同一天就跳过」那条捷径
  savedText = '';
  el('entry-text').value = '';
  setPhoto(null);
  await activate();
}

/* ── 写作区 ───────────────────────────────────────────────── */

function autoGrow() {
  const box = el('entry-text');
  box.style.height = 'auto';
  box.style.height = `${box.scrollHeight}px`;
}

const AUTOSAVE_DELAY = 800;

/**
 * 真正写库。正文和照片都空就把这天删掉 ——
 * 敲两个字又删干净不该在回顾里留一条空记录。
 * 返回是否留下了内容。
 */
async function persist() {
  clearTimeout(autosaveTimer);
  autosaveTimer = null;
  if (!dateKey) return false;

  const text = el('entry-text').value.trim();
  if (!text && !photo) {
    await deleteEntry(dateKey);
    savedText = '';
    return false;
  }
  await putEntry(dateKey, { text, photo });
  savedText = text;
  return true;
}

/** 输入停下来 800ms 后落库。打字过程中不写，免得每个键都开一次事务。 */
function scheduleSave() {
  clearTimeout(autosaveTimer);
  autosaveTimer = setTimeout(persist, AUTOSAVE_DELAY);
}

/**
 * 把没落库的改动立刻写掉。切页、切后台、被杀之前都要调。
 * 判断依据是「正文和上次落库的不一样」而不是「有没有待写的定时器」——
 * 后者只要哪处改动漏调 scheduleSave 就会静默丢数据（并入碎片就踩过这个坑）。
 */
export function flush() {
  if (el('entry-text').value.trim() !== savedText) persist();
}

async function save() {
  const kept = await persist();
  if (!kept) {
    toast('写点什么再记下吧');
    return;
  }
  const isUpdate = saved;
  saved = true;
  syncSaveButton();
  toast(isUpdate ? '已更新' : '已记下');   // 保存后停留当前页，不跳转
}

/* ── 照片 ─────────────────────────────────────────────────── */

function setPhoto(blob) {
  if (photoUrl) URL.revokeObjectURL(photoUrl);
  photo = blob;
  photoUrl = blob ? URL.createObjectURL(blob) : null;

  el('photo-slot').hidden = !blob;
  el('add-photo').hidden = Boolean(blob);
  if (blob) el('photo-preview').src = photoUrl;
}

async function pickPhoto(event) {
  const file = event.target.files?.[0];
  event.target.value = '';           // 清掉，不然选同一张不会再触发 change
  if (!file) return;
  try {
    setPhoto(await compress(file));
    await persist();
  } catch {
    toast('这张图读不了，换一张试试');
  }
}

/* ── 随手记：待整理角标 ───────────────────────────────────── */

async function refreshPending() {
  const notes = await todaysNotes();
  el('pending-chip').hidden = notes.length === 0;
  el('pending-count').textContent = `待整理 ${notes.length}`;
  return notes;
}

/* ── 随手记：捕捉浮层 ─────────────────────────────────────── */

function openCapture() {
  el('capture-text').value = '';
  openOverlay('capture-sheet');
  el('capture-text').focus();
}

async function saveCapture() {
  const text = el('capture-text').value.trim();
  if (text) await addNote(text);
  closeOverlays();
  await refreshPending();
}

/* ── 随手记：整理浮层 ─────────────────────────────────────── */

async function openInbox() {
  await renderInbox();
  openOverlay('inbox-sheet');
}

async function renderInbox() {
  const notes = await refreshPending();
  if (notes.length === 0) {          // 整理光了浮层自己关掉
    closeOverlays();
    return;
  }

  el('inbox-count').textContent = `${notes.length} 条`;
  el('inbox-list').replaceChildren(...notes.map(noteRow));
}

function noteRow(note) {
  const row = document.createElement('div');
  row.className = 'note-row';

  const time = document.createElement('div');
  time.className = 'note-time';
  time.textContent = formatTime(note.createdAt);

  const body = document.createElement('div');
  body.className = 'note-text';
  body.textContent = note.text;      // textContent 不是 innerHTML —— 用户写的内容不当 HTML 解析

  const actions = document.createElement('div');
  actions.className = 'note-actions';

  const merge = document.createElement('button');
  merge.type = 'button';
  merge.className = 'note-merge';
  merge.textContent = '并入今天';
  merge.onclick = () => mergeNote(note);

  const remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'note-delete';
  remove.textContent = '删除';
  remove.onclick = () => removeNote(note);

  actions.append(merge, remove);
  row.append(time, body, actions);
  return row;
}

async function mergeNote(note) {
  const box = el('entry-text');
  box.value = box.value.trim() ? `${box.value}\n${note.text}` : note.text;
  autoGrow();
  scheduleSave();
  await deleteNote(note.id);
  await renderInbox();
  toast('已并入今天');
}

async function removeNote(note) {
  await deleteNote(note.id);
  await renderInbox();
  toast('已删除', {
    action: '撤销',
    onAction: async () => {
      await putNote(note);           // 连 id 和 createdAt 一起还原，顺序不会乱
      if (el('inbox-sheet').hidden) await refreshPending();
      else await renderInbox();
    },
  });
}

/* ── 接线 ─────────────────────────────────────────────────── */

export function init() {
  el('entry-text').addEventListener('input', () => {
    autoGrow();
    scheduleSave();
  });
  el('save-entry').addEventListener('click', save);

  el('add-photo').addEventListener('click', () => el('photo-input').click());
  el('photo-input').addEventListener('change', pickPhoto);
  el('photo-remove').addEventListener('click', async () => {
    setPhoto(null);
    await persist();
  });

  // iOS 杀后台不打招呼，能抓到的最后时机就这两个事件。
  window.addEventListener('pagehide', flush);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) flush();
  });

  el('capture-fab').addEventListener('click', openCapture);
  el('capture-save').addEventListener('click', saveCapture);
  el('pending-chip').addEventListener('click', openInbox);
  el('inbox-close').addEventListener('click', closeOverlays);
}
