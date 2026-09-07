# 每日一记

一天一条的极简日记。**数据只存在你自己的设备上** —— 没有服务器、没有账号、没有任何统计埋点。

**网页版**：<https://2763945400-ctrl.github.io/daily-diary/>

> 首次打开约 21 KB，装好 Service Worker 之后**完全离线可用**。
> 建议成功打开一次后「添加到主屏幕」—— 之后就再也不需要网络，
> 而且 iOS 上主屏 App 的存储比 Safari 标签页持久得多。

---

## ⚠️ 这个仓库里有两套代码，只有一套是活的

| 目录 | 状态 |
|---|---|
| **`app/`** | ✅ **当前版本。** 原生 Web 技术栈（Vite + 原生 JS，无框架）。网页版由它构建，以后的 iOS 版也走它（Capacitor） |
| `lib/` `ios/` `android/` `test/`<br>`pubspec.yaml` `assets/` `web/` | ❄️ **旧的 Flutter 版，已冻结。** 保留作回滚保险，**不要修改** |

**要改功能，改的是 `app/`。**

### 为什么会有两套

Flutter 的网页版体积下限约 4.4 MB（渲染引擎是硬成本，没有任何配置能做小），在链路质量波动的网络环境下加载不稳定 —— 而这个应用本身是离线优先的，根本不需要那么重。

于是用 Web 技术栈重写了一份：**21 KB**，加上自写的 Service Worker，成功打开一次之后永久离线可用。

Flutter 项目在新版完全取代它之前不删，作为退路。

---

## `app/` 目录结构

```
app/
├── index.html            整个应用只有这一个页面（hash 路由切换）
├── vite.config.js        构建配置 + 生成 Service Worker 的插件
├── capacitor.config.json 原生壳配置（iOS 尚未启用）
│
├── public/               原样复制到站点根目录
│   ├── manifest.webmanifest
│   └── icons/
│
├── design/               ⚠️ 设计稿与设计 token，只读，不是运行代码
│
└── src/
    ├── main.js           路由、Service Worker 注册
    ├── db.js             IndexedDB 读写
    ├── day.js            ⭐ 凌晨 2 点日界，全应用唯一真源，别在别处另写日期计算
    ├── backup.js         导入导出的 JSON 格式
    ├── photo.js          照片压缩（最大边 1600、JPEG 质量 82）
    ├── bell.js           静坐钟声（Web Audio 合成，不打包音频文件）
    ├── sw.js             Service Worker 模板（构建时注入文件清单和版本戳）
    ├── platform.js       判断网页版还是 Capacitor 原生壳
    ├── overlay.js  toast.js  version.js  styles.css
    ├── pages/            today.js  review.js  settings.js  meditate.js
    └── *.test.js         单元测试
```

## 本地开发

```
cd app
npm install
npm run dev      # 开发服务器，http://localhost:8686
npm test         # 单元测试
npm run build    # 构建到 app/dist
```

> Service Worker **只在生产构建里注册**。开发服务器下不注册 —— Vite 按模块单独发文件，
> 缓存了反而会拿到过期模块。要验离线能力，得 `npm run build` 之后用静态服务器跑 `dist/`。

## 两条流水线，互不干扰

| 工作流 | 触发路径 | 干什么 |
|---|---|---|
| `web-deploy.yml` | `app/**` | 构建并发布网页版到 GitHub Pages。**测试不过就不发布** |
| `ios-build.yml` | `lib/** ios/** pubspec.yaml` | 用旧的 Flutter 工程编译 iOS 安装包（未签名） |

改 `app/` 不会触发 iOS 编译，改 `lib/` 也不会触发网页部署。

**推到 `master` 即自动部署**，约一分钟后线上生效。

## 三端能力差异

| | 网页版 | iOS App |
|---|---|---|
| 写日记 / 回顾 / 碎片 / 照片 / 导入导出 | ✅ | ✅ |
| 离线可用 | ✅ Service Worker 缓存后 | ✅ 天然 |
| 每日提醒 | ❌ 浏览器给不了 | ✅ 本地通知 |
| 静坐钟声（锁屏 / 后台） | ❌ 仅前台 | ✅ 本地通知兜底 |

## 数据格式

导出的 JSON **新旧两版互通**，字段名和结构不能改 —— 这是两个版本之间唯一的桥。
格式定义见 [`app/src/backup.js`](app/src/backup.js)。

导入时按日期（日记）和 id（碎片）去重，**已存在的跳过不覆盖**。

## 回滚

旧的 Flutter 网页版一个文件都没删，只是不再编译上网。要让它回来：

把 `.github/workflows/web-deploy.yml` 恢复到提交 `87187cc` 那一版并 push —— 新旧并存的状态会原样回来（Flutter 版在根路径，新版在 `/next/`）。
