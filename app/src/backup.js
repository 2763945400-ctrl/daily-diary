// 导出 / 导入备份的纯逻辑。不碰 IndexedDB、不碰 DOM，好单测。
//
// ⚠️ 这里的字段名和结构是**新旧两版互通的唯一桥梁**（规格第四节「不许动清单」）。
//    一个字母都不能改。逐条对着 lib/pages/settings_page.dart 核过：
//    - photo 是裸 base64：没有 data: 前缀、不带 MIME
//    - text 可能是 null（当空串）
//    - notes 整个字段可能缺失（version 1 的老备份，当空数组）
//
// version: 2 是**数据格式版本**，跟应用版本号（v2.0.0）没有关系，永远是 2。

import { nowIso } from './day.js';

const APP_TAG = 'daily_diary';
const FORMAT_VERSION = 2;
const DATE_KEY = /^\d{4}-\d{2}-\d{2}$/;

/** 出错一律报这一句 —— 用户不需要知道是第几行 JSON 坏了。 */
export const INVALID_BACKUP = '这个文件不是有效的日记备份';

const invalid = () => new Error(INVALID_BACKUP);

/* ── base64 ⇄ Blob ───────────────────────────────────────── */

async function blobToBase64(blob) {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  // 一次 32 KB。整个数组直接 apply 进去，几 MB 的照片会爆调用栈。
  const CHUNK = 0x8000;
  let binary = '';
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function base64ToBlob(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new Blob([bytes], { type: 'image/jpeg' });
}

/* ── 导出 ─────────────────────────────────────────────────── */

/**
 * 攒出可以直接 JSON.stringify 的备份对象。
 * entries 传进来时照片是 Blob，这里转成 base64 —— 库里存 Blob、只有导出才转。
 */
export async function buildBackup({ entries, notes }) {
  return {
    app: APP_TAG,
    version: FORMAT_VERSION,
    exportedAt: nowIso(),
    entries: await Promise.all(entries.map(async (e) => ({
      date: e.date,
      text: e.text ?? '',
      photo: e.photo ? await blobToBase64(e.photo) : null,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
    }))),
    notes: notes.map((n) => ({ id: n.id, text: n.text ?? '', createdAt: n.createdAt })),
  };
}

/* ── 导入 ─────────────────────────────────────────────────── */

/** 是数字就用，不是就给 null —— 由写库那边补当前时间。 */
const toMs = (v) => (Number.isFinite(Number(v)) && v !== null && v !== '' ? Number(v) : null);

/**
 * 解析备份文件正文，产出可以直接写库的形状（照片已经是 Blob）。
 * 坏文件一律抛 INVALID_BACKUP，不做「跳过坏行继续导」——
 * 半截导入比直接报错更糟：用户会以为导成功了。
 */
export function readBackup(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw invalid();
  }

  if (!data || typeof data !== 'object' || Array.isArray(data)) throw invalid();
  if (data.app !== APP_TAG) throw invalid();
  if (!Array.isArray(data.entries)) throw invalid();
  // notes 缺失是合法的：version 1 的老备份没有碎片这个概念。
  const rawNotes = data.notes ?? [];
  if (!Array.isArray(rawNotes)) throw invalid();

  const entries = data.entries.map((e) => {
    if (!e || typeof e !== 'object') throw invalid();
    if (typeof e.date !== 'string' || !DATE_KEY.test(e.date)) throw invalid();
    let photo = null;
    if (e.photo) {
      try {
        photo = base64ToBlob(e.photo);
      } catch {
        throw invalid();                       // 照片解不开就是文件坏了
      }
    }
    return {
      date: e.date,
      text: e.text ?? '',
      photo,
      createdAt: toMs(e.createdAt),
      updatedAt: toMs(e.updatedAt),
    };
  });

  const notes = rawNotes.map((n) => {
    if (!n || typeof n !== 'object') throw invalid();
    const id = String(n.id ?? '');
    if (!id) throw invalid();
    return { id, text: n.text ?? '', createdAt: toMs(n.createdAt) };
  });

  return { entries, notes };
}
