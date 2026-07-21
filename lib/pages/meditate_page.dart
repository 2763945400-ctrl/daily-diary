import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../data/notification_service.dart';
import '../data/settings_store.dart';

/// 静坐页：全屏深色，独立于底部导航。
/// 唤醒是双保险——预约系统通知兜底锁屏/后台，前台则渐强播放钟声。
class MeditatePage extends StatefulWidget {
  const MeditatePage({super.key});

  @override
  State<MeditatePage> createState() => _MeditatePageState();
}

enum _Phase { ready, running, done }

class _MeditatePageState extends State<MeditatePage> with WidgetsBindingObserver {
  static const _options = [5, 10, 15, 20];

  _Phase _phase = _Phase.ready;
  int _minutes = SettingsStore.meditationMinutes;
  DateTime? _endTime; // 以真实时间判定结束，不靠 Timer 计数
  Timer? _ticker;
  AudioPlayer? _player; // 渐强播放专用实例，不影响别处
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _fadeTimer?.cancel();
    _player?.dispose();
    // 进行中页面被滑走，视同提前结束
    if (_phase == _Phase.running) {
      NotificationService.cancelMeditationBell();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台用真实时间对表：后台时 Timer 会停，系统通知也可能没触发
    if (state == AppLifecycleState.resumed && _phase == _Phase.running) {
      _tick();
    }
  }

  void _start() {
    final end = DateTime.now().add(Duration(minutes: _minutes));
    SettingsStore.setMeditationMinutes(_minutes); // 记住上次选择
    setState(() {
      _phase = _Phase.running;
      _endTime = end;
    });
    NotificationService.scheduleMeditationBell(end); // 锁屏/后台兜底
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final end = _endTime;
    if (end == null || _phase != _Phase.running) return;
    if (!DateTime.now().isBefore(end)) {
      _finish();
    } else {
      setState(() {}); // 刷新剩余分钟
    }
  }

  Future<void> _finish() async {
    if (_phase != _Phase.running) return;
    _ticker?.cancel();
    // 前台自己播钟，预约的兜底通知撤掉
    await NotificationService.cancelMeditationBell();
    setState(() => _phase = _Phase.done);
    unawaited(_playBell());
  }

  /// 渐强播放：音量从 0 每 500ms 递增，封顶 0.6。
  Future<void> _playBell() async {
    final player = AudioPlayer();
    _player = player;
    await player.setVolume(0);
    await player.play(AssetSource('audio/bell.wav'));
    var step = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      step++;
      final v = (step * 0.05).clamp(0.0, 0.6);
      player.setVolume(v);
      if (v >= 0.6) t.cancel();
    });
  }

  /// 提前结束：取消通知和计时，静默返回。
  Future<void> _abort() async {
    _ticker?.cancel();
    await NotificationService.cancelMeditationBell();
    if (mounted) Navigator.of(context).pop();
  }

  int get _remainingMinutes {
    final end = _endTime;
    if (end == null) return _minutes;
    final secs = end.difference(DateTime.now()).inSeconds;
    return (secs / 60).ceil().clamp(1, _minutes);
  }

  @override
  Widget build(BuildContext context) {
    // 近黑背景、低亮度文字，屏幕本身不打扰
    const bg = Color(0xFF0E100D);
    const dim = Color(0x66FFFFFF);
    const dimmer = Color(0x40FFFFFF);

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        // 结束后点击任意处退出
        onTap: _phase == _Phase.done ? () => Navigator.of(context).pop() : null,
        child: SafeArea(
          child: Stack(
            children: [
              Center(child: _center(dim, dimmer)),
              if (_phase == _Phase.ready)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: dim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _center(Color dim, Color dimmer) {
    switch (_phase) {
      case _Phase.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('坐多久？', style: TextStyle(color: dim, fontSize: 15)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                for (final m in _options)
                  ChoiceChip(
                    label: Text('$m 分钟'),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                    backgroundColor: Colors.transparent,
                    selectedColor: const Color(0x22FFFFFF),
                    labelStyle:
                        TextStyle(color: _minutes == m ? Colors.white : dim),
                    side: BorderSide(
                        color: _minutes == m ? dim : Colors.transparent),
                    showCheckmark: false,
                  ),
              ],
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0x1FFFFFFF),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32)),
              ),
              child: const Text('开始', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      case _Phase.running:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 只显示分钟不显示秒，避免盯屏
            Text('还剩 $_remainingMinutes 分钟',
                style: TextStyle(color: dim, fontSize: 17)),
            const SizedBox(height: 32),
            TextButton(
              onPressed: _abort,
              child: Text('提前结束', style: TextStyle(color: dimmer)),
            ),
          ],
        );
      case _Phase.done:
        return Text('慢慢回来', style: TextStyle(color: dim, fontSize: 15));
    }
  }
}
