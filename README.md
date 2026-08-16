# 拾页 PageNote

一款精美的手账应用 —— 拾起生活中的每一页。

基于 Flutter 构建，支持 **Android 手机 / 平板** 与 **Windows** 三端，界面自适应：手机使用底部导航，平板与桌面使用侧边导航栏。

## ✨ 功能

- **时光轴** — 按日期分组浏览全部手账，支持收藏过滤、快捷搜索
- **写手账** — 标题、正文、心情（10 种）、天气（8 种）、标签、最多 9 张照片
- **日历** — 月视图回看每一天，当日心情一目了然，可直达某天补写
- **统计** — 总篇数、连续记录天数、本月篇数、累计字数、近 7 天趋势、心情分布、常用标签排行
- **搜索** — 按标题、正文、标签即时搜索，支持按标签快速浏览
- **个性化** — 浅色 / 深色 / 跟随系统主题，6 种强调色，正文字号调节

## 🛠 技术栈

| 模块 | 方案 |
| --- | --- |
| 框架 | Flutter 3.x（Material 3） |
| 状态管理 | provider |
| 本地存储 | sqflite（Android）/ sqflite_common_ffi（Windows） |
| 偏好设置 | shared_preferences |
| 图片选择 | file_selector（附件复制到应用目录持久保存） |
| 图表 | 自绘（无第三方图表依赖） |

## 🚀 运行

```bash
flutter pub get

# Windows
flutter run -d windows

# Android（手机 / 平板）
flutter run -d <device-id>
```

发布构建：

```bash
flutter build windows --release
flutter build apk --release
```

## 📁 结构

```
lib/
  app.dart            # 根导航骨架（响应式布局）
  main.dart           # 入口与平台数据库初始化
  models/             # 手账条目、心情/天气模型
  database/           # SQLite 数据库层
  providers/          # 手账数据与设置的状态管理
  pages/              # 时光 / 日历 / 统计 / 设置 / 编辑器 / 搜索
  widgets/            # 卡片、表情选择器、标签编辑器等
  theme/              # Material 3 主题
  utils/              # 日期、附件等工具
```
