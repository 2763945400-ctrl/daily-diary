import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/entry_store.dart';
import '../data/note_store.dart';
import '../data/notification_service.dart';
import '../style.dart';
import 'meditate_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _noteController = TextEditingController(); // 碎片速记条
  final _noteFocus = FocusNode();
  Uint8List? _photo;
  Entry? _existing;
  String _loadedDate = ''; // 本页面当前绑定的日期,编辑和保存都以它为准

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _load() {
    _loadedDate = EntryStore.todayKey();
    _existing = EntryStore.get(_loadedDate);
    _textController.text = _existing?.text ?? '';
    _photo = _existing?.photo;
  }

  /// 有没有还没保存的改动。
  bool get _isDirty =>
      _textController.text.trim() != (_existing?.text ?? '') ||
      !identical(_photo, _existing?.photo);

  /// 日期翻篇了且没有未保存的草稿 → 换到新的一天。
  /// 有草稿时不换:半夜写的日记属于开始写的那一天。
  void _maybeRollover() {
    if (_loadedDate == EntryStore.todayKey() || _isDirty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _loadedDate != EntryStore.todayKey() && !_isDirty) {
        setState(_load);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {}); // 从后台回来时触发重画,让 _maybeRollover 检查日期
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// 记下一条碎片：轻触感反馈，清空输入框但键盘不收起，便于连续记。
  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    await NoteStore.put(Note(
      id: now.millisecondsSinceEpoch.toString(),
      text: text,
      createdAt: now,
    ));
    _noteController.clear();
    _noteFocus.requestFocus();
  }

  /// 把碎片并入日记草稿：前面有内容则换行分隔；碎片保留，由用户自己决定何时删。
  void _mergeNote(Note note) {
    final current = _textController.text;
    _textController.text =
        current.trim().isEmpty ? note.text : '$current\n${note.text}';
    setState(() {}); // 刷新「记下今天」的脏状态判断
  }

  /// 删除碎片：无确认弹窗直接删，SnackBar 给「撤销」。
  Future<void> _deleteNote(Note note) async {
    await NoteStore.delete(note.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('碎片已删除'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => NoteStore.put(note),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _photo = bytes);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus(); // 保存时收起键盘
    final now = DateTime.now();
    final entry = Entry(
      date: _loadedDate, // 存到页面绑定的日期,跨午夜也不会记错天
      text: _textController.text.trim(),
      photo: _photo,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (entry.isEmpty) return;
    await EntryStore.put(entry);
    await NotificationService.schedule(); // 今天记过了,当晚的提醒自动跳过
    if (!mounted) return;
    setState(() => _existing = entry);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已记下今天 ✓'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeRollover();
    final day = DateTime.parse(_loadedDate);
    final streak = EntryStore.streak();
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 点输入框以外的空白处收起键盘
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SafeArea(
        child: ListView(
          // 列表下滑时收起键盘
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
          Text(
            '${day.month}月${day.day}日 ${weekdays[day.weekday - 1]}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            streak > 0 ? '已连续记录 $streak 天' : '记下第一天，从今天开始',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          // 碎片速记条：想到什么先卸下，不打断写日记
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _noteController,
                  focusNode: _noteFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveNote(),
                  decoration: InputDecoration(
                    hintText: '此刻的想法，随手记下',
                    hintStyle: const TextStyle(color: hintColor),
                    filled: true,
                    fillColor: cardFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FilledButton.tonal(
                  onPressed: _saveNote,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('记下'),
                ),
              ),
            ],
          ),
          // 今天的碎片：「并入」追加进日记草稿，「删除」可撤销
          ValueListenableBuilder(
            valueListenable: NoteStore.listenable,
            builder: (context, _, _) {
              final notes = NoteStore.todays();
              if (notes.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [for (final n in notes) _noteTile(n, scheme)],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // 静坐入口：全屏页，返回后无状态牵连
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MeditatePage()),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cardFill,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.self_improvement, color: scheme.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('先静坐片刻',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('清空思绪，再写今天',
                            style: TextStyle(
                                fontSize: 12, color: scheme.outline)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.outline),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 文字卡片
          TextField(
            controller: _textController,
            minLines: 5,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: '今天过得怎么样？',
              hintStyle: const TextStyle(color: hintColor),
              filled: true,
              fillColor: cardFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 16),
          // 照片卡片
          _photo == null
              ? InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 96,
                    decoration: BoxDecoration(
                      color: cardFill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: scheme.outline),
                        const SizedBox(width: 8),
                        Text('添加照片', style: TextStyle(color: scheme.outline)),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _photo!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filledTonal(
                        onPressed: () => setState(() => _photo = null),
                        icon: const Icon(Icons.close, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              _existing == null ? '记下今天' : '更新今天',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// 一条碎片：时间 + 文本，右侧「并入」「删除」两个小操作。
  Widget _noteTile(Note note, ColorScheme scheme) {
    final time =
        '${note.createdAt.hour.toString().padLeft(2, '0')}:'
        '${note.createdAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time,
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
                const SizedBox(height: 2),
                Text(note.text),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _mergeNote(note),
            child: const Text('并入'),
          ),
          TextButton(
            onPressed: () => _deleteNote(note),
            style: TextButton.styleFrom(foregroundColor: scheme.outline),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
