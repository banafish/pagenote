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
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';
import 'package:pagenote/utils/sticker_store.dart';
import 'package:pagenote/widgets/canvas/canvas_tool_sheets.dart';

/// 素材面板「我的」页签分节改版的三条关键路径：
/// 1. 分节结构：预览条（管理入口 + 包封面）置顶，未分组在最上一节，
///    包名标题带张数，旧的「导入图片」行不再出现；
/// 2. 点击包预览定位到对应分节标题；
/// 3. 预览条首位的管理入口整页打开素材首页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Future<String> Function() previousDocumentsDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    documents = await Directory.systemTemp.createTemp('pagenote-mine-docs');
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

  Future<
    (
      JournalProvider,
      SettingsProvider,
      TemplateProvider,
      CustomStickerProvider,
    )
  >
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

  /// 未分组 10 张 + 「春日」包 5 张 + 「夏夜」包 8 张，
  /// 分节内容足够超出页签区高度，滚动定位才有意义。
  Future<void> seedMine(WidgetTester tester, CustomStickerProvider stickers) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await stickers.importFromBytes(pngOf(i), name: '散$i');
      }
      final spring = await stickers.createPack('春日');
      for (var i = 0; i < 5; i++) {
        await stickers.importFromBytes(
          pngOf(10 + i),
          name: '春$i',
          packId: spring!.id,
        );
      }
      final summer = await stickers.createPack('夏夜');
      for (var i = 0; i < 8; i++) {
        await stickers.importFromBytes(
          pngOf(20 + i),
          name: '夏$i',
          packId: summer!.id,
        );
      }
    });
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
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showStickerPalette(context, onPick: (_) {}),
                child: const Text('打开面板'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开素材面板并切到「我的」页签。
  Future<void> openMineTab(WidgetTester tester) async {
    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
  }

  /// 预览条纯图标后按 Tooltip 文案定位条目。
  Finder stripTile(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == tooltip,
  );

  testWidgets('我的页签分节直出：预览条 + 未分组置顶 + 包名带张数', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await seedMine(tester, stickers);
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await openMineTab(tester);

    // 预览条：首位管理入口 + 两个包封面；纯图标无名称，
    // 包名只出现在分节标题与 Tooltip 里。
    expect(find.text('管理'), findsNothing, reason: '预览条不应再有名称文字');
    expect(stripTile('管理我的素材'), findsOneWidget);
    expect(stripTile('春日'), findsOneWidget);
    expect(stripTile('夏夜'), findsOneWidget);
    expect(find.text('春日'), findsOneWidget);
    expect(find.text('夏夜'), findsOneWidget);

    // 分节标题带张数；旧的「导入图片」行已被预览条取代。
    expect(find.text('10 张'), findsOneWidget);
    expect(find.text('5 张'), findsOneWidget);
    expect(find.text('8 张'), findsOneWidget);
    expect(find.text('导入图片'), findsNothing);

    // 格子角标与其他页签一致是收藏星标，「更多」菜单不再出现。
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(23));

    // 未分组在最上一节，其后按 provider 的包顺序（素材页同序）排列。
    double topOf(String text) => tester.getTopLeft(find.text(text).last).dy;
    var prevTop = topOf('未分组');
    for (final name in stickers.packs.map((p) => p.name)) {
      final top = topOf(name);
      expect(top, greaterThan(prevTop), reason: '「$name」分节应排在前面的小节之后');
      prevTop = top;
    }
  });

  testWidgets('点击包预览定位到对应分节标题', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await seedMine(tester, stickers);
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await openMineTab(tester);

    final list = find.byType(SingleChildScrollView);
    final viewportTop = tester.getTopLeft(list).dy;
    final viewportBottom = viewportTop + tester.getSize(list).height;
    // 「夏夜」分节在列表底部之外。
    expect(
      tester.getTopLeft(find.text('夏夜').last).dy,
      greaterThan(viewportBottom),
    );

    // 预览条里的「夏夜」封面（Tooltip 定位）点击后滚到其分节标题。
    await tester.tap(stripTile('夏夜'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('夏夜').last).dy,
      closeTo(viewportTop + 8, 2.5),
      reason: '分节标题应对齐到列表顶部（标题自带 8px 上内边距）',
    );
  });

  testWidgets('预览条首位是素材管理入口，整页打开素材首页', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await seedMine(tester, stickers);
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await openMineTab(tester);

    await tester.tap(stripTile('管理我的素材'));
    await tester.pumpAndSettle();
    expect(find.text('我的素材包'), findsOneWidget, reason: '应整页打开素材首页');
  });

  testWidgets('素材包过多时预览条可横滑且有渐隐提示', (tester) async {
    final (journal, settings, templates, stickers) = await bootstrap(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 25; i++) {
        final pack = await stickers.createPack('包$i');
        await stickers.importFromBytes(
          pngOf(30 + i),
          name: '贴$i',
          packId: pack!.id,
        );
      }
    });
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        journal: journal,
        settings: settings,
        templates: templates,
        stickers: stickers,
      ),
    );
    await openMineTab(tester);

    final strip = find.descendant(
      of: find.byType(ShaderMask),
      matching: find.byType(ListView),
    );
    expect(strip, findsOneWidget, reason: '预览条应包一层渐隐遮罩');
    final controller = tester.widget<ListView>(strip).controller;
    expect(controller, isNotNull);
    expect(controller!.hasClients, isTrue);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: '25 个包应超出预览条宽度,产生横滑余量',
    );
  });
}
