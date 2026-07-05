import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'entry_store.dart';
import 'settings_store.dart';

/// 每日提醒：闹钟定在本机系统里，不经过任何服务器。
/// 网页版不支持（浏览器限制），所有方法在 web 上直接空操作。
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 拿不到时区标识时退回默认，提醒可能有时差但不影响使用
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// 申请系统通知权限，返回是否被允许。
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// 按当前设置重新安排提醒。
  /// 规则：今天已经记过、或今天的提醒时间已过 → 首次触发定在明天；
  /// 之后每天同一时间重复。每次保存日记后调用本方法，实现"记过当天不再催"。
  static Future<void> schedule() async {
    if (!_ready) return;
    await _plugin.cancelAll();
    if (!SettingsStore.reminderEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day,
        SettingsStore.reminderHour, SettingsStore.reminderMinute);
    final todayDone = EntryStore.get(EntryStore.todayKey()) != null;
    if (!when.isAfter(now) || todayDone) {
      when = when.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: 0,
      title: '每日一记',
      body: '今天过得怎么样？花一分钟记下来吧',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('daily_reminder', '每日提醒'),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
