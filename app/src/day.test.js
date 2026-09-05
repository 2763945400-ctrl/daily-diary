import { describe, expect, it } from 'vitest';
import {
  formatTime, formatTitle, logicalKey,
  monthGrid, monthLabel, monthOf, sameMonth, shiftMonth,
} from './day.js';

// new Date(年, 月-1, 日, 时, 分) 走本地时区，和 logicalKey 的取值方式一致。
const at = (y, m, d, h, min = 0) => new Date(y, m - 1, d, h, min);

describe('logicalKey：凌晨 2 点日界', () => {
  it('白天照常算当天', () => {
    expect(logicalKey(at(2026, 8, 5, 14, 30))).toBe('2026-08-05');
  });

  it('23:59 仍算当天', () => {
    expect(logicalKey(at(2026, 8, 5, 23, 59))).toBe('2026-08-05');
  });

  it('00:00 算前一天', () => {
    expect(logicalKey(at(2026, 8, 5, 0, 0))).toBe('2026-08-04');
  });

  it('01:59 算前一天（日界前最后一分钟）', () => {
    expect(logicalKey(at(2026, 8, 5, 1, 59))).toBe('2026-08-04');
  });

  it('02:00 整算当天（日界这一刻）', () => {
    expect(logicalKey(at(2026, 8, 5, 2, 0))).toBe('2026-08-05');
  });
});

describe('logicalKey：边界回退', () => {
  it('跨月：8/1 凌晨 1 点 → 7/31', () => {
    expect(logicalKey(at(2026, 8, 1, 1, 0))).toBe('2026-07-31');
  });

  it('跨年：1/1 凌晨 1 点 → 前一年 12/31', () => {
    expect(logicalKey(at(2026, 1, 1, 1, 0))).toBe('2025-12-31');
  });

  it('闰年：2028/3/1 凌晨 1 点 → 2/29', () => {
    expect(logicalKey(at(2028, 3, 1, 1, 0))).toBe('2028-02-29');
  });

  it('平年：2027/3/1 凌晨 1 点 → 2/28', () => {
    expect(logicalKey(at(2027, 3, 1, 1, 0))).toBe('2027-02-28');
  });
});

describe('logicalKey：格式', () => {
  it('月和日都补零到两位', () => {
    expect(logicalKey(at(2026, 1, 5, 12, 0))).toBe('2026-01-05');
  });

  it('不传参数时用此刻，格式合法', () => {
    expect(logicalKey()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

describe('formatTitle', () => {
  it('排版成「8月5日 周三」，月和日不补零', () => {
    expect(formatTitle('2026-08-05')).toBe('8月5日 周三');
  });

  it('一月一日', () => {
    expect(formatTitle('2026-01-01')).toBe('1月1日 周四');
  });

  it('周日显示「周日」不是「周0」', () => {
    expect(formatTitle('2026-08-02')).toBe('8月2日 周日');
  });
});

describe('formatTime', () => {
  it('时和分都补零到两位', () => {
    expect(formatTime(at(2026, 8, 5, 9, 5).getTime())).toBe('09:05');
  });

  it('午夜是 00:00 不是 24:00', () => {
    expect(formatTime(at(2026, 8, 5, 0, 0).getTime())).toBe('00:00');
  });
});

describe('monthOf / shiftMonth / sameMonth', () => {
  it('从日期键取出月份', () => {
    expect(monthOf('2026-08-05')).toEqual({ year: 2026, month: 8 });
  });

  it('月份不补零地取整数，01 月是 1 不是 "01"', () => {
    expect(monthOf('2026-01-31')).toEqual({ year: 2026, month: 1 });
  });

  it('往后翻一个月', () => {
    expect(shiftMonth({ year: 2026, month: 8 }, 1)).toEqual({ year: 2026, month: 9 });
  });

  it('12 月往后翻进到次年 1 月', () => {
    expect(shiftMonth({ year: 2026, month: 12 }, 1)).toEqual({ year: 2027, month: 1 });
  });

  it('1 月往前翻退到上一年 12 月', () => {
    expect(shiftMonth({ year: 2026, month: 1 }, -1)).toEqual({ year: 2025, month: 12 });
  });

  it('连翻 12 个月正好回到同月的下一年', () => {
    let m = { year: 2026, month: 3 };
    for (let i = 0; i < 12; i += 1) m = shiftMonth(m, 1);
    expect(m).toEqual({ year: 2027, month: 3 });
  });

  it('sameMonth 认年份，2025-08 和 2026-08 不是同一个月', () => {
    expect(sameMonth({ year: 2026, month: 8 }, { year: 2026, month: 8 })).toBe(true);
    expect(sameMonth({ year: 2025, month: 8 }, { year: 2026, month: 8 })).toBe(false);
  });
});

describe('monthLabel', () => {
  it('排版成「2026年8月」，月份不补零', () => {
    expect(monthLabel({ year: 2026, month: 8 })).toBe('2026年8月');
  });
});

describe('monthGrid：周一排第一列', () => {
  it('2026 年 8 月 1 号是周六，前面垫 5 个空格子', () => {
    // 这个数字和设计稿 screens/index.html 回顾页那句注释是对上的。
    expect(monthGrid({ year: 2026, month: 8 }).blanks).toBe(5);
  });

  it('1 号正好是周一时不垫空格子', () => {
    expect(monthGrid({ year: 2026, month: 6 }).blanks).toBe(0);
  });

  it('1 号是周日时垫 6 个 —— 周日排最后一列', () => {
    expect(monthGrid({ year: 2026, month: 2 }).blanks).toBe(6);
  });

  it('31 天的月份给出 31 格，日期键首尾都补零', () => {
    const { days } = monthGrid({ year: 2026, month: 8 });
    expect(days).toHaveLength(31);
    expect(days[0]).toEqual({ key: '2026-08-01', day: 1 });
    expect(days[30]).toEqual({ key: '2026-08-31', day: 31 });
  });

  it('号数是数字且不补零 —— 日历格子直接拿它显示', () => {
    const { days } = monthGrid({ year: 2026, month: 8 });
    expect(days[8]).toEqual({ key: '2026-08-09', day: 9 });
  });

  it('30 天的月份不多给一天', () => {
    expect(monthGrid({ year: 2026, month: 4 }).days).toHaveLength(30);
  });

  it('平年 2 月 28 天', () => {
    expect(monthGrid({ year: 2026, month: 2 }).days).toHaveLength(28);
  });

  it('闰年 2 月 29 天', () => {
    expect(monthGrid({ year: 2024, month: 2 }).days).toHaveLength(29);
  });

  it('整百年不是闰年（1900 年 2 月 28 天）', () => {
    expect(monthGrid({ year: 1900, month: 2 }).days).toHaveLength(28);
  });

  it('400 的倍数是闰年（2000 年 2 月 29 天）', () => {
    expect(monthGrid({ year: 2000, month: 2 }).days).toHaveLength(29);
  });

  it('格子里的日期键喂回 logicalKey 的输出格式一致', () => {
    const { days } = monthGrid({ year: 2026, month: 1 });
    expect(days[0].key).toBe(logicalKey(new Date(2026, 0, 1, 12)));
  });
});
