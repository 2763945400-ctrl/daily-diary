// 存储层。IndexedDB 库名 diary，三个 object store（规格第七节）：
//   entries  主键 = 'yyyy-MM-dd'  → { text, photo: Blob|null, createdAt, updatedAt }
//   notes    主键 = 毫秒时间戳字符串 → { text, createdAt }
//   settings 主键 = 设置项名字      → 任意值
//
// 主键都是 out-of-line（不存在值里），所以读出来时由这里把 date / id 拼回去，
// 保证值的结构和规格里的导出 JSON 逐字对齐。
// 时间一律毫秒整数；照片存 Blob，只在导出时才转 base64。

import { logicalKey, todayKey } from './day.js';

const DB_NAME = 'diary';
const DB_VERSION = 1;
const STORES = ['entries', 'notes', 'settings'];
const DATA_STORES = ['entries', 'notes'];

let dbPromise = null;

function open() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        for (const name of STORES) {
          if (!req.result.objectStoreNames.contains(name)) {
            req.result.createObjectStore(name);
          }
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  return dbPromise;
}

/** 把一个 IDBRequest 包成 Promise。 */
function done(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

/** 开一个事务并立刻拿到 store —— fn 必须同步发起请求，不然事务会先关掉。 */
async function withStore(name, mode, fn) {
  const db = await open();
  return fn(db.transaction(name, mode).objectStore(name));
}

/* ── entries ──────────────────────────────────────────────── */

/** 读一天的记录，没有返回 null。 */
export function getEntry(date) {
  return withStore('entries', 'readonly', async (s) => (await done(s.get(date))) ?? null);
}

/** 写一天的记录。已存在则保留原 createdAt，只更新 updatedAt。 */
export function putEntry(date, { text, photo = null }) {
  return withStore('entries', 'readwrite', async (s) => {
    const existing = await done(s.get(date));
    const now = Date.now();
    const value = {
      text,
      photo,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    await done(s.put(value, date));
    return value;
  });
}

/** 全部记录，日期从新到旧。 */
export function allEntries() {
  return withStore('entries', 'readonly', async (s) => {
    // getAllKeys / getAll 都按主键升序返回，可以直接对位拼。
    const [dates, values] = await Promise.all([done(s.getAllKeys()), done(s.getAll())]);
    return dates.map((date, i) => ({ date, ...values[i] })).reverse();
  });
}

export function deleteEntry(date) {
  return withStore('entries', 'readwrite', (s) => done(s.delete(date)));
}

/* ── notes（随手记）───────────────────────────────────────── */

/** 记一条碎片，返回带 id 的完整条目。 */
export function addNote(text) {
  return withStore('notes', 'readwrite', async (s) => {
    const createdAt = Date.now();
    const id = String(createdAt);
    await done(s.put({ text, createdAt }, id));
    return { id, text, createdAt };
  });
}

/** 全部碎片，按记录时间从旧到新。 */
export function allNotes() {
  return withStore('notes', 'readonly', async (s) => {
    const [ids, values] = await Promise.all([done(s.getAllKeys()), done(s.getAll())]);
    return ids.map((id, i) => ({ id, ...values[i] }));
  });
}

/** 今天（按凌晨 2 点日界）记下的碎片 —— 待整理角标数的来源。 */
export async function todaysNotes() {
  const today = todayKey();
  return (await allNotes()).filter((n) => logicalKey(new Date(n.createdAt)) === today);
}

/** 原样写回一条碎片，保留原 id 和 createdAt（撤销删除、导入时用）。 */
export function putNote({ id, text, createdAt }) {
  return withStore('notes', 'readwrite', (s) => done(s.put({ text, createdAt }, id)));
}

export function deleteNote(id) {
  return withStore('notes', 'readwrite', (s) => done(s.delete(id)));
}

/* ── settings ─────────────────────────────────────────────── */

export function getSetting(key, fallback = null) {
  return withStore('settings', 'readonly', async (s) => {
    const v = await done(s.get(key));
    return v === undefined ? fallback : v;
  });
}

export function setSetting(key, value) {
  return withStore('settings', 'readwrite', (s) => done(s.put(value, key)));
}

/* ── 清除 ─────────────────────────────────────────────────── */

/**
 * 清空日记和碎片，一个事务里做完，要么全清要么全不清。
 * 不碰 settings —— 提醒时间、静坐时长是偏好不是记录，
 * 跟着一起清会把用户的每日提醒静悄悄关掉。
 */
export async function clearAllData() {
  const db = await open();
  const t = db.transaction(DATA_STORES, 'readwrite');
  for (const name of DATA_STORES) t.objectStore(name).clear();
  return new Promise((resolve, reject) => {
    t.oncomplete = () => resolve();
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

/* ── 条数 ─────────────────────────────────────────────────── */

/** 设置页「导出备份」副标题用。走 count() 不走 getAll，免得把照片全读进内存。 */
export async function counts() {
  const db = await open();
  const t = db.transaction(DATA_STORES, 'readonly');
  const [entries, notes] = await Promise.all([
    done(t.objectStore('entries').count()),
    done(t.objectStore('notes').count()),
  ]);
  return { entries, notes };
}

/* ── 导入 ─────────────────────────────────────────────────── */

/**
 * 批量写入备份里的内容。entries 按 date、notes 按 id 去重，**已存在的跳过不覆盖**。
 * 返回 { added, skipped } —— 日记和碎片合并计数（Flutter 版的文案就是合并的）。
 *
 * ⚠️ 照片必须在调用前就解好成 Blob（backup.js 干这活）。
 *    IndexedDB 的事务只要 await 了非 IDB 的东西就会自己关掉，
 *    在事务里解 base64 会写到一半事务没了。
 *
 * 整个导入是一个事务：要么全进去，要么一条都不进，不会留下导一半的库。
 */
export async function importAll(entries, notes) {
  const db = await open();
  const t = db.transaction(DATA_STORES, 'readwrite');
  const entryStore = t.objectStore('entries');
  const noteStore = t.objectStore('notes');

  const [haveDates, haveIds] = await Promise.all([
    done(entryStore.getAllKeys()),
    done(noteStore.getAllKeys()),
  ]);
  const dates = new Set(haveDates);
  const ids = new Set(haveIds.map(String));

  const now = Date.now();
  let added = 0;
  let skipped = 0;

  for (const e of entries) {
    // 边加边记：同一个文件里万一有两条同日期，第二条也照样算跳过。
    if (dates.has(e.date)) { skipped += 1; continue; }
    dates.add(e.date);
    entryStore.put({
      text: e.text,
      photo: e.photo,
      createdAt: e.createdAt ?? now,
      updatedAt: e.updatedAt ?? now,
    }, e.date);
    added += 1;
  }

  for (const n of notes) {
    if (ids.has(n.id)) { skipped += 1; continue; }
    ids.add(n.id);
    noteStore.put({ text: n.text, createdAt: n.createdAt ?? now }, n.id);
    added += 1;
  }

  await new Promise((resolve, reject) => {
    t.oncomplete = () => resolve();
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
  return { added, skipped };
}
