import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'pages/editor_page.dart';
import 'pages/pack_detail_page.dart';
import 'pages/share_pack_import_page.dart';
import 'providers/custom_sticker_provider.dart';
import 'providers/journal_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/template_provider.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'services/webdav_service.dart';
import 'theme/app_theme.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端（Windows）使用 sqlite3 FFI 实现。
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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

  runApp(
    // Windows 端整体禁用语义树（flutter/flutter#182444）：外部 UIA 客户端
    // （输入法、远程/截图工具、讲述人等）会激活引擎无障碍桥，ListView +
    // Tooltip 组合会产生孤儿语义节点，控制台刷 "Failed to update ui::AXTree"
    // 且可能无 Dart 异常直接崩溃；官方修复（#190344/#190431）合并后可移除。
    ExcludeSemantics(
      child: PageNoteApp(
        settings: settings,
        journal: journal,
        templates: templates,
        customStickers: customStickers,
      ),
    ),
  );

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
            home: const LockGate(child: _SharePackGate(child: RootShell())),
          );
        },
      ),
    );
  }
}

/// 分享包入口（REQ-21.11）：系统把 zip 交给拾页时,原生侧只暂存到私有缓存,
/// 由本层在启动与每次回到前台时主动来取,再打开导入预览页(REQ-21.5)。
///
/// 挂在 [LockGate] 内侧 —— 应用锁未解开时本层根本不挂载,导入页不会盖在锁屏之上。
/// 仅 Android 有原生实现;Windows 走设置页手动选择文件(REQ-21.12),此处直接空转。
class _SharePackGate extends StatefulWidget {
  const _SharePackGate({required this.child});

  final Widget child;

  @override
  State<_SharePackGate> createState() => _SharePackGateState();
}

class _SharePackGateState extends State<_SharePackGate>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('pagenote/app');

  /// 导入流程进行中:不重复取包、不叠开第二个预览页。
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    // 冷启动:首帧后再取,此时 Navigator 已就绪。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPack());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 热启动:原生侧 onNewIntent 之后必然走一次 onResume,在这里补取。
    if (state == AppLifecycleState.resumed) _consumePendingPack();
  }

  Future<void> _consumePendingPack() async {
    if (_handling) return;
    Map<Object?, Object?>? pending;
    try {
      pending = await _channel.invokeMethod<Map<Object?, Object?>>(
        'sharePack.consumePending',
      );
    } on MissingPluginException {
      return; // 原生侧未实现（测试环境）。
    } on PlatformException {
      return;
    }
    final path = pending?['path'] as String?;
    if (path == null || path.isEmpty || !mounted) return;

    _handling = true;
    final file = File(path);
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      _handling = false;
      return;
    }
    try {
      await file.delete();
    } on FileSystemException {
      // 缓存文件删不掉不影响导入,下次收包时会被整目录清掉。
    }
    if (!mounted) {
      _handling = false;
      return;
    }
    try {
      await _openImportPage(bytes, pending?['name'] as String?);
    } finally {
      _handling = false;
    }
  }

  Future<void> _openImportPage(Uint8List bytes, String? sourceName) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<SharePackImportResult>(
      MaterialPageRoute(
        builder: (_) =>
            SharePackImportPage(bytes: bytes, sourceName: sourceName),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    // REQ-26.4：导入完成直达对应包详情页并高亮新装的内容——
    // 包有了自己的页面,回跳有了天然落点,不再连续 push 两个管理页。
    // 极端情况下（素材全部被尺寸闸拦下）没有落位包,留在当前页即可。
    if (result.packId != null) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PackDetailPage.pack(
            result.packId!,
            highlightTemplateIds: result.templateIds,
            highlightStickerIds: result.stickerIds,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
