import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/data/prompts.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/pages/editor_page.dart';
import 'package:pagenote/pages/home_page.dart';
import 'package:pagenote/pages/search_page.dart';
import 'package:pagenote/pages/share_card_page.dart';
import 'package:pagenote/pages/stats_page.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    // Widget 测试的 fake-async 环境无法接收 ffi 后台 isolate 的结果。
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// 本文件所有测试共享同一条 :memory: 连接（见 AppDatabase.inMemory 说明），
  /// 每个测试前清空数据以保证隔离。
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
    final sqlite = await db.database;
    await sqlite.delete('entries');
    await sqlite.delete('templates');
  });

  JournalEntry entry(
    String id, {
    String date = '2026-08-16',
    String title = '标题',
    String content = '内容',
    Mood? mood,
  }) {
    final now = DateTime.now();
    return JournalEntry(
      id: id,
      date: date,
      title: title,
      content: content,
      mood: mood,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Widget> wrap(
    WidgetTester tester, {
    required Widget child,
    List<JournalEntry> seed = const [],
    SettingsProvider? settings,
  }) async {
    final journal = JournalProvider(database: db);
    for (final e in seed) {
      await journal.saveEntry(e);
    }
    await journal.load();

    final prefs = await SharedPreferences.getInstance();
    final effectiveSettings = settings ?? SettingsProvider(prefs);
    final templates = TemplateProvider(database: db);
    await templates.load();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: effectiveSettings),
        ChangeNotifierProvider.value(value: templates),
      ],
      child: MaterialApp(
        theme: AppTheme.light(effectiveSettings.seedColor),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // HomePage 等页面在生产环境中位于 Scaffold 内，测试同样包一层。
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('REQ-01 那年今天：有历史时展示卡片，无历史不占位', (tester) async {
    // 有去年今天的记录 → 展示。
    await tester.pumpWidget(
      await wrap(
        tester,
        child: HomePage(onOpenEditor: (_, _) {}),
        seed: [
          entry('old', date: '2025-08-16', title: '去年今天写的'),
          entry('today', date: '2026-08-16', title: '今天写的'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('那年今天'), findsOneWidget);
    expect(find.text('2025 年的今天'), findsOneWidget);
    // 标题在回忆卡片与时间轴卡片中各出现一次。
    expect(find.text('去年今天写的'), findsNWidgets(2));
  });

  testWidgets('REQ-01 那年今天：无历史记录时完全不出现', (tester) async {
    await tester.pumpWidget(
      await wrap(
        tester,
        child: HomePage(onOpenEditor: (_, _) {}),
        seed: [entry('today', date: '2026-08-16')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('那年今天'), findsNothing);
  });

  testWidgets('REQ-02 删除进入回收站并出现撤销提示，撤销可恢复', (tester) async {
    await tester.pumpWidget(
      await wrap(
        tester,
        child: HomePage(onOpenEditor: (_, _) {}),
        seed: [entry('e1', title: '待删除的手账')],
      ),
    );
    await tester.pumpAndSettle();

    // 打开卡片菜单并删除。
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('已移入回收站，30 天后自动清除'), findsOneWidget);
    expect(find.text('待删除的手账'), findsNothing, reason: '时间轴不再展示已删除条目');

    // 撤销恢复。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('待删除的手账'), findsOneWidget);
  });

  testWidgets('REQ-05 统计页心情趋势：区间切换与均值展示', (tester) async {
    final now = DateTime.now();
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await tester.pumpWidget(
      await wrap(
        tester,
        child: const StatsPage(),
        seed: [
          entry('m1', date: key(now), mood: Mood.happy),
          entry(
            'm2',
            date: key(now.subtract(const Duration(days: 1))),
            mood: Mood.sad,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('心情趋势'), findsOneWidget);
    expect(find.text('情绪随时间的变化'), findsOneWidget);
    expect(find.text('区间平均'), findsOneWidget);
    expect(find.text('7 天'), findsOneWidget);

    // 切换到 30 天。
    await tester.tap(find.text('30 天'));
    await tester.pumpAndSettle();
    expect(find.text('90 天'), findsOneWidget);
  });

  testWidgets('REQ-05 无心情数据时显示占位说明', (tester) async {
    await tester.pumpWidget(
      await wrap(
        tester,
        child: const StatsPage(),
        seed: [entry('e1')], // 无心情
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('区间内还没有带心情的手账'), 200);
    expect(find.text('区间内还没有带心情的手账'), findsOneWidget);
  });

  testWidgets('REQ-06 搜索筛选：仅用条件检索并显示命中数量', (tester) async {
    await tester.pumpWidget(
      await wrap(
        tester,
        child: const SearchPage(),
        seed: [
          entry('1', title: '开心的一天', mood: Mood.happy),
          entry('2', title: '难过的一天', mood: Mood.sad),
          entry('3', title: '平静的一天', mood: Mood.calm),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 打开筛选面板，选择心情「开心」。
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😄 开心'));
    await tester.pumpAndSettle();

    // 无关键词、仅筛选条件也能检索（REQ-06.4）。
    expect(find.text('找到 1 篇'), findsOneWidget);
    expect(find.text('开心的一天'), findsOneWidget);
    expect(find.text('难过的一天'), findsNothing);

    // 已选条件 chips 展示，可移除。
    expect(find.text('😄 开心'), findsWidgets);
  });

  testWidgets('REQ-11 分享卡片：纸质浅色模板与署名开关', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    await settings.setShareSignature(true);

    final e = entry('e1', title: '分享测试', content: '正文内容', mood: Mood.happy);
    await tester.pumpWidget(
      await wrap(
        tester,
        child: ShareCardPage(entry: e),
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('分享测试'), findsOneWidget);
    expect(find.text('正文内容'), findsOneWidget);
    expect(find.text('拾页 PageNote'), findsOneWidget, reason: '默认展示署名');

    // 关闭署名后不再显示。
    await settings.setShareSignature(false);
    await tester.pumpAndSettle();
    expect(find.text('拾页 PageNote'), findsNothing);
  });

  testWidgets('REQ-12 活动图标在卡片上展示', (tester) async {
    final e = entry('e1', title: '跑步日')..activities = ['运动', '阅读'];

    await tester.pumpWidget(
      await wrap(
        tester,
        child: HomePage(onOpenEditor: (_, _) {}),
        seed: [e],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('跑步日'), findsOneWidget);
    expect(find.text('🏃'), findsOneWidget);
    expect(find.text('📖'), findsOneWidget);
  });

  testWidgets('REQ-04 编辑页：新条目默认展开一问并可插入正文；编辑旧条目默认收起', (tester) async {
    final todayKey =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    final prompt = promptForDate(todayKey);

    // 新建：默认展开。
    await tester.pumpWidget(await wrap(tester, child: const EditorPage()));
    await tester.pumpAndSettle();
    expect(find.text('今日一问'), findsOneWidget);
    expect(find.text(prompt), findsOneWidget);

    // 插入正文开头（REQ-04.2）：拖动表单直到正文输入框构建（标题框会先出现）。
    expect(find.text(prompt), findsOneWidget);
    final chip = find.widgetWithText(ActionChip, '插入正文');
    expect(chip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(chip.first));
    await gesture.up();
    await tester.pumpAndSettle();
    final contentField = find.widgetWithText(TextField, '记录此刻的所思所感…');
    var guard = 0;
    while (contentField.evaluate().isEmpty && guard++ < 30) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -150));
      await tester.pumpAndSettle();
    }
    final editableTexts = find
        .byType(EditableText)
        .evaluate()
        .map((e) => (e.widget as EditableText).controller.text)
        .toList();
    expect(
      editableTexts.any((t) => t.contains(prompt)),
      isTrue,
      reason: '问题应被插入正文开头，实际输入框内容: $editableTexts',
    );

    // 编辑已有条目：默认收起，可手动展开（REQ-04.3）。
    // 先卸载页面重置滚动位置。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      await wrap(
        tester,
        child: EditorPage(entry: entry('exist', title: '旧手账')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日一问'), findsOneWidget);
    expect(find.text(prompt), findsNothing, reason: '编辑模式默认收起');

    await tester.tap(find.text('今日一问'));
    await tester.pumpAndSettle();
    expect(find.text(prompt), findsOneWidget, reason: '手动展开可见');
  });
}
