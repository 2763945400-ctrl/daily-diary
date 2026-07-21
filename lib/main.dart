import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/entry_store.dart';
import 'data/note_store.dart';
import 'data/notification_service.dart';
import 'data/settings_store.dart';
import 'pages/review_page.dart';
import 'pages/settings_page.dart';
import 'pages/today_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EntryStore.init();
  await NoteStore.init();
  await SettingsStore.init();
  try {
    await NotificationService.init();
    await NotificationService.schedule(); // 启动时校准下一次提醒
  } catch (_) {
    // 提醒系统出问题不能挡住日记本身,静默降级
  }
  runApp(const DiaryApp());
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 强调色：墨绿。想换色只改这一行。
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3A5A40));
    return MaterialApp(
      title: '每日一记',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [TodayPage(), ReviewPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: 三页常驻只切换显示,切标签不丢「今天」页的未保存草稿
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '回顾',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
