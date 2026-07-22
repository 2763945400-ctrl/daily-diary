import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 一条日记录：一天一条，date 是唯一键。
class Entry {
  final String date; // 'yyyy-MM-dd'
  final String text;
  final Uint8List? photo;
  final DateTime createdAt;
  final DateTime updatedAt;

  Entry({
    required this.date,
    required this.text,
    this.photo,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isEmpty => text.trim().isEmpty && photo == null;

  Map<String, dynamic> toMap() => {
        'text': text,
        'photo': photo,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  static Entry fromMap(String date, Map map) => Entry(
        date: date,
        text: (map['text'] as String?) ?? '',
        photo: map['photo'] as Uint8List?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      );
}

/// 本地存储：手机上是本地文件，网页上自动落在浏览器 IndexedDB。
/// 数据不经过任何服务器。
class EntryStore {
  static late Box _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('entries');
  }

  static const int dayStartHour = 2; // 一天从凌晨2点开始

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 逻辑日期键：凌晨2点前算前一天。全 App 的"今天"都以这里为准。
  static String logicalKey(DateTime t) =>
      dateKey(t.subtract(const Duration(hours: dayStartHour)));

  static String todayKey() => logicalKey(DateTime.now());

  static Entry? get(String date) {
    final raw = _box.get(date);
    if (raw == null) return null;
    return Entry.fromMap(date, raw as Map);
  }

  static Future<void> put(Entry entry) => _box.put(entry.date, entry.toMap());

  static Future<void> delete(String date) => _box.delete(date);

  /// 全部记录，按日期从新到旧。
  static List<Entry> all() {
    final keys = _box.keys.cast<String>().toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) => get(k)!).toList();
  }

  /// 连续记录天数：从逻辑今天（或逻辑昨天，如果今天还没记）往回数。
  static int streak() {
    var day = DateTime.now().subtract(const Duration(hours: dayStartHour));
    if (!_box.containsKey(dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (_box.containsKey(dateKey(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// 数据变化通知（回顾页实时刷新用）。
  static ValueListenable<Box> get listenable => _box.listenable();

  static int get count => _box.length;

  static Future<void> clearAll() async {
    await _box.clear();
  }
}
