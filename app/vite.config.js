import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { defineConfig } from 'vite';

// public/ 里额外要进预缓存的东西。
// 图标（共 13.5 KB）**故意不进**：只有「添加到主屏幕」那一刻才用得上，
// 而那一刻必然在线；进了预缓存就等于每个首次访问都白下 13.5 KB。
const EXTRA_PRECACHE = ['manifest.webmanifest'];

/**
 * 构建时生成 dist/sw.js：把真实的产物清单和一个内容版本戳注进 src/sw.js 模板。
 *
 * 为什么手写而不用 vite-plugin-pwa：那个插件（连同 workbox）的依赖树比整个应用
 * 还大，而我们只需要「全量预缓存 + 版本化缓存名」这一件事，三十行就够。
 * 规格第五节也写了「自写 Service Worker，几十行即可」。
 */
function serviceWorker() {
  return {
    name: 'diary-sw',
    apply: 'build',
    // ⚠️ 必须 post。index.html 是 Vite 内部的 vite:build-html 插件在它自己的
    //    generateBundle 里才塞进 bundle 的；不加 post 就跑在它前面，清单里
    //    静悄悄地少了 index.html —— 缓存看着建好了，离线打开却是白屏。
    enforce: 'post',
    generateBundle(_options, bundle) {
      const hash = createHash('sha256');
      const files = Object.keys(bundle).sort();

      // 版本戳按**内容**算，不按文件名算：
      // JS/CSS 的文件名本来就带内容哈希，但 index.html 不带 —— 只改 HTML 的那种
      // 提交，光看文件名会以为什么都没变，缓存就永远换不掉。
      for (const name of files) {
        const item = bundle[name];
        hash.update(name);
        hash.update(item.type === 'chunk' ? item.code : item.source);
      }
      for (const name of EXTRA_PRECACHE) {
        hash.update(name);
        hash.update(readFileSync(new URL(`./public/${name}`, import.meta.url)));
      }

      const precache = [...files, ...EXTRA_PRECACHE].map((name) => `./${name}`);

      const source = readFileSync(new URL('./src/sw.js', import.meta.url), 'utf8')
        .replace('__CACHE_VERSION__', hash.digest('hex').slice(0, 8))
        .replace('__PRECACHE__', JSON.stringify(precache));

      // 这两条断言各挡过一次真事故，别删：
      //   占位符没换干净 → SW 直接语法错误，但浏览器只在控制台小声抱怨一句
      //   清单里少 index.html → 离线打开白屏，而缓存看上去是建好的
      // 两种都不会让构建失败，只会让线上悄悄坏掉，所以在这里主动炸。
      if (source.includes('__CACHE_VERSION__') || source.includes('__PRECACHE__')) {
        this.error('sw.js 模板里的占位符没有全部替换');
      }
      if (!precache.includes('./index.html')) {
        this.error('预缓存清单里没有 index.html');
      }

      this.emitFile({ type: 'asset', fileName: 'sw.js', source });
    },
  };
}

export default defineConfig({
  // 相对路径。GitHub Pages 的 /daily-diary/ 子路径和 Capacitor WebView
  // 的 capacitor:// 协议都要求这个，写死 '/' 两边都会 404。
  base: './',
  plugins: [serviceWorker()],
  server: { port: 8686, strictPort: true },
  build: { outDir: 'dist' },
});
