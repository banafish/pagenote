import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/pages/pack_detail_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';
import 'package:pagenote/widgets/canvas/canvas_view.dart';

/// 模板管理页大列表的**结构性**回归（REQ-18.6）。
///
/// 这里钉的不是帧率：widget 测试跑在 fake-async 里，没有真实光栅化，
/// 量不出 REQ-18.6 说的滚动流畅度。终验报告把 REQ-18.6 记为
/// 「结构到位但无实测」，本文件补的正是「结构到位」这一半 ——
/// 只保证下面两个前提不被后人无意改掉：
///
/// 1. 懒渲染：网格用 `SliverGrid.builder`，首帧只为可视范围内的模板
///    建出 [CanvasView] 缩略图，几十套模板不会一次性全渲染；
/// 2. 重绘隔离：每张缩略图外层裹着 [RepaintBoundary]，滚动时一张卡片
///    的重绘不牵动同屏其他卡片。
///
/// 真实帧率仍需在 Android / Windows 真机上用 DevTools 观察，本文件不能替代。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    // 与 widget_test.dart 同理：fake-async 下跨 isolate 的 ffi 结果送不回来。
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// 造一套带画布的用户模板：元素数量贴近真实手账版式，
  /// 让缩略图的构建开销不至于被优化成空壳。
  JournalTemplate userTemplate(int i) => JournalTemplate(
    id: 'perf-$i',
    name: '压力模板 $i',
    content: '正文 $i',
    sortIndex: i,
    createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
    canvas: JournalCanvas(
      paperId: 'plain',
      elements: [
        TextElement(x: 0.07, y: 0.08, text: '标题 $i', fontScale: 0.06),
        TextElement(x: 0.07, y: 0.22, text: '今天写了点什么 $i', role: 'body'),
        StickerElement(key: 'vec:flower', x: 0.7, y: 0.1),
        StickerElement(key: 'vec:cat', x: 0.72, y: 0.6),
      ],
    ),
  );

  /// 30 套用户模板 + 全部内置模板，凑出 REQ-18.6 说的「几十套」规模。
  Future<TemplateProvider> loadedProvider({int users = 30}) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = TemplateProvider(database: db);
    await provider.load();
    for (var i = 0; i < users; i++) {
      await provider.saveTemplate(userTemplate(i));
    }
    return provider;
  }

  Widget wrap(TemplateProvider templates, SettingsProvider settings) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: templates),
          ChangeNotifierProvider.value(value: settings),
          // 详情页同时 watch 贴纸仓库（未分组节的贴纸数据源）。
          ChangeNotifierProvider.value(
            value: CustomStickerProvider(database: AppDatabase.inMemory()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(settings.seedColor),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 未分组详情承载全部自建模板的网格（REQ-26.2），
          // 懒渲染与重绘隔离的断言在这条路径上仍然成立。
          home: const PackDetailPage.ungrouped(),
        ),
      );

  /// 固定成手机竖屏尺寸，网格列数与可视行数才是确定的。
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// 从缩略图往上找 [RepaintBoundary]：卡片内层级固定在 5 层以内，
  /// 放宽到 8 层是给后续微调布局留余地，再远就说明隔离边界丢了。
  bool hasNearbyRepaintBoundary(Element element, {int limit = 8}) {
    var found = false;
    var steps = 0;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is RepaintBoundary) {
        found = true;
        return false;
      }
      steps++;
      return steps < limit;
    });
    return found;
  }

  testWidgets('几十套模板时首帧只渲染可视范围内的缩略图（REQ-18.6）', (tester) async {
    usePhoneScreen(tester);
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final templates = await loadedProvider();

    await tester.pumpWidget(wrap(templates, settings));
    await tester.pumpAndSettle();

    final total = templates.templates.length;
    expect(total, greaterThanOrEqualTo(30), reason: '样本量不够就测不出懒渲染');

    final rendered = find.byType(CanvasView).evaluate().length;
    expect(rendered, greaterThan(0), reason: '一张缩略图都没建出来，说明页面根本没渲染');
    expect(
      rendered,
      lessThan(total ~/ 2),
      reason: '首帧建出了 $rendered/$total 张缩略图，懒渲染（SliverGrid.builder）可能被换成了一次性构建',
    );
  });

  testWidgets('滚动到底再回头都不抛异常，且缩略图数量始终受限（REQ-18.6）', (tester) async {
    usePhoneScreen(tester);
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final templates = await loadedProvider();

    await tester.pumpWidget(wrap(templates, settings));
    await tester.pumpAndSettle();

    final total = templates.templates.length;
    final scrollable = find.byType(CustomScrollView);
    expect(scrollable, findsOneWidget);

    var peak = find.byType(CanvasView).evaluate().length;
    for (var i = 0; i < 8; i++) {
      await tester.drag(scrollable, const Offset(0, -420));
      await tester.pumpAndSettle();
      peak = peak > find.byType(CanvasView).evaluate().length
          ? peak
          : find.byType(CanvasView).evaluate().length;
    }
    for (var i = 0; i < 8; i++) {
      await tester.drag(scrollable, const Offset(0, 420));
      await tester.pumpAndSettle();
      peak = peak > find.byType(CanvasView).evaluate().length
          ? peak
          : find.byType(CanvasView).evaluate().length;
    }

    expect(tester.takeException(), isNull, reason: '来回滚动过程中不得抛异常');
    expect(
      peak,
      lessThan(total ~/ 2),
      reason: '滚动过程中同时存活 $peak/$total 张缩略图，说明离屏卡片没有被回收',
    );
    // 回到顶部后模板节仍在，滚动没把列表滚丢。
    expect(find.text('模板'), findsOneWidget);
  });

  testWidgets('每张可见缩略图都被 RepaintBoundary 隔离（REQ-18.6）', (tester) async {
    usePhoneScreen(tester);
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final templates = await loadedProvider();

    await tester.pumpWidget(wrap(templates, settings));
    await tester.pumpAndSettle();

    final views = tester.elementList(find.byType(CanvasView)).toList();
    expect(views, isNotEmpty);
    for (final view in views) {
      expect(
        hasNearbyRepaintBoundary(view),
        isTrue,
        reason: '有缩略图外层没有 RepaintBoundary，滚动时会连带同屏其他卡片一起重绘',
      );
    }
  });
}
