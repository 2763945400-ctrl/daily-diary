import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/entry_store.dart';
import '../data/notification_service.dart';
import '../style.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final _textController = TextEditingController();
  Uint8List? _photo;
  Entry? _existing;

  @override
  void initState() {
    super.initState();
    _existing = EntryStore.get(EntryStore.todayKey());
    if (_existing != null) {
      _textController.text = _existing!.text;
      _photo = _existing!.photo;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
    final now = DateTime.now();
    final entry = Entry(
      date: EntryStore.todayKey(),
      text: _textController.text.trim(),
      photo: _photo,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (entry.isEmpty) return;
    await EntryStore.put(entry);
    await NotificationService.schedule(); // 今天记过了,当晚的提醒自动跳过
    setState(() => _existing = entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已记下今天 ✓'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final streak = EntryStore.streak();
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          Text(
            '${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}',
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
    );
  }
}
