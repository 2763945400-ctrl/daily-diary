import 'package:hive_flutter/hive_flutter.dart';

/// 设置项的本地存储（和日记数据同在本机 Hive 里）。
class SettingsStore {
  static late Box _box;

  static Future<void> init() async {
    _box = await Hive.openBox('settings');
  }

  static bool get reminderEnabled =>
      _box.get('reminderEnabled', defaultValue: false) as bool;

  static int get reminderHour => _box.get('reminderHour', defaultValue: 21) as int;

  static int get reminderMinute =>
      _box.get('reminderMinute', defaultValue: 30) as int;

  static Future<void> setReminderEnabled(bool value) =>
      _box.put('reminderEnabled', value);

  static Future<void> setReminderTime(int hour, int minute) async {
    await _box.put('reminderHour', hour);
    await _box.put('reminderMinute', minute);
  }
}
