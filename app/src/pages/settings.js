// 设置页。这一步只做设计稿 frame ③ 里的「数据」组和「隐私」组，外加版本号。
//
// 特意没做的两样（不是漏掉）：
//   提醒组 —— 归第 6 步，要 Capacitor 本地通知，且网页版根本给不了
//   提点意见 —— 等用户建好问卷给链接

import { INVALID_BACKUP, buildBackup, readBackup } from '../backup.js';
import { todayKey } from '../day.js';
import {
  allEntries, allNotes, clearAllData, counts, getSetting, importAll, setSetting,
} from '../db.js';
import { closeOverlays, openOverlay } from '../overlay.js';
import { IS_WEB } from '../platform.js';
import { toast } from '../toast.js';
import { APP_VERSION } from '../version.js';
import { DEFAULT_MINUTES } from './meditate.js';

const el = (id) => document.getElementById(id);

/** 清空 / 导入过之后，今天页缓存的那份内容就不作数了。由 main.js 接上重置。 */
let onDataChanged = () => {};

export async function activate() {
  const { entries, notes } = await counts();
  el('export-sub').textContent = `${entries} 条日记 · ${notes} 条碎片`;
  // 和静坐页共用同一个值：那边改了时长，这里进来就跟着变
  el('med-minutes').value = String(await getSetting('meditationMinutes', DEFAULT_MINUTES));
}

/* ── 导出 ─────────────────────────────────────────────────── */

async function exportBackup() {
  const [entries, notes] = await Promise.all([allEntries(), allNotes()]);
  if (entries.length === 0 && notes.length === 0) {
    toast('还没有任何记录，无需备份');
    return;
  }

  // 照片转 base64 和最后的 JSON.stringify 都是同步的大活，主线程会卡住 ——
  // 实测 100 张照片 / 85 MB 要 9.5 秒。不给提示的话用户以为点了没反应，会再点一次。
  // 时长写长一点，让它一直挂到下面的成功/失败提示把它顶掉。
  toast('正在导出…', { duration: 60_000 });
  await yieldOnce();

  try {
    // allEntries() 是新→旧；备份文件里按日期正序排，跟手写日记本一个方向，好翻。
    const data = await buildBackup({ entries: [...entries].reverse(), notes });
    download(`日记备份-${todayKey()}.json`, JSON.stringify(data));
    toast(`已导出 ${entries.length} 条日记、${notes.length} 条碎片`);
  } catch {
    // 不兜的话上面那条「正在导出…」会一直挂 60 秒，比报错还难受。
    toast('导出失败了，照片可能太多，删几张再试');
  }
}

/**
 * 让出一轮宏任务，好让「正在导出…」先画出来再开始卡主线程的活。
 * ⚠️ 别改成 requestAnimationFrame —— 标签页切到后台时它会一直不触发，
 *    导出就永远停在这一行了。MessageChannel 不受后台节流影响。
 */
function yieldOnce() {
  return new Promise((resolve) => {
    const ch = new MessageChannel();
    ch.port1.onmessage = () => resolve();
    ch.port2.postMessage(0);
  });
}

/**
 * 触发浏览器下载。
 * ⚠️ 这条路只在网页版通。iOS 的 WKWebView 里 <a download> 不工作，
 *    真机上要走 @capacitor/filesystem + share —— 那是第 6 步的活，这里先不装依赖。
 */
function download(filename, text) {
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  // 立刻 revoke 会让下载拿不到内容，等一会儿再还。
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/* ── 导入 ─────────────────────────────────────────────────── */

async function importBackup(event) {
  const file = event.target.files?.[0];
  event.target.value = '';           // 清掉，不然选同一个文件不会再触发 change
  if (!file) return;

  let parsed;
  try {
    // 解析和照片解码都必须在开事务之前做完（db.importAll 的注释说了为什么）。
    parsed = readBackup(await file.text());
  } catch {
    toast(INVALID_BACKUP);
    return;
  }

  try {
    const { added, skipped } = await importAll(parsed.entries, parsed.notes);
    // 文案跟 Flutter 版逐字对齐：日记和碎片合并计数，跳过 0 条时不显示后半句。
    toast(skipped
      ? `导入完成：新增 ${added} 条，跳过已有的 ${skipped} 条`
      : `导入完成：新增 ${added} 条`);
    await activate();
    await onDataChanged();
  } catch {
    // 写库失败不是「文件无效」，多半是存储空间不够，得说不一样的话。
    toast('导入没能写进去，可能是存储空间不够');
  }
}

/* ── 清空 ─────────────────────────────────────────────────── */

async function doClear() {
  closeOverlays();
  await clearAllData();              // 只清日记和碎片，不碰 settings
  await activate();
  await onDataChanged();
  toast('已清空');
}

/* ── 清除缓存（仅网页版） ─────────────────────────────────── */

/**
 * 清掉网页外壳本身的缓存（Service Worker 注册 + Cache Storage），然后重新加载。
 *
 * ⚠️ 一个字节都不碰 IndexedDB —— 日记、碎片、设置全在那里。
 *    磁贴的副标题就是在保证这件事，改文案时别把这层意思弄丢了。
 *
 * 用途是自救：新版本发了却一直卡在旧版本，或者缓存本身坏了打不开。
 */
async function clearCacheAndReload() {
  toast('正在清除缓存…', { duration: 60_000 });
  try {
    const regs = await (navigator.serviceWorker?.getRegistrations() ?? []);
    await Promise.all(regs.map((reg) => reg.unregister()));
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
  } catch {
    // 清不干净也照样重载：至少浏览器那层普通 HTTP 缓存有机会刷新，
    // 而且这个按钮存在的意义就是「卡住了给条出路」，不该在这里卡第二次。
  }
  location.reload();
}

/* ── 接线 ─────────────────────────────────────────────────── */

export function init(handler) {
  onDataChanged = handler;
  el('app-version').textContent = `每日一记 v${APP_VERSION}`;

  el('med-minutes').addEventListener('change', (event) => {
    setSetting('meditationMinutes', Number(event.target.value));
  });

  el('export-backup').addEventListener('click', exportBackup);
  el('import-backup').addEventListener('click', () => el('import-input').click());
  el('import-input').addEventListener('change', importBackup);

  // 原生壳里资源本来就在本地，没有 Service Worker 也没有可清的缓存（规格第八节：仅网页版）
  if (IS_WEB) {
    el('web-label').hidden = false;
    el('web-card').hidden = false;
    el('clear-cache').addEventListener('click', clearCacheAndReload);
  }

  el('clear-all').addEventListener('click', () => openOverlay('confirm-clear'));
  el('confirm-cancel').addEventListener('click', closeOverlays);
  el('confirm-ok').addEventListener('click', doClear);
}
