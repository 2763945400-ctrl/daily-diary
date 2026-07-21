# 合成冥想结束钟声：528Hz 基频 + 少量泛音，指数衰减模拟钵音。
# 3 声敲击、间隔 4 秒、音量逐声略升，总长约 12 秒，44.1kHz 16bit 单声道。
# 输出两份：assets/audio/bell.wav（App 前台渐强播放用）
#           ios/Runner/bell.wav（iOS 锁屏通知自定义音用，须 ≤30 秒）
# 用法：在项目根目录运行  python tools/gen_bell.py

import math
import os
import struct
import wave

SR = 44100          # 采样率
DURATION = 12.0     # 总时长（秒）

# 三声敲击：(起始秒, 相对音量)，逐声略升
STRIKES = [(0.2, 0.50), (4.2, 0.65), (8.2, 0.80)]

# 泛音列：(频率, 相对振幅, 衰减时间常数τ秒)，τ 越小消失越快
PARTIALS = [
    (528.0, 1.00, 1.8),
    (528.0 * 2.01, 0.35, 1.1),
    (528.0 * 2.76, 0.18, 0.7),
    (528.0 * 5.40, 0.08, 0.4),
]


def strike(t, amp):
    """单声敲击在 t 秒处的采样值（钵音：泛音叠加 + 各自指数衰减）。"""
    v = 0.0
    for freq, a, tau in PARTIALS:
        v += a * math.sin(2.0 * math.pi * freq * t) * math.exp(-t / tau)
    return amp * v


def synthesize():
    n = int(SR * DURATION)
    frames = bytearray()
    for i in range(n):
        t = i / SR
        s = 0.0
        for start, amp in STRIKES:
            if t >= start:
                s += strike(t - start, amp)
        # 首尾淡入淡出，避免爆音
        s *= min(1.0, t / 0.05, (DURATION - t) / 0.5)
        s = math.tanh(s)  # 软限幅，防止泛音叠加削波
        frames += struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767))
    return bytes(frames)


def write_wav(path, frames):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)


def verify(path):
    with wave.open(path, 'rb') as w:
        secs = w.getnframes() / w.getframerate()
        print(f'{path}: {w.getnchannels()}声道 {w.getframerate()}Hz '
              f'{w.getsampwidth() * 8}bit {secs:.2f}秒')


if __name__ == '__main__':
    frames = synthesize()
    for out in ('assets/audio/bell.wav', 'ios/Runner/bell.wav'):
        write_wav(out, frames)
        verify(out)
