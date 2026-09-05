import { defineConfig } from 'vite';

export default defineConfig({
  // 相对路径。GitHub Pages 的 /daily-diary/ 子路径和 Capacitor WebView
  // 的 capacitor:// 协议都要求这个，写死 '/' 两边都会 404。
  base: './',
  server: { port: 8686, strictPort: true },
  build: { outDir: 'dist' },
});
