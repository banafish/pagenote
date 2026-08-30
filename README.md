# 拾页 PageNote

一款精美的手账应用 —— 拾起生活中的每一页。

基于 Flutter 构建，支持 **Android 手机 / 平板**、**Windows** 与 **Web 浏览器** 三类载体，界面自适应：手机使用底部导航，平板与桌面使用侧边导航栏。

## ✨ 功能

- **时光轴** — 按日期分组浏览全部手账，支持收藏过滤、快捷搜索；「那年今天」卡片回看历史上同一天写下的内容
- **画布手账编辑器** — 一页手账 = 一张自由画布：文字框、照片、贴纸、胶带、日期/心情/天气组件均为可拖拽、双指缩放旋转的独立图层；支持撤销/重做与图层置顶/置底；时间线卡片、编辑器与分享长图共用同一渲染器，所见即所得
- **手账素材库** — 81 款程序绘制的免抠矢量贴纸（自然/美食/生活/可爱/旅行/心情 6 大类）+ 系统 emoji 贴纸，12 纹样 × 11 色和纸胶带，9 款纸张纹理 + 8 款纯色 + 5 款柔和渐变，全部离线自绘、零图片资产
- **自定义贴纸** — 相册图片一键去白底转为专属贴纸，按内容哈希存储、跨设备稳定
- **素材包** — 把贴纸、模板等组合成带封面署名的素材包，导出为 zip 分享给好友，也可导入他人分享的包
- **花样字体** — 霞鹜文楷 / 马善政楷 / 快乐体 / 站酷小薇 / 庆科黄油体 / 龙藏体 / 志莽行书 / 柳建毛草 / 得意黑 / 朱雀仿宋 10 款开源可商用中文字体（OFL 1.1，GB2312 子集化后入库，见 `tool/subset_fonts.py`），文字框级可选；Android release 包仅内置霞鹜文楷，其余字体首次选用时从远端下载源（支持多源按序回退）按需下载并缓存
- **照片贴纸化** — 相册照片直接转为画布元素，支持圆形 / 拍立得遮罩与圆角
- **整页版式模板** — 12 套内置模板自带纸张、贴纸预设、文字占位与字体，「今日手账」一键套用并自动填入每日一问；任意手账可另存为模板
- **回顾** — 日历与统计合并为一个一级入口：月视图回看每一天、当日心情一目了然，可直达某天补写；窄屏切换查看、宽屏两栏同屏
- **统计与月报** — 总篇数、连续记录天数、本月篇数、累计字数、近 7 天趋势、心情分布、常用标签排行；月报页可回看任意历史月份的写作报告（心情/天气/活动在画布上自由排版的同时仍参与统计）
- **搜索** — 按标题、正文、标签即时搜索，支持按标签快速浏览
- **回收站** — 删除的手账软删除保留 30 天，可恢复或彻底清除
- **应用锁** — 4 位 PIN 加盐哈希存储，Android 生物识别 / Windows Hello 一键解锁，可设置退出后台后免验证延时
- **写作提醒** — Android 本地通知每日定时提醒写作，点按通知直达编辑页（Web / Windows 自动降级）
- **个性化** — 浅色 / 深色 / 跟随系统主题，6 种强调色，正文字号调节
- **桌面小组件** — Android 桌面展示连续记录天数、今日是否已写与今日一问，点按直达编辑页
- **WebDAV 自动备份** — 定期把全部手账与图片单向备份到坚果云等网盘，最多保留 10 份，支持从云端恢复（Web 端要求 WebDAV 服务器允许跨域访问）
- **快速速记** — 一句话 + 可选图片直接入库并标记「未整理」，稍后在编辑页补充心情 / 标签整理成正式手账
- **Web 品牌主页** — 浏览器打开默认展示品牌介绍页（复用内置矢量贴纸与胶带绘制装饰），点击「开始使用」进入应用本体；原生端不经过该页

## 🛠 技术栈

| 模块 | 方案 |
| --- | --- |
| 框架 | Flutter 3.x（Material 3） |
| 状态管理 | provider |
| 本地存储 | sqflite（Android）/ sqflite_common_ffi（Windows）/ sqflite_common_ffi_web + IndexedDB（Web） |
| 偏好设置 | shared_preferences |
| 图片选择 | file_selector（附件复制到应用目录持久保存），file_picker（Android SAF 导出素材包） |
| 图片处理 | image（自定义贴纸解码与去白底） |
| 应用安全 | crypto（PIN 加盐哈希）、local_auth（生物识别 / Windows Hello） |
| 提醒通知 | flutter_local_notifications + timezone（仅 Android） |
| 分享导出 | share_plus（分享长图）、gal（保存相册）、archive（备份 / 素材包 zip 打包） |
| 图表 | 自绘（无第三方图表依赖） |

## 🚀 运行

```bash
flutter pub get

# Windows
flutter run -d windows

# Android（手机 / 平板）
flutter run -d <device-id>

# Web 浏览器
flutter run -d chrome
```

发布构建：

```bash
flutter build windows --release
flutter build web --release

# Android：先出分架构包（推荐分发，体积约为通用包一半），
# 再出全 ABI 通用包兜底模拟器与未适配机型。
# release 包只内置霞鹜文楷一款花样字体（其余在打包期剔除），需通过
# PAGENOTE_FONT_BASE_URL 注入字体下载目录（逗号分隔多源、按序回退，
# 见下文「花样字体下载源」一节）后其余字体才可按需下载；
# debug 构建全量随包，不受影响。
flutter build apk --release --split-per-abi \
  --dart-define=PAGENOTE_FONT_BASE_URL=https://pagenote-web.pages.dev/assets/fonts,https://cdn.jsdelivr.net/gh/banafish/pagenote@v1.4.0/fonts
flutter build apk --release
```

### Web 部署（Cloudflare Pages）与品牌页外链

线上站点：**https://pagenote-web.pages.dev**（Cloudflare Pages，花样字体
的按需下载也以该域名为源）。

Web 品牌页的 GitHub / 客户端下载入口通过 `--dart-define` 在构建期注入，
未注入的入口会自动隐藏。Cloudflare Pages 构建命令使用
`bash tool/build_web.sh`（输出目录 `build/web`）；Pages 构建机没有预装
Flutter，脚本会在 PATH 上找不到 flutter 时自动下载官方 Linux 稳定版
SDK（默认钉住 3.44.6，可用环境变量 `FLUTTER_VERSION` 覆盖），因此
每次 CI 构建会多花几分钟，属预期行为。脚本会读取下列同名
环境变量（Pages 控制台 Settings → Environment variables 配置）并透传：

| 环境变量 | 说明 |
| --- | --- |
| `PAGENOTE_GITHUB_REPO` | GitHub 仓库地址 |
| `PAGENOTE_GITHUB_RELEASES` | GitHub Releases 下载页 |
| `PAGENOTE_DOWNLOAD_ANDROID` | 安卓客户端直接下载地址（APK） |
| `PAGENOTE_DOWNLOAD_PC` | PC 客户端直接下载地址（Windows） |
| `FLUTTER_VERSION` | 覆盖 CI 自动安装的 Flutter 版本（默认 3.44.6） |

### 花样字体下载源（Android release）

`PAGENOTE_FONT_BASE_URL` 不是 Pages 环境变量，而是构建 **Android release APK**
时的 `--dart-define`：指向花样字体的下载目录，**逗号分隔可配多个源、按序
回退**，首个下载成功的源生效——任何单一部署下线都不影响取字。推荐
「Pages 站点 + jsDelivr 仓库源」双源组合：

```
--dart-define=PAGENOTE_FONT_BASE_URL=https://pagenote-web.pages.dev/assets/fonts,https://cdn.jsdelivr.net/gh/banafish/pagenote@v1.4.0/fonts
```

- **Pages 源**（`…/assets/fonts`）：随 web 部署自动同步最新字体，但依赖
  该部署存活，且 `pages.dev` 域名在部分网络环境下不可达；
- **jsDelivr 源**（`gh/banafish/pagenote@<tag>/fonts`）：直接托管 GitHub
  仓库里的同一份 `fonts/` 目录（与应用下载的正是同一批文件），由公共
  CDN 长期服务、不依赖任何自有部署，适合兜底；被墙的 `pages.dev` 网络
  下通常仍可直连 jsDelivr。

debug / Windows / web 构建全量随包，不需要该变量。

**tag 维护约定**：jsDelivr 对 tag 内容永久缓存，`@v1.4.0` 必须是已推送、
包含当前字体内容的 tag（`git tag v1.4.0 && git push origin v1.4.0`）。
字体一旦重新子集化或增删（`fontPackVersion` 随之 +1），须同步打新 tag
并更新构建命令里的 tag 名——只改代码不打 tag 的话，jsDelivr 源仍会下发
旧字体字节。

本地带外链预览：`flutter run -d chrome --dart-define=PAGENOTE_GITHUB_REPO=https://github.com/xxx/pagenote ...`。

## 📁 结构

```
web/                 # Web 端壳（index.html / sqlite wasm / 图标）
lib/
  app.dart            # 根导航骨架（响应式布局：时光 / 素材 / 回顾 / 设置）
  main.dart           # 入口与平台数据库初始化
  models/             # 手账条目、画布元素树、贴纸/胶带/纸张素材库、模板模型
  data/               # 内置数据（每日一问题库）
  database/           # SQLite 数据库层
  providers/          # 手账数据、设置、自定义贴纸、模板的状态管理
  services/           # 应用锁、备份/WebDAV、提醒通知、桌面小组件、素材包等服务
  storage/            # 跨平台文件存取（IO / Web 双实现）
  pages/              # 时光 / 素材库 / 回顾 / 统计 / 设置 / 画布编辑器 / 搜索 /
                      #   月报 / 回收站 / PIN 锁 / 分享卡片 / 素材包导入导出
  widgets/            # 卡片、画布渲染器/编辑层、表情选择器、标签编辑器等
  theme/              # Material 3 主题
  utils/              # 日期、附件、平台判断等工具
fonts/                # OFL 开源中文字体 10 款（GB2312 子集化后入库，含许可证；
                      #   重新子集化用 python tool/subset_fonts.py）
```
