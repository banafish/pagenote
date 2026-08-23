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
import 'package:pagenote/models/template.dart';
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
import 'package:pagenote/widgets/entry_card.dart';

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

  testWidgets('时光页视图切换：单列纵向 ↔ 多列并排且持久化', (tester) async {
    final journal = JournalProviderForTest();
    journal.debugSetEntries([
      _entry(id: 'e1', title: '第一条', content: '一一'),
      _entry(id: 'e2', title: '第二条', content: '二二'),
      _entry(id: 'e3', title: '第三条', content: '三三'),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    await tester.pumpWidget(
      _wrap(child: const RootShell(), journal: journal, settings: settings),
    );
    await tester.pumpAndSettle();

    Rect rect(int i) => tester.getRect(find.byType(EntryCard).at(i));

    // 默认单列：同组卡片逐条纵向堆叠、左缘对齐。
    expect(rect(0).left, rect(1).left);
    expect(rect(0).bottom, lessThan(rect(1).top));
    expect(settings.timelineGrid, isFalse);

    // 切到多列：宽屏两列，左右交替流入（树序 = 左列 e1、左列 e3、右列 e2）。
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();
    expect(settings.timelineGrid, isTrue);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(rect(2).left, greaterThan(rect(0).right));
    expect(rect(2).top, closeTo(rect(0).top, 0.5));
    expect(rect(1).top, greaterThan(rect(0).bottom));

    // 再切回单列，布局与偏好都还原。
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    expect(settings.timelineGrid, isFalse);
    expect(rect(0).left, rect(1).left);
    expect(rect(0).bottom, lessThan(rect(1).top));
  });

  testWidgets('四个一级入口与素材/回顾的二级页面均可达（REQ-23/24、NFR-12）', (tester) async {
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

    // 素材：包列表首页——置顶固定入口保证首屏不为空（REQ-26.1）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);

    // 「我的素材」固定入口可达：散装贴纸 + 自建模板的详情页（REQ-26.2）。
    await tester.tap(find.text('我的素材'));
    await tester.pumpAndSettle();
    expect(find.text('散装素材都住这里').hitTestable(), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

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

    // 右上角统计图标进入统计二级页（REQ-24：默认日历直达，
    // 统计内容整体迁移为独立整页、不做删减，REQ-24.3）。
    await tester.tap(find.byIcon(Icons.insights_rounded));
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
    await tester.pageBack();
    await tester.pumpAndSettle();

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

  testWidgets('一级入口切换与进出统计均保留日历选中状态（REQ-23.3/24.5、NFR-09）', (tester) async {
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

    // 素材 → 我的素材详情，离开再回来时首页仍在（详情页是独立路由，
    // REQ-26.9；一级入口切换不打断它之上的浏览状态）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的素材'));
    await tester.pumpAndSettle();
    expect(find.text('散装素材都住这里').hitTestable(), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsNothing);
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);
    expect(find.text('还没有素材包').hitTestable(), findsOneWidget);

    // 回顾 → 日历里选中 15 号，进出统计二级页后选中日期不变（REQ-24.5）。
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
    // 进右上角统计页再返回：统计覆盖日历，返回后选中日期不变（REQ-24.5）。
    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsNothing);
    expect(find.text('总篇数').hitTestable(), findsOneWidget);
    await tester.pageBack();
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

    // 去别的一级入口再回来：选中日期同样原样保留（REQ-23.3 / NFR-09）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.text(selectedLabel).hitTestable(), findsOneWidget);
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
    // 写手账 FAB 只在时光首页提供，其余一级入口不显示。
    expect(find.byType(FloatingActionButton), findsNothing);

    // 回顾默认展示日历（REQ-24.2；窄屏下当日列表在折叠线以下，滚过去再断言）。
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

    // 素材：包列表首页——置顶固定入口 + 空包引导，结构与窄屏一致（REQ-26）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('内置模板').hitTestable(), findsOneWidget);
    expect(find.text('我的素材').hitTestable(), findsOneWidget);
    expect(find.text('还没有素材包').hitTestable(), findsOneWidget);
    // 写手账 FAB 只在时光首页提供，其余一级入口不显示。
    expect(find.byType(FloatingActionButton), findsNothing);

    // 回顾：宽屏（≥900dp）下日历与统计并排同屏（REQ-24.2 宽屏形态）——
    // 左栏日历含当日列表、右栏统计卡组，无需切换即同时可见。
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页').hitTestable(), findsOneWidget);
    expect(find.text('总篇数').hitTestable(), findsOneWidget);
  });

  testWidgets('素材首页与详情页的独立整页形态可用（REQ-26.9、NFR-12）', (tester) async {    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: AppDatabase.inMemory());
    await templates.load();
    await templates.saveTemplate(
      JournalTemplate(id: 'detail-user-1', name: '未分组模板甲', content: '测试'),
    );

    // 编辑器贴纸面板「管理我的素材」以整页打开素材首页（canvas_tool_sheets.dart）。
    await tester.pumpWidget(
      _wrap(
        child: const LibraryPage(),
        journal: journal,
        settings: settings,
        templates: templates,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('素材'), findsOneWidget);
    // 首屏永不为空：内置模板固定入口永远存在（REQ-26.1）。
    expect(find.text('内置模板'), findsOneWidget);
    expect(find.text('我的素材'), findsOneWidget);

    // 点固定入口进入详情页：内置模板 = builtin 网格（只读 + 复制）。
    await tester.tap(find.text('内置模板'));
    await tester.pumpAndSettle();
    expect(find.text('内置模板'), findsWidgets);
    expect(templates.builtinTemplates, isNotEmpty);
    for (final t in templates.builtinTemplates.take(2)) {
      expect(find.text(t.name), findsWidgets, reason: '内置模板 ${t.name} 应可见');
    }
    // 内置详情没有多选以外的整页操作入口，也没有排序条。
    expect(find.text('最近使用'), findsNothing);

    // 「我的素材」入口：排序选择已下线，各处都不再出现排序条。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的素材'));
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsNothing);
    expect(find.text('创建时间'), findsNothing);
    expect(find.text('手动排序'), findsNothing);
    expect(find.text('未分组模板甲'), findsOneWidget);
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
