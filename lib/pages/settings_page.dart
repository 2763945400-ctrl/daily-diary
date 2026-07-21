import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/entry_store.dart';
import '../data/note_store.dart';
import '../data/notification_service.dart';
import '../data/settings_store.dart';
import '../style.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── 每日提醒 ──────────────────────────────────────────

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        _toast('系统未允许通知。请到 iPhone 的「设置 → 通知 → 每日一记」里打开');
        return;
      }
    }
    await SettingsStore.setReminderEnabled(value);
    await NotificationService.schedule();
    setState(() {});
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: SettingsStore.reminderHour,
        minute: SettingsStore.reminderMinute,
      ),
    );
    if (picked == null) return;
    await SettingsStore.setReminderTime(picked.hour, picked.minute);
    await NotificationService.schedule();
    setState(() {});
  }

  String get _reminderTimeLabel =>
      '${SettingsStore.reminderHour.toString().padLeft(2, '0')}:'
      '${SettingsStore.reminderMinute.toString().padLeft(2, '0')}';

  // ── 导出 ──────────────────────────────────────────────

  Future<void> _export() async {
    final entries = EntryStore.all();
    final notes = NoteStore.all();
    if (entries.isEmpty && notes.isEmpty) {
      _toast('还没有任何记录，无需备份');
      return;
    }
    final data = {
      'app': 'daily_diary',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'entries': [
        for (final e in entries)
          {
            'date': e.date,
            'text': e.text,
            'photo': e.photo == null ? null : base64Encode(e.photo!),
            'createdAt': e.createdAt.millisecondsSinceEpoch,
            'updatedAt': e.updatedAt.millisecondsSinceEpoch,
          },
      ],
      'notes': [
        for (final n in notes)
          {
            'id': n.id,
            'text': n.text,
            'createdAt': n.createdAt.millisecondsSinceEpoch,
          },
      ],
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final name = '日记备份-${EntryStore.todayKey()}.json';
    await FilePicker.saveFile(fileName: name, bytes: bytes);
    _toast('已导出 ${entries.length} 条日记、${notes.length} 条碎片');
  }

  // ── 导入 ──────────────────────────────────────────────

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.firstOrNull?.bytes;
    if (bytes == null) return;

    int added = 0, skipped = 0;
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['app'] != 'daily_diary') throw const FormatException();
      for (final raw in data['entries'] as List) {
        final m = raw as Map<String, dynamic>;
        final date = m['date'] as String;
        if (EntryStore.get(date) != null) {
          skipped++;
          continue;
        }
        await EntryStore.put(Entry(
          date: date,
          text: (m['text'] as String?) ?? '',
          photo: m['photo'] == null ? null : base64Decode(m['photo'] as String),
          createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
        ));
        added++;
      }
      // version 2 起有碎片；旧版备份没有 notes 字段，跳过即可
      for (final raw in (data['notes'] as List?) ?? const []) {
        final m = raw as Map<String, dynamic>;
        final id = m['id'] as String;
        if (NoteStore.has(id)) {
          skipped++;
          continue;
        }
        await NoteStore.put(Note(
          id: id,
          text: (m['text'] as String?) ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        ));
        added++;
      }
    } catch (_) {
      _toast('这个文件不是有效的日记备份');
      return;
    }
    setState(() {});
    _toast('导入完成：新增 $added 条${skipped > 0 ? '，跳过已有的 $skipped 条' : ''}');
  }

  // ── 清空 ──────────────────────────────────────────────

  Future<void> _clearAll() async {
    final count = EntryStore.count;
    final noteCount = NoteStore.count;
    if (count == 0 && noteCount == 0) {
      _toast('没有可清空的记录');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: Text(
            '将永久删除全部 $count 条日记和 $noteCount 条碎片（含照片），无法恢复。\n建议先导出备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await EntryStore.clearAll();
    await NoteStore.clearAll();
    setState(() {});
    _toast('已清空全部数据');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          Text(
            '设置',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          if (!kIsWeb) ...[
            _sectionLabel('提醒'),
            _card([
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('每日提醒'),
                value: SettingsStore.reminderEnabled,
                onChanged: _toggleReminder,
              ),
              if (SettingsStore.reminderEnabled) ...[
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('提醒时间'),
                  subtitle: const Text('当天已记录时自动跳过',
                      style: TextStyle(fontSize: 12)),
                  trailing: Text(_reminderTimeLabel,
                      style: const TextStyle(fontSize: 16)),
                  onTap: _pickReminderTime,
                ),
              ],
            ]),
            const SizedBox(height: 24),
          ],
          _sectionLabel('数据'),
          _card([
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导出备份'),
              subtitle: Text(
                  '${EntryStore.count} 条日记 · ${NoteStore.count} 条碎片',
                  style: const TextStyle(fontSize: 12)),
              onTap: _export,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导入备份'),
              subtitle: const Text('只补充缺少的日期，不覆盖已有记录',
                  style: TextStyle(fontSize: 12)),
              onTap: _import,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('清空全部数据', style: TextStyle(color: Colors.red)),
              onTap: _clearAll,
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel('隐私'),
          _card([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '你的全部记录（文字和照片）只保存在这台设备上。\n'
                '没有服务器，没有账号，没有人能看到你写了什么。\n'
                '也因此：换设备前请先「导出备份」，数据不会自动跟着你走。',
                style: TextStyle(fontSize: 13, height: 1.7, color: scheme.outline),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 13, color: hintColor)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: cardFill,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}
