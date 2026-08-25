import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'database/configure_database.dart';
import 'pages/editor_page.dart';
import 'providers/custom_sticker_provider.dart';
import 'providers/journal_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/template_provider.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'services/webdav_service.dart';
import 'theme/app_theme.dart';
import 'utils/env.dart';
import 'widgets/lock_gate.dart';
import 'widgets/share_pack_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 按平台装配 sqlite 实现：桌面 FFI、Web wasm（Android 用自带实现）。
  configureDatabase();

  final prefs = await SharedPreferences.getInstance();

  final settings = SettingsProvider(prefs);

  final journal = JournalProvider();
  await journal.load();

  final templates = TemplateProvider();
  await templates.load();

  // 自定义图片贴纸（REQ-20）:加载后同步全局索引,供渲染端取素材路径。
  final customStickers = CustomStickerProvider();
  await customStickers.load();

  // 写作提醒（仅 Android;Windows 自动降级）。
  await NotificationService.instance.init();

  // 桌面小组件数据（REQ-14,仅 Android;数据变化时刷新）。
  await WidgetService.instance.init();
  journal.addListener(() => WidgetService.instance.updateFrom(journal));
  await WidgetService.instance.updateFrom(journal);

  Widget app = PageNoteApp(
    settings: settings,
    journal: journal,
    templates: templates,
    customStickers: customStickers,
  );
  // 桌面端整体禁用语义树（flutter/flutter#182444）：外部 UIA 客户端
  // （输入法、远程/截图工具、讲述人等）会激活引擎无障碍桥，ListView +
  // Tooltip 组合会产生孤儿语义节点，控制台刷 "Failed to update ui::AXTree"
  // 且可能无 Dart 异常直接崩溃；官方修复（#190344/#190431）合并后可移除。
  // Web 端不受该 bug 影响，保留语义树供读屏器使用。
  if (isDesktopOS) {
    app = ExcludeSemantics(child: app);
  }
  runApp(app);

  // WebDAV 定期自动备份（REQ-15）:到期则后台执行,不阻塞首帧。
  unawaited(
    WebDavBackupRunner().maybeRunAutoBackup(
      settings: settings,
      buildZip: () async => BackupService.instance.buildZip(
        entries: journal.entries,
        templates: templates.templates,
        customStickers: customStickers.stickers,
        stickerBytes: await customStickers.exportBytes(),
        stickerPacks: customStickers.packs,
        packCoverBytes: await customStickers.exportCoverBytes(),
      ),
    ),
  );
}

class PageNoteApp extends StatelessWidget {
  const PageNoteApp({
    super.key,
    required this.settings,
    required this.journal,
    required this.templates,
    required this.customStickers,
  });

  final SettingsProvider settings;
  final JournalProvider journal;
  final TemplateProvider templates;
  final CustomStickerProvider customStickers;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: templates),
        ChangeNotifierProvider.value(value: customStickers),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([settings, templates]),
        builder: (context, _) {
          return MaterialApp(
            onGenerateTitle: (context) => '拾页',
            debugShowCheckedModeBanner: false,
            navigatorKey: NotificationService.instance.navigatorKey,
            // 桌面端允许鼠标左键按住拖动滚动列表（如素材面板的横滑条）。
            // Flutter 默认 dragDevices 不含鼠标,桌面端按住拖动无法滚动。
            scrollBehavior: const _MouseDragScrollBehavior(),
            theme: AppTheme.light(settings.seedColor),
            darkTheme: AppTheme.dark(settings.seedColor),
            themeMode: settings.themeMode,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(settings.fontScale)),
                child: child!,
              );
            },
            onGenerateRoute: (route) {
              // 点击写作提醒通知直达编辑页（REQ-07.3）：
              // 在当前栈顶直接叠加编辑器。
              if (route.name == '/write') {
                return MaterialPageRoute(builder: (_) => const EditorPage());
              }
              return null;
            },
            home: const LockGate(child: SharePackGate(child: RootShell())),
          );
        },
      ),
    );
  }
}

/// 桌面端滚动行为：鼠标左键按住拖动即可滚动（含横向列表）。
/// 默认行为只认触摸/触笔,电脑上素材面板的横滑条（配色、类别、纸样等）
/// 只能靠滚轮或拖滚动条,鼠标拖拽毫无反应。
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  const _MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.mouse,
  };
}
