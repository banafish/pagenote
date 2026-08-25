import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/pages/editor_page.dart';
import 'package:pagenote/pages/library_page.dart';
import 'package:pagenote/pages/pack_detail_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';
import 'package:pagenote/storage/stored_files.dart';
import 'package:pagenote/utils/sticker_store.dart';
import 'package:pagenote/widgets/canvas/canvas_editor.dart';
import 'package:pagenote/widgets/template_picker.dart';

/// 素材包优先浏览（REQ-26～28）的五条关键路径（NFR-15）：
/// 1. 素材首页两个固定入口可达；
/// 2. 包详情可达且包级操作可用；
/// 3. 导入回跳直达包详情并高亮；
/// 4. 包排序持久化；
/// 5. 模板弹层分节正确。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Future<String> Function() previousDocumentsDir;

  setUpAll(() async {
    sqfliteFfiInit();
    // Widget 测试运行在 fake-async 环境，跨 isolate 的 ffi 结果无法送达，
    // 必须使用同 isolate 的 ffi 工厂。
    databaseFactory = databaseFactoryFfiNoIsolate;
    documents = await Directory.systemTemp.createTemp('pagenote-library-docs');
    previousDocumentsDir = StoredFilesImpl.documentsDir;
    StoredFilesImpl.documentsDir = () async => documents.path;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StickerStore.clearAll();
  });

  tearDownAll(() async {
    StoredFilesImpl.documentsDir = previousDocumentsDir;
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  /// 一套 Providers + 手账数据，测试注入内存库。
  ///
  /// [CustomStickerProvider.load] 会创建素材目录（真实文件 I/O），
  /// fake-async 环境内不会完成，必须经 [WidgetTester.runAsync] 走真实事件循环。
  Future<(JournalProvider, SettingsProvider, TemplateProvider, CustomStickerProvider)>
  bootstrap(WidgetTester tester) async {
    final journalDb = AppDatabase.inMemory();
    addTearDown(journalDb.close);
    final journal = JournalProvider(database: journalDb);
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final templates = TemplateProvider(database: db);
    await templates.load();
    final stickerDb = AppDatabase.inMemory();
    addTearDown(stickerDb.close);
    final stickers = CustomStickerProvider(database: stickerDb);
    await tester.runAsync(stickers.load);
    return (journal, settings, templates, stickers);
  }

  Uint8List pngOf(int seed) {
    final image = img.Image(width: 24, height: 24, numChannels: 4);
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 24; x++) {
        image.setPixelRgba(x, y, (x + seed) % 256, (y + seed) % 256, seed % 256, 255);
      }
    }
    return img.encodePng(image);
  }

  /// 造一个有贴纸与模板的包：贴纸走 importFromBytes 真实落盘（同样需要
  /// runAsync），模板直接 saveTemplate 后挂包（等价于分享包安装的落位结果）。
  Future<({String packId, String stickerId, String templateId})> seedPack(
    WidgetTester tester,
    CustomStickerProvider stickers,
    TemplateProvider templates, {
    String name = '秋日旅行',
  }) async {
    late final ({String packId, String stickerId, String templateId}) seeded;
    await tester.runAsync(() async {
      final pack = await stickers.createPack(name);
      final sticker = await stickers.importFromBytes(
        pngOf(3),
        name: '枫叶',
        packId: pack!.id,
      );
      final template = JournalTemplate(
        id: 'tpl-${pack.id}',
        name: '$name模板',
        content: '内容',
      );
      template.packId = pack.id;
      await templates.saveTemplate(template);
      seeded = (
        packId: pack.id,
        stickerId: sticker!.id,
        templateId: template.id,
      );
    });
    return seeded;
  }

  Widget wrap(
    Widget child, {
    required JournalProvider journal,
    required SettingsProvider settings,
    required TemplateProvider templates,
    required CustomStickerProvider stickers,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: templates),
        ChangeNotifierProvider.value(value: stickers),
      ],
      child: MaterialApp(
        theme: AppTheme.light(settings.seedColor),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('素材首页两个固定入口可达（NFR-15 路径 1）', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await seedPack(tester, stickers, templates);
    // 我的素材里放一套自建模板：该详情页才有内容。
    await templates.saveTemplate(
      JournalTemplate(id: 'tpl-loose-1', name: '散装模板', content: '内容'),
    );

    await tester.pumpWidget(
      wrap(
        const LibraryPage(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();

    // 首页结构（REQ-26.1）：固定入口置顶 + 「我的素材包」区。
    expect(find.text('内置模板'), findsOneWidget);
    expect(find.text('我的素材'), findsOneWidget);
    expect(find.text('我的素材包'), findsOneWidget);
    expect(find.text('秋日旅行'), findsOneWidget, reason: '包卡片应显示包名');

    // 内置模板固定入口 → builtin 详情（只读 + 复制）。
    await tester.tap(find.text('内置模板'));
    await tester.pumpAndSettle();
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('点模板可预览；用模板可直接写一篇，复制为我的模板后可自由修改'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 「我的素材」固定入口 → 未分组详情（排序选择已下线，仅保留手动序与拖排）。
    await tester.tap(find.text('我的素材'));
    await tester.pumpAndSettle();
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('手动排序'), findsNothing, reason: '排序切换条已移除');
    expect(find.text('散装模板'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // 回到首页仍在，固定入口不受详情页进出影响（NFR-13）。
    expect(find.text('内置模板'), findsOneWidget);
  });

  testWidgets('包详情可达且包级操作可用（NFR-15 路径 2）', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    final seeded = await seedPack(tester, stickers, templates);

    await tester.pumpWidget(
      wrap(
        const LibraryPage(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();

    // 点包卡片进入包详情（REQ-26.1）。
    await tester.tap(find.text('秋日旅行'));
    await tester.pumpAndSettle();
    expect(find.byType(PackDetailPage), findsOneWidget);
    // 同屏浏览包内贴纸与模板（REQ-26.2）。
    expect(find.text('枫叶'), findsOneWidget);
    expect(find.text('秋日旅行模板'), findsOneWidget);
    expect(find.text('1 张贴纸 · 1 套模板'), findsOneWidget);

    // 包级操作上移到详情页（REQ-26.3）：菜单里能重命名。
    // 用 tooltip 定位 AppBar 的包操作按钮（模板卡上也有一枚 more_vert）。
    await tester.tap(find.byTooltip('素材包操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名素材包'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '秋日旅行 II');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(stickers.packById(seeded.packId)!.name, '秋日旅行 II');
    expect(find.text('秋日旅行 II'), findsWidgets, reason: '详情页标题随包名更新');
  });

  testWidgets('导入回跳直达包详情并高亮（NFR-15 路径 3）', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    final seeded = await seedPack(tester, stickers, templates);

    // 分享包导入完成后 push 的形态（main.dart / settings_page.dart，REQ-26.4）：
    // 模板高亮 badge 与贴纸高亮 badge 同时出现。贴纸的呼吸描边 4 秒后
    // 自动衰减（REQ-21.9），这里用固定 pump 断言衰减前的状态，
    // 最后快进过衰减点，不留挂起的定时器。
    await tester.pumpWidget(
      wrap(
        PackDetailPage.pack(
          seeded.packId,
          highlightTemplateIds: [seeded.templateId],
          highlightStickerIds: [seeded.stickerId],
        ),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('枫叶'), findsOneWidget);
    expect(find.text('秋日旅行模板'), findsOneWidget);
    // 模板卡与贴纸格各带一枚「新导入」badge（REQ-21.9 表现沿用）。
    expect(find.text('新导入'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('包排序持久化（NFR-15 路径 4，REQ-26.5）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = CustomStickerProvider(database: db);
    await provider.load();

    // 新建 / 新导入的包默认排最前（REQ-26.5）。
    final a = await provider.createPack('A');
    final b = await provider.createPack('B');
    final c = await provider.createPack('C');
    expect(
      provider.packs.map((p) => p.name).toList(),
      ['C', 'B', 'A'],
      reason: '新包应落在列表最前',
    );

    // 长按拖拽排序后的落库：重编 sortIndex 并持久化。
    await provider.reorderPacks([a!.id, c!.id, b!.id]);
    expect(provider.packs.map((p) => p.name).toList(), ['A', 'C', 'B']);

    // 换一个 provider 实例从同一 DB 重读：顺序仍在（持久化到位）。
    final reloaded = CustomStickerProvider(database: db);
    await reloaded.load();
    expect(reloaded.packs.map((p) => p.name).toList(), ['A', 'C', 'B']);

    // 又新建的包仍排最前。
    await reloaded.createPack('D');
    expect(reloaded.packs.map((p) => p.name).toList(), ['D', 'A', 'C', 'B']);
  });

  testWidgets('模板弹层分节正确（NFR-15 路径 5，REQ-28）', (tester) async {
    // 弹层是懒加载列表：加高屏幕让 62% 的初始高度装下全部三节，
    // 分节断言才是确定性的。（内置模板扩到 12 套后每套 tile ≈106px，
    // 1600 高已装不下后面的节，按 tile 数同步加高。）
    tester.view.physicalSize = const Size(800, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await seedPack(tester, stickers, templates, name: '胶带集');
    // 未分组的自建模板。
    await templates.saveTemplate(
      JournalTemplate(id: 'tpl-loose', name: '散装模板', content: '内容'),
    );
    // 空包不出现在分节里（REQ-28.3）。
    await stickers.createPack('空包');

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showTemplatePicker(context),
              child: const Text('打开弹层'),
            ),
          ),
        ),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开弹层'));
    await tester.pumpAndSettle();

    // 分节顺序：内置模板 → 我的模板 → 各包（REQ-28.1，包顺序 = 首页手动顺序）。
    final labels = ['内置模板', '我的模板', '胶带集'];
    var top = -1.0;
    for (final label in labels) {
      final found = find.text(label);
      expect(found, findsOneWidget, reason: '节头「$label」应出现');
      final dy = tester.getTopLeft(found).dy;
      expect(dy, greaterThan(top), reason: '「$label」应排在上一节之后');
      top = dy;
    }
    // 空节不显示（REQ-28.3）。
    expect(find.text('空包'), findsNothing);
    // tile 与节头计数齐全：内置 + 自建 1 套 + 包内 1 套。
    expect(find.text('散装模板'), findsOneWidget);
    expect(find.text('胶带集模板'), findsOneWidget);
    expect(find.text('共 1 套'), findsNWidgets(2));
    // 内置 badge 在 tile 上保留（REQ-28.3）。
    expect(find.text('内置'), findsAtLeastNWidgets(1));
  });

  testWidgets('模板「编辑」：复用编辑器就地更新原模板，不产生手账（REQ-18.3）', (
    tester,
  ) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    // 未分组的一套旧式纯文本模板：编辑时自动合成画布，保存升级为整页版式。
    await templates.saveTemplate(
      JournalTemplate(
        id: 'tpl-edit-me',
        name: '待编辑',
        title: '旧标题',
        content: '旧正文',
      ),
    );

    await tester.pumpWidget(
      wrap(
        const PackDetailPage.ungrouped(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();

    // 我的模板：更多菜单里提供「编辑」。
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // 编辑器以模板模式打开：直接进编辑态，画布上已有模板内容。
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('编辑模板'), findsOneWidget);
    expect(find.byType(CanvasEditor), findsOneWidget);
    expect(find.text('旧正文'), findsOneWidget);
    expect(find.text('套用模板'), findsNothing, reason: '模板模式不提供套用/另存');

    // 加一块自由文字后保存：回写原模板本身。
    await tester.tap(find.byTooltip('文字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新加的文字');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    final saved = templates.byId('tpl-edit-me')!;
    expect(saved.canvas, isNotNull, reason: '纯文本模板经编辑升级为整页版式');
    expect(saved.content, contains('旧正文'));
    expect(saved.content, contains('新加的文字'), reason: '编辑结果就地回写原模板');
    expect(saved.title, '旧标题');
    expect(saved.name, '待编辑', reason: '名字等元数据保持不动');
    expect(journal.entries, isEmpty, reason: '编辑模板不产生手账');
    // 回到详情页：更新提示可见，网格仍在。
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.textContaining('已更新模板'), findsOneWidget);
    expect(find.text('待编辑'), findsOneWidget);
  });

  testWidgets('模板「用模板写一篇」：一键开新篇，保存落手账库不回写模板', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await templates.saveTemplate(
      JournalTemplate(
        id: 'tpl-use-me',
        name: '旅行版式',
        title: '出发吧',
        content: '【行程】',
      ),
    );

    await tester.pumpWidget(
      wrap(
        const PackDetailPage.ungrouped(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();

    // 卡片底部栏的快捷入口：一键用该模板开一篇新手账。
    await tester.tap(find.byTooltip('用模板写一篇'));
    await tester.pumpAndSettle();

    // 编辑器以新手账模式打开（区别于「编辑模板」），画布上已有模板内容。
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('写手账'), findsOneWidget);
    expect(find.byType(CanvasEditor), findsOneWidget);
    expect(find.text('【行程】'), findsOneWidget);
    expect(find.text('从模板开始'), findsNothing, reason: '已带着模板进来，不再引导重选模板');

    // 直接保存：落一篇新手账，模板本身保持原样。
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(journal.entries, hasLength(1));
    expect(journal.entries.single.content, contains('【行程】'));
    final template = templates.byId('tpl-use-me')!;
    expect(template.content, '【行程】', reason: '用模板开新篇不回写模板本身');
    expect(template.lastUsedAt, isNotNull, reason: '开新篇即记一次套用');
    // 回到详情页：模板网格仍在。
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('旅行版式'), findsOneWidget);
  });

  testWidgets('内置模板菜单不出现「编辑」，保持只读现状（REQ-26）', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);

    await tester.pumpWidget(
      wrap(
        const PackDetailPage.builtin(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await tester.pumpAndSettle();

    // 内置卡片的更多菜单：只有复制与导出，没有编辑/重命名/删除。
    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsNothing);
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('复制为我的模板'), findsOneWidget);
    expect(find.text('导出分享'), findsOneWidget);
  });
}
