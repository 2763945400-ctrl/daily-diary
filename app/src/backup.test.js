import { describe, expect, it } from 'vitest';
import { INVALID_BACKUP, buildBackup, readBackup } from './backup.js';

const bytes = (b) => new Blob([new Uint8Array(b)], { type: 'image/jpeg' });
const readBytes = async (blob) => [...new Uint8Array(await blob.arrayBuffer())];

const oneEntry = (over = {}) => ({
  date: '2026-08-05', text: '今天很好', photo: null,
  createdAt: 1785523001000, updatedAt: 1785523001000, ...over,
});

/** 把对象变成文件正文再喂给 readBackup，跟真实链路一致。 */
const roundTrip = (obj) => readBackup(JSON.stringify(obj));

const validFile = (over = {}) => ({
  app: 'daily_diary', version: 2, exportedAt: '2026-08-05T12:00:00.000Z',
  entries: [oneEntry()], notes: [{ id: '1785523001000', text: '碎片', createdAt: 1785523001000 }],
  ...over,
});

describe('buildBackup：字段名一个字母都不能变', () => {
  it('顶层是 app / version / exportedAt / entries / notes', async () => {
    const out = await buildBackup({ entries: [], notes: [] });
    expect(Object.keys(out)).toEqual(['app', 'version', 'exportedAt', 'entries', 'notes']);
    expect(out.app).toBe('daily_diary');
    expect(out.version).toBe(2);
  });

  it('version 恒为 2 —— 那是数据格式版本，不是应用版本号', async () => {
    const out = await buildBackup({ entries: [oneEntry()], notes: [] });
    expect(out.version).toBe(2);
  });

  it('exportedAt 是 ISO8601 字符串', async () => {
    const { exportedAt } = await buildBackup({ entries: [], notes: [] });
    expect(exportedAt).toMatch(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/);
  });

  it('日记条目是 date / text / photo / createdAt / updatedAt 五个字段', async () => {
    const out = await buildBackup({ entries: [oneEntry()], notes: [] });
    expect(Object.keys(out.entries[0]))
      .toEqual(['date', 'text', 'photo', 'createdAt', 'updatedAt']);
  });

  it('碎片条目是 id / text / createdAt 三个字段', async () => {
    const out = await buildBackup({
      entries: [], notes: [{ id: '17855', text: '碎片', createdAt: 17855 }],
    });
    expect(Object.keys(out.notes[0])).toEqual(['id', 'text', 'createdAt']);
  });

  it('没有照片时 photo 是 null，不是空串', async () => {
    const out = await buildBackup({ entries: [oneEntry()], notes: [] });
    expect(out.entries[0].photo).toBeNull();
  });

  it('照片转成裸 base64：没有 data: 前缀、不带 MIME', async () => {
    const out = await buildBackup({
      entries: [oneEntry({ photo: bytes([255, 216, 255, 224]) })], notes: [],
    });
    expect(out.entries[0].photo).toBe('/9j/4A==');
    expect(out.entries[0].photo).not.toContain('data:');
    expect(out.entries[0].photo).not.toContain('image/jpeg');
  });

  it('text 是 null 时导出成空串', async () => {
    const out = await buildBackup({ entries: [oneEntry({ text: null })], notes: [] });
    expect(out.entries[0].text).toBe('');
  });
});

describe('照片 round-trip：导出再导入，字节一模一样', () => {
  it('小图', async () => {
    const raw = [255, 216, 255, 224, 0, 16, 74, 70, 73, 70];
    const file = await buildBackup({ entries: [oneEntry({ photo: bytes(raw) })], notes: [] });
    const { entries } = roundTrip(file);
    expect(await readBytes(entries[0].photo)).toEqual(raw);
    expect(entries[0].photo.type).toBe('image/jpeg');
  });

  it('跨过分块边界的大图（80 KB，比 32 KB 的分块大）', async () => {
    const raw = Array.from({ length: 80 * 1024 }, (_, i) => i % 256);
    const file = await buildBackup({ entries: [oneEntry({ photo: bytes(raw) })], notes: [] });
    const { entries } = roundTrip(file);
    expect(await readBytes(entries[0].photo)).toEqual(raw);
  });
});

describe('readBackup：正常文件', () => {
  it('日记和碎片都读出来', () => {
    const { entries, notes } = roundTrip(validFile());
    expect(entries).toHaveLength(1);
    expect(entries[0].date).toBe('2026-08-05');
    expect(entries[0].text).toBe('今天很好');
    expect(notes).toHaveLength(1);
    expect(notes[0].id).toBe('1785523001000');
  });

  it('时间戳原样保留，不被改写', () => {
    const { entries } = roundTrip(validFile());
    expect(entries[0].createdAt).toBe(1785523001000);
    expect(entries[0].updatedAt).toBe(1785523001000);
  });

  it('text 是 null 的当空串（Flutter 版会写 null）', () => {
    const { entries } = roundTrip(validFile({ entries: [oneEntry({ text: null })] }));
    expect(entries[0].text).toBe('');
  });

  it('version 1 的老备份没有 notes 字段，当空数组', () => {
    const old = { app: 'daily_diary', version: 1, entries: [oneEntry()] };
    expect(roundTrip(old).notes).toEqual([]);
  });

  it('notes 显式写成 null 也当空数组', () => {
    expect(roundTrip(validFile({ notes: null })).notes).toEqual([]);
  });

  it('entries 是空数组时读出空数组，不报错', () => {
    expect(roundTrip(validFile({ entries: [] })).entries).toEqual([]);
  });

  it('碎片 id 是数字时转成字符串 —— 主键必须是字符串', () => {
    const f = validFile({ notes: [{ id: 1785523001000, text: 'x', createdAt: 1 }] });
    expect(roundTrip(f).notes[0].id).toBe('1785523001000');
  });

  it('时间戳缺失时给 null，留给写库那边补', () => {
    const f = validFile({ entries: [oneEntry({ createdAt: undefined })] });
    expect(roundTrip(f).entries[0].createdAt).toBeNull();
  });
});

describe('readBackup：坏文件一律报同一句话', () => {
  const rejects = (text) => expect(() => readBackup(text)).toThrow(INVALID_BACKUP);

  it('压根不是 JSON', () => rejects('这不是 json'));
  it('空文件', () => rejects(''));
  it('JSON 是 null', () => rejects('null'));
  it('JSON 是数组不是对象', () => rejects('[]'));
  it('JSON 是个数字', () => rejects('42'));

  it('app 字段不对 —— 别的 App 的备份', () => {
    rejects(JSON.stringify(validFile({ app: 'other_app' })));
  });

  it('app 字段缺失', () => {
    const f = validFile();
    delete f.app;
    rejects(JSON.stringify(f));
  });

  it('entries 字段缺失', () => {
    const f = validFile();
    delete f.entries;
    rejects(JSON.stringify(f));
  });

  it('entries 不是数组', () => rejects(JSON.stringify(validFile({ entries: {} }))));
  it('notes 不是数组', () => rejects(JSON.stringify(validFile({ notes: {} }))));

  it('日期不是 yyyy-MM-dd', () => {
    rejects(JSON.stringify(validFile({ entries: [oneEntry({ date: '2026/8/5' })] })));
  });

  it('日期字段缺失', () => {
    rejects(JSON.stringify(validFile({ entries: [oneEntry({ date: undefined })] })));
  });

  it('照片是解不开的 base64', () => {
    rejects(JSON.stringify(validFile({ entries: [oneEntry({ photo: '这不是base64!!' })] })));
  });

  it('碎片没有 id', () => {
    rejects(JSON.stringify(validFile({ notes: [{ text: 'x', createdAt: 1 }] })));
  });
});
