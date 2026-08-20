import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/app.dart';
import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/pages/calendar_page.dart';
import 'package:pagenote/pages/library_page.dart';
import 'package:pagenote/pages/settings_page.dart';
import 'package:pagenote/pages/stats_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/theme/app_theme.dart';
import 'package:pagenote/utils/date_utils.dart';

JournalEntry _entry({
  required String id,
  String date = '2026-08-16',
  String title = '测试标题',
  String content = '测试内容',
  Mood? mood,
  List<String> tags = const [],
  List<String> activities = const [],
  bool favorite = false,
}) {
  final now = DateTime.now();
  return JournalEntry(
    id: id,
    date: date,
    title: title,
    content: content,
    mood: mood,
    tags: tags,
    activities: activities,
    isFavorite: favorite,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap({
  required Widget child,
  required JournalProvider journal,
  required SettingsProvider settings,
  TemplateProvider? templates,
  CustomStickerProvider? stickers,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: journal),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(
        value: templates ?? TemplateProvider(database: AppDatabase.inMemory()),
      ),
      // 一级入口常驻挂载（NFR-09），「素材」里的贴纸页签始终需要它。
      ChangeNotifierProvider.value(
        value:
            stickers ?? CustomStickerProvider(database: AppDatabase.inMemory()),
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
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    // Widget 测试运行在 fake-async 环境，跨 isolate 的 ffi 结果无法送达，
    // 必须使用同 isolate 的 ffi 工厂。
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('JournalProvider 统计', () {
    test('空数据统计为 0', () {
      final journal = JournalProviderForTest();
      expect(journal.totalCount, 0);
      expect(journal.streakDays(), 0);
      expect(journal.totalWords, 0);
    });

    test('标签按使用次数排序', () {
      final journal = JournalProviderForTest();
      journal.debugSetEntries([
        _entry(id: '1', tags: ['旅行']),
        _entry(id: '2', tags: ['日常', '旅行']),
        _entry(id: '3', tags: ['旅行', '日常']),
      ]);
      expect(journal.allTags, ['旅行', '日常']);
      expect(journal.totalCount, 3);
    });

    test('连续天数统计', () {
      final journal = JournalProviderForTest();
      final today = DateTime.now();
      journal.debugSetEntries([
        _entry(id: '1', date: _key(today)),
        _entry(id: '2', date: _key(today.subtract(const Duration(days: 1)))),
        _entry(id: '3', date: _key(today.subtract(const Duration(days: 2)))),
        _entry(id: '4', date: _key(today.subtract(const Duration(days: 9)))),
      ]);
      expect(journal.streakDays(), 3);
    });

    test('心情分布', () {
      final journal = JournalProviderForTest();
      journal.debugSetEntries([
        _entry(id: '1', mood: Mood.happy),
        _entry(id: '2', mood: Mood.happy),
        _entry(id: '3', mood: Mood.sad),
      ]);
      expect(journal.moodCounts[Mood.happy], 2);
      expect(journal.moodCounts[Mood.sad], 1);
      expect(journal.dominantMood, Mood.happy);
    });
  });

  test('JournalEntry 序列化往返（含活动与删除时间）', () {
    final entry = _entry(
      id: 'a1',
      mood: Mood.calm,
      tags: ['生活', '随笔'],
      activities: ['运动', '阅读'],
      favorite: true,
    );
    final map = entry.toMap();
    expect(map['activities'], '运动\u001F阅读');
    expect(map['deletedAt'], isNull);

    final restored = JournalEntry.fromMap(map);
    expect(restored.id, entry.id);
    expect(restored.date, entry.date);
    expect(restored.mood, Mood.calm);
    expect(restored.tags, ['生活', '随笔']);
    expect(restored.activities, ['运动', '阅读']);
    expect(restored.isFavorite, true);
    expect(restored.deletedAt, isNull);
  });

  testWidgets('首页展示空状态、今日一问与写作入口（REQ-04.4）', (tester) async {
    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    await tester.pumpWidget(
      _wrap(child: const RootShell(), journal: journal, settings: settings),
    );
    await tester.pumpAndSettle();

    expect(find.text('拾页'), findsWidgets);
    expect(find.text('写下你的第一页'), findsOneWidget);
    expect(find.text('写手账'), findsOneWidget);
    // 空状态展示今日一问（REQ-04.4）。
    expect(find.text('今日一问'), findsOneWidget);
    expect(find.text('以此开始写作'), findsOneWidget);
  });

  testWidgets('首页时间轴渲染条目卡片', (tester) async {
    final journal = JournalProviderForTest();
    journal.debugSetEntries([
      _entry(
        id: 'e1',
        title: '海边散步',
        content: '傍晚的海风很舒服',
        mood: Mood.happy,
        tags: ['旅行'],
      ),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    await tester.pumpWidget(
      _wrap(child: const RootShell(), journal: journal, settings: settings),
    );
    await tester.pumpAndSettle();

    expect(find.text('海边散步'), findsOneWidget);
    expect(find.text('傍晚的海风很舒服'), findsOneWidget);
    expect(find.text('#旅行'), findsOneWidget);
    expect(find.text('1 篇'), findsWidgets);
  });

  testWidgets('四个一级入口与素材/回顾子页签均可达（REQ-23/24、NFR-12）', (tester) async {
    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();

    await tester.pumpWidget(
      _wrap(
        child: const RootShell(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();

    // 时光：默认首页（一级入口 1）。
    expect(find.text('写下你的第一页').hitTestable(), findsOneWidget);

    // 素材：默认落在「模板」子页签——内置模板保证首屏不为空（REQ-23.2）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);

    // 切到「贴纸」子页签（REQ-23：素材内两个子页签可达）。
    await tester.tap(find.text('贴纸'));
    await tester.pumpAndSettle();
    expect(find.text('还没有自己的素材').hitTestable(), findsOneWidget);

    // 回顾：默认落在「日历」（REQ-24.2），高频项不为合并多付一次点击。
    // 默认 800 宽减去侧栏 81 后日历列仅 719（<760），当日列表在折叠线
    // 以下，滚过去再断言（列宽判断见 calendar_page.dart 的 LayoutBuilder）。
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这一天还是空白的一页'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CalendarPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsOneWidget);

    // 切到「统计」子页签（REQ-24：回顾内两个子页签可达），
    // 统计页内容整体迁移、不做删减（REQ-24.3）。
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('总篇数').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('心情趋势'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(StatsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('心情趋势').hitTestable(), findsOneWidget);

    // 设置（一级入口 4）。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('主题模式').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('v1.2.0 · 拾起生活中的每一页'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('v1.2.0 · 拾起生活中的每一页'), findsOneWidget);
  });

  testWidgets('一级入口切换保留子页签与日历选中状态（REQ-23.3/24.5、NFR-09）', (tester) async {
    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();

    await tester.pumpWidget(
      _wrap(
        child: const RootShell(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();

    // 素材 → 贴纸子页签，离开再回来时仍停在贴纸（REQ-23.3）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('贴纸'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('还没有自己的素材').hitTestable(), findsNothing);
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('还没有自己的素材').hitTestable(), findsOneWidget);

    // 回顾 → 日历里选中 15 号，切到统计再切回，选中日期不变（REQ-24.5）。
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final selectedLabel = DateUtils2.friendlyDate(
      DateUtils2.dateKey(DateTime(now.year, now.month, 15)),
    );
    await tester.scrollUntilVisible(
      find.text('15'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CalendarPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsNothing);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(selectedLabel),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CalendarPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text(selectedLabel).hitTestable(), findsOneWidget);

    // 去别的一级入口再回来：仍停在「统计」子页签（REQ-24.5 / NFR-09）。
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.text('总篇数').hitTestable(), findsOneWidget);
  });

  testWidgets('窄屏 NavigationBar 呈现相同的目的地与子页签结构（NFR-11）', (tester) async {
    // 固定成手机竖屏：底栏 + 悬浮 FAB 形态（REQ-24.6）。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();

    await tester.pumpWidget(
      _wrap(
        child: const RootShell(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();

    // 仍是 4 个目的地 + 写手账 FAB，与宽屏 NavigationRail 同构。
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 素材默认落在「模板」子页签。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);

    // 回顾默认落在「日历」子页签（窄屏下当日列表在折叠线以下，滚过去再断言）。
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这一天还是空白的一页'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CalendarPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // ensureVisible 跳到新位置后需要再出一帧，hit-test 才基于新布局。
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsOneWidget);
  });

  testWidgets('宽屏 NavigationRail 呈现相同的目的地与子页签结构（NFR-11）', (tester) async {
    // ≥700dp 走侧边导航栏；≥1050 为展开式（带文字标签）。
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();

    await tester.pumpWidget(
      _wrap(
        child: const RootShell(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();

    // 侧栏形态 + 4 个目的地（展开式侧栏直接带文字标签，与窄屏同一份列表）+ FAB 仍在。
    // 首个目的地处于选中态，渲染的是 selectedIcon（填充变体）而非 outlined。
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byIcon(Icons.auto_stories), findsWidgets, reason: '时光：选中态图标');
    expect(find.text('时光'), findsOneWidget);
    expect(find.text('素材'), findsOneWidget);
    expect(find.text('回顾'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 素材：默认落在「模板」子页签，可切到「贴纸」——结构与窄屏一致。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);
    await tester.tap(find.text('贴纸'));
    await tester.pumpAndSettle();
    expect(find.text('还没有自己的素材').hitTestable(), findsOneWidget);

    // 回顾：宽屏（≥900dp）下日历与统计并排同屏（REQ-24.2 宽屏形态）——
    // 左栏日历含当日列表、右栏统计卡组，无需切换即同时可见。
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsOneWidget);
    expect(find.text('总篇数').hitTestable(), findsOneWidget);
  });

  testWidgets('素材管理的独立整页形态仍可用（REQ-23.5/23.6、NFR-12）', (tester) async {    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();

    // 素材包导入回跳打开的模板管理整页（main.dart / 设置页手动导入）：
    // 不带子页签栏，标题与高亮定位行为与一级入口形态一致。
    await tester.pumpWidget(
      _wrap(
        child: const TemplateManagerPage(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('手账模板'), findsOneWidget);
    expect(find.text('内置模板'), findsOneWidget);
    expect(find.text('模板'), findsNothing, reason: '整页形态不渲染子页签栏');

    // 编辑器贴纸面板「管理」打开的素材管理整页（canvas_tool_sheets.dart）。
    await tester.pumpWidget(
      _wrap(
        child: const StickerManagerPage(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的素材'), findsOneWidget);
    expect(find.text('还没有自己的素材'), findsOneWidget);
  });
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 测试专用 Provider：跳过数据库加载，直接注入内存数据。
class JournalProviderForTest extends JournalProvider {
  final List<JournalEntry> _seeded = [];

  JournalProviderForTest() : super(database: AppDatabase.inMemory());

  @override
  List<JournalEntry> get entries => List.unmodifiable(_seeded);

  List<JournalEntry> get backing => _seeded;

  @override
  bool get loaded => true;

  void debugSetEntries(List<JournalEntry> entries) {
    _seeded
      ..clear()
      ..addAll(entries);
  }
}
