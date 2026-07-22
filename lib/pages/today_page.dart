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
    super.dispose();
  }

  /// 记下一条碎片：轻触感反馈，id 用毫秒时间戳。
  Future<void> _saveNote(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    await NoteStore.put(Note(
      id: now.millisecondsSinceEpoch.toString(),
      text: text,
      createdAt: now,
    ));
  }

  /// 右下角悬浮 ＋ 打开的捕捉浮层：记下即关，回到主页。
  Future<void> _openCaptureSheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            // 跟随键盘上移
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: hintColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: '此刻的想法，随手记下',
                  hintStyle: const TextStyle(color: hintColor),
                  filled: true,
                  fillColor: cardFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () {
                    _saveNote(controller.text);
                    Navigator.of(sheetContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('记下'),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
  }

  /// 右上角「待整理 N」角标打开的整理浮层:逐条并入/删除,清空后自动关闭。
  Future<void> _openOrganizeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: ValueListenableBuilder(
              valueListenable: NoteStore.listenable,
              builder: (context, _, _) {
                final notes = NoteStore.todays();
                if (notes.isEmpty) {
                  // 整理完了:浮层自动关闭,主页角标也随之消失
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  });
                  return const SizedBox(height: 120);
                }
                final scheme = Theme.of(context).colorScheme;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: hintColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('待整理',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text('${notes.length} 条',
                            style: TextStyle(
                                fontSize: 12, color: scheme.outline)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close, size: 20),
                          color: scheme.outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [for (final n in notes) _organizeTile(n)],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 整理浮层里的一条碎片:时间 + 全文(不截断),下方「并入今天」「删除」。
  Widget _organizeTile(Note note) {
    final scheme = Theme.of(context).colorScheme;
    final time =
        '${note.createdAt.hour.toString().padLeft(2, '0')}:'
        '${note.createdAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time,
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
                const SizedBox(height: 4),
                Text(note.text),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () async {
                  // 并入正文草稿,同时把它从待整理里清掉
                  _mergeNote(note);
                  await NoteStore.delete(note.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已并入今天'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Icons.arrow_downward,
                    size: 16, color: scheme.primary),
                label: Text('并入今天',
                    style: TextStyle(color: scheme.primary)),
              ),
              TextButton(
                onPressed: () => _deleteNote(note),
                style: TextButton.styleFrom(foregroundColor: scheme.outline),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 把碎片并入日记草稿：正文非空则换行追加，不加任何标记。
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
        child: Stack(
          children: [
            ListView(
          // 列表下滑时收起键盘
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // 底部多留白,悬浮 ＋ 不会压住「记下今天」按钮
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 96),
          children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${day.month}月${day.day}日 ${weekdays[day.weekday - 1]}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              // 待整理角标:有待整理的碎片才出现,点开整理浮层
              ValueListenableBuilder(
                valueListenable: NoteStore.listenable,
                builder: (context, _, _) {
                  final count = NoteStore.todays().length;
                  if (count == 0) return const SizedBox.shrink();
                  return InkWell(
                    onTap: _openOrganizeSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cardFill,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 16, color: scheme.outline),
                          const SizedBox(width: 4),
                          Text('待整理 $count',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.outline)),
                          Icon(Icons.chevron_right,
                              size: 16, color: scheme.outline),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            streak > 0 ? '已连续记录 $streak 天' : '记下第一天，从今天开始',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          // 写作卡片：文字 + 照片合成一张卡，照片是卡内的轻 affordance（对齐设计稿）
          Container(
            decoration: BoxDecoration(
              color: cardFill,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _textController,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: '今天过得怎么样？',
                    hintStyle: TextStyle(color: hintColor),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
                const SizedBox(height: 12),
                _photo == null
                    ? InkWell(
                        onTap: _pickPhoto,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 20, color: scheme.outline),
                              const SizedBox(width: 8),
                              Text('添加照片',
                                  style: TextStyle(color: scheme.outline)),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 静坐入口：位于写作区下方（对齐设计稿）；全屏页，返回后无状态牵连
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
            // 右下角悬浮 ＋：打开捕捉浮层；浮在内容之上、底部导航栏之上
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                onPressed: _openCaptureSheet,
                shape: const CircleBorder(),
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
