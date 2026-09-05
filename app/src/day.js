// 全应用「现在算哪一天」的唯一真源。
// 凌晨 0:00–1:59 写的东西归到前一天，02:00 起才算新一天。
//
// ⚠️ 严禁在别处另写日期计算（规格第七节）。Flutter 版就是因为这段逻辑
//    散在 4 个文件里，各写各的，漂移出过 bug。要算日期一律 import 这里。

export const DAY_START_HOUR = 2;

const pad = (n) => String(n).padStart(2, '0');

/**
 * 把一个时刻换算成它归属的逻辑日期键 'yyyy-MM-dd'。
 * 用本地时间取年月日 —— 日界是用户感受上的「今天」，不是 UTC 的。
 */
export function logicalKey(t = new Date()) {
  const d = new Date(t.getTime() - DAY_START_HOUR * 3600 * 1000);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** 此刻的逻辑日期键。 */
export function todayKey() {
  return logicalKey();
}

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];

/**
 * 把日期键排版成「8月5日 周三」。
 * 放在这里是因为整个应用只允许这个文件碰 Date 的年月日 —— 别处要显示日期就调它。
 */
export function formatTitle(key) {
  const [y, m, d] = key.split('-').map(Number);
  return `${m}月${d}日 周${WEEKDAYS[new Date(y, m - 1, d).getDay()]}`;
}

/** 把毫秒时间戳排版成「09:41」。随手记列表显示记录时刻用。 */
export function formatTime(ms) {
  const t = new Date(ms);
  return `${pad(t.getHours())}:${pad(t.getMinutes())}`;
}

/* ── 月份与日历 ───────────────────────────────────────────
   回顾页的月历要算「这个月有几天」「1 号是周几」，都得碰 Date 的年月日，
   所以一并收在这里。月份对象统一用 { year, month }，month 是 1–12
   （不是 Date 那个 0–11 的月，免得到处 ±1 出错）。
   ---------------------------------------------------------- */

/** 日期键 'yyyy-MM-dd' 所属的月份。 */
export function monthOf(key) {
  const [year, month] = key.split('-').map(Number);
  return { year, month };
}

/** 此刻所属的月份（走逻辑日期，凌晨 1 点还算前一天那个月）。 */
export function thisMonth() {
  return monthOf(todayKey());
}

/** 前后翻月。delta 为 -1 / +1，跨年自己进位。 */
export function shiftMonth({ year, month }, delta) {
  const n = year * 12 + (month - 1) + delta;
  return { year: Math.floor(n / 12), month: (n % 12) + 1 };
}

export function sameMonth(a, b) {
  return a.year === b.year && a.month === b.month;
}

/** 排版成「2026年8月」。 */
export function monthLabel({ year, month }) {
  return `${year}年${month}月`;
}

/**
 * 一个月的日历网格。
 * blanks = 1 号前面要垫几个空格子（**周一排第一列**，跟设计稿的「一二三四五六日」一致）；
 * days = 这个月每一天的 { key 日期键, day 号数 }，从 1 号到月末。
 *        号数一并给出来，是为了让别处不用去切 'yyyy-MM-dd' 这个字符串 ——
 *        日期键长什么样只有这个文件知道。
 */
export function monthGrid({ year, month }) {
  // new Date(y, m, 0) 是「上个月的第 0 天」= 这个月最后一天，闰年 2 月也对。
  const total = new Date(year, month, 0).getDate();
  // getDay() 是 0=周日…6=周六；+6 再取模把周一挪到 0。
  const blanks = (new Date(year, month - 1, 1).getDay() + 6) % 7;
  const days = Array.from({ length: total }, (_, i) => ({
    key: `${year}-${pad(month)}-${pad(i + 1)}`,
    day: i + 1,
  }));
  return { blanks, days };
}

/** 导出备份的 exportedAt 用。放这儿是为了不让 toISOString 漏到别的文件去。 */
export function nowIso() {
  return new Date().toISOString();
}
