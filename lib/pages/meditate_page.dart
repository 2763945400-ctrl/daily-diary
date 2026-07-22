import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notification_service.dart';
import '../data/settings_store.dart';

/// 静坐页：全屏深色，独立于底部导航。
/// 进来即自动开始（用上次/默认时长），中央呼吸圆环，底部可低调改时长。
/// 唤醒是双保险——预约系统通知兜底锁屏/后台，前台则渐强播放钟声。
class MeditatePage extends StatefulWidget {
  const MeditatePage({super.key});

  @override
  State<MeditatePage> createState() => _MeditatePageState();
}

enum _Phase { running, done }

class _MeditatePageState extends State<MeditatePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _options = [5, 10, 15, 20];

  _Phase _phase = _Phase.running;
  int _minutes = SettingsStore.meditationMinutes;
  DateTime? _endTime; // 以真实时间判定结束，不靠 Timer 计数
  Timer? _ticker;
  AudioPlayer? _player; // 渐强播放专用实例，不影响别处
  Timer? _fadeTimer;

  // 呼吸圆环：一次完整呼吸约 7 秒，涨缩 + 明暗联动
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7000),
  )..repeat(reverse: true);
  late final Animation<double> _breathAnim =
      CurvedAnimation(parent: _breath, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进页面即开始：直接给字段赋值（initState 里不能 setState）
    SettingsStore.setMeditationMinutes(_minutes); // 记住上次选择
    _endTime = DateTime.now().add(Duration(minutes: _minutes));
    NotificationService.scheduleMeditationBell(_endTime!); // 锁屏/后台兜底
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breath.dispose();
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

  /// 底部时长微调：把计时重置为新时长继续走。
  void _changeDuration(int m) {
    if (m == _minutes) return;
    HapticFeedback.lightImpact();
    SettingsStore.setMeditationMinutes(m); // 记住上次选择
    final end = DateTime.now().add(Duration(minutes: m));
    NotificationService.scheduleMeditationBell(end); // 重新约兜底通知
    setState(() {
      _minutes = m;
      _endTime = end;
    });
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
              Center(child: _center(dim)),
              if (_phase == _Phase.running) ...[
                // 左上 ✕：等同「提前结束」
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    onPressed: _abort,
                    icon: const Icon(Icons.close, color: dim),
                  ),
                ),
                // 底部：低调时长微调 + 提前结束
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final m in _options)
                            GestureDetector(
                              onTap: () => _changeDuration(m),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Text(
                                  '$m',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _minutes == m
                                        ? Colors.white
                                        : dimmer,
                                    fontWeight: _minutes == m
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _abort,
                        child: Text('提前结束', style: TextStyle(color: dimmer)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _center(Color dim) {
    switch (_phase) {
      case _Phase.running:
        // 呼吸圆环：光圈缓慢一涨一缩，圆心显示剩余分钟（只给分钟不给秒）
        return AnimatedBuilder(
          animation: _breathAnim,
          builder: (context, _) {
            final t = _breathAnim.value; // 0↔1 随呼吸往返
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 0.82 + 0.18 * t,
                  child: Opacity(
                    opacity: 0.75 + 0.25 * t,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color.fromRGBO(143, 184, 156, 0.45),
                            Color.fromRGBO(143, 184, 156, 0.15),
                            Color.fromRGBO(143, 184, 156, 0.0),
                          ],
                          stops: [0.0, 0.65, 1.0],
                        ),
                        border: Border.fromBorderSide(BorderSide(
                          color: Color.fromRGBO(143, 184, 156, 0.25),
                        )),
                      ),
                    ),
                  ),
                ),
                Text('还剩 $_remainingMinutes 分钟',
                    style: TextStyle(color: dim, fontSize: 17)),
              ],
            );
          },
        );
      case _Phase.done:
        return Text('慢慢回来', style: TextStyle(color: dim, fontSize: 15));
    }
  }
}
