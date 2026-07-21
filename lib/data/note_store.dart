import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 一条碎片：随时卸下的只言片语，id 是毫秒时间戳字符串。
class Note {
  final String id;
  final String text;
  final DateTime createdAt;

  Note({required this.id, required this.text, required this.createdAt});

  Map<String, dynamic> toMap() => {
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static Note fromMap(String id, Map map) => Note(
        id: id,
        text: (map['text'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );
}

/// 碎片存储：和日记同在本机 Hive 里，box 名 'notes'，不经过任何服务器。
class NoteStore {
  static late Box _box;

  static Future<void> init() async {
    _box = await Hive.openBox('notes');
  }

  static Future<void> put(Note note) => _box.put(note.id, note.toMap());

  static Future<void> delete(String id) => _box.delete(id);

  static bool has(String id) => _box.containsKey(id);

  /// 全部碎片，新的在前。
  static List<Note> all() {
    final keys = _box.keys.cast<String>().toList()
      ..sort((a, b) => b.compareTo(a));
    return keys.map((k) => Note.fromMap(k, _box.get(k) as Map)).toList();
  }

  /// 今天的碎片，新的在前。
  static List<Note> todays() {
    final now = DateTime.now();
    return all()
        .where((n) =>
            n.createdAt.year == now.year &&
            n.createdAt.month == now.month &&
            n.createdAt.day == now.day)
        .toList();
  }

  /// 数据变化通知（今天页碎片列表实时刷新用）。
  static ValueListenable<Box> get listenable => _box.listenable();

  static int get count => _box.length;

  static Future<void> clearAll() => _box.clear();
}
