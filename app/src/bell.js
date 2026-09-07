// 静坐结束的钟声。规格第八节要求 **Web Audio 合成，不打包 wav** ——
// 老版本那个 bell.wav 有 1 MB，是整个网页版 150 KB 预算的六倍还多。
//
// 音色仿磬/颂钵：几个**非整数倍**的分音叠在一起。整数倍泛音听着像风琴，
// 金属体振动的分音是不成比例的，那种「铛——」的味道就来自这个。

let ctx = null;

/**
 * 把 AudioContext 备好。
 * ⚠️ 规格第九节的坑：音频不能自动播放，必须在用户手势里创建/resume。
 *    进静坐页是从今天页点进来的，那一下点击就是手势，所以在 activate() 里调。
 */
export function prepare() {
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  }
  if (ctx.state === 'suspended') ctx.resume().catch(() => {});
  return ctx;
}

const F0 = 432;          // 基频，偏暖不刺耳
const PEAK = 0.5;
const ATTACK = 0.08;     // 不做瞬间起振，否则像敲玻璃

// [频率倍数, 相对音量, 衰减秒数]。越高的分音衰减越快，真实金属体就是这样。
const PARTIALS = [
  [1.00, 1.00, 7.0],
  [2.00, 0.45, 4.5],
  [2.76, 0.28, 3.0],
  [5.40, 0.12, 1.6],
];

export function playBell() {
  const audio = prepare();
  if (!audio) return;

  const t0 = audio.currentTime + 0.02;
  const out = audio.createGain();
  out.gain.value = PEAK;
  out.connect(audio.destination);

  for (const [ratio, level, decay] of PARTIALS) {
    const osc = audio.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = F0 * ratio;

    const env = audio.createGain();
    env.gain.setValueAtTime(0, t0);
    env.gain.linearRampToValueAtTime(level, t0 + ATTACK);
    // 指数衰减才像敲击。⚠️ 终值不能写 0，exponentialRamp 到 0 会抛错
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + ATTACK + decay);

    osc.connect(env).connect(out);
    osc.start(t0);
    osc.stop(t0 + ATTACK + decay + 0.1);
  }
}
