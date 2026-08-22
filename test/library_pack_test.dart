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
import 'package:pagenote/pages/library_page.dart';
import 'package:pagenote/pages/pack_detail_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';
import 'package:pagenote/utils/sticker_store.dart';
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
    previousDocumentsDir = StickerStore.documentsDir;
    StickerStore.documentsDir = () async => documents.path;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StickerStore.clearAll();
  });

  tearDownAll(() async {
    StickerStore.documentsDir = previousDocumentsDir;
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
    // 未分组里放一套自建模板：未分组详情才有内容（三档排序条随之出现）。
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
    expect(find.text('未分组'), findsOneWidget);
    expect(find.text('我的素材包'), findsOneWidget);
    expect(find.text('秋日旅行'), findsOneWidget, reason: '包卡片应显示包名');

    // 内置模板固定入口 → builtin 详情（只读 + 复制）。
    await tester.tap(find.text('内置模板'));
    await tester.pumpAndSettle();
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('点模板可预览；复制为我的模板后可自由修改'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 未分组固定入口 → 未分组详情（三档排序条继承 REQ-26.2）。
    await tester.tap(find.text('未分组'));
    await tester.pumpAndSettle();
    expect(find.byType(PackDetailPage), findsOneWidget);
    expect(find.text('手动排序'), findsOneWidget);
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
    // 分节断言才是确定性的。
    tester.view.physicalSize = const Size(800, 1600);
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

    // 分节顺序：内置模板 → 未分组 → 各包（REQ-28.1，包顺序 = 首页手动顺序）。
    final labels = ['内置模板', '未分组', '胶带集'];
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
    // tile 与节头计数齐全：内置 + 未分组 1 套 + 包内 1 套。
    expect(find.text('散装模板'), findsOneWidget);
    expect(find.text('胶带集模板'), findsOneWidget);
    expect(find.text('共 1 套'), findsNWidgets(2));
    // 内置 badge 在 tile 上保留（REQ-28.3）。
    expect(find.text('内置'), findsAtLeastNWidgets(1));
  });
}
