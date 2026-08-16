import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagenote/app.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/theme/app_theme.dart';

JournalEntry _entry({
  required String id,
  String date = '2026-08-16',
  String title = '测试标题',
  String content = '测试内容',
  Mood? mood,
  List<String> tags = const [],
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
    isFavorite: favorite,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap({
  required Widget child,
  required JournalProvider journal,
  required SettingsProvider settings,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: journal),
      ChangeNotifierProvider.value(value: settings),
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('JournalProvider 统计', () {
    test('空数据统计为 0', () {
      final journal = JournalProviderForTest();
      expect(journal.totalCount, 0);
      expect(journal.streakDays, 0);
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
      expect(journal.streakDays, 3);
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

  test('JournalEntry 序列化往返', () {
    final entry = _entry(
      id: 'a1',
      mood: Mood.calm,
      tags: ['生活', '随笔'],
      favorite: true,
    );
    final restored = JournalEntry.fromMap(entry.toMap());
    expect(restored.id, entry.id);
    expect(restored.date, entry.date);
    expect(restored.mood, Mood.calm);
    expect(restored.tags, ['生活', '随笔']);
    expect(restored.isFavorite, true);
  });

  testWidgets('首页展示空状态与写手账入口', (tester) async {
    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    await tester.pumpWidget(_wrap(
      child: RootShell(),
      journal: journal,
      settings: settings,
    ));
    await tester.pumpAndSettle();

    expect(find.text('拾页'), findsWidgets);
    expect(find.text('写下你的第一页'), findsOneWidget);
    expect(find.text('写手账'), findsOneWidget);
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

    await tester.pumpWidget(_wrap(
      child: RootShell(),
      journal: journal,
      settings: settings,
    ));
    await tester.pumpAndSettle();

    expect(find.text('海边散步'), findsOneWidget);
    expect(find.text('傍晚的海风很舒服'), findsOneWidget);
    expect(find.text('#旅行'), findsOneWidget);
    expect(find.text('1 篇'), findsWidgets);
  });

  testWidgets('导航到日历/统计/设置页', (tester) async {
    final journal = JournalProviderForTest();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    await tester.pumpWidget(_wrap(
      child: RootShell(),
      journal: journal,
      settings: settings,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.text('这一天还是空白的一页'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('总篇数'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('v1.0.0 · 拾起生活中的每一页'),
      200,
    );
    expect(find.text('v1.0.0 · 拾起生活中的每一页'), findsOneWidget);
  });
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 测试专用 Provider：跳过数据库加载，直接注入内存数据。
class JournalProviderForTest extends JournalProvider {
  final List<JournalEntry> _seeded = [];

  @override
  List<JournalEntry> get entries => List.unmodifiable(_seeded);

  @override
  bool get loaded => true;

  void debugSetEntries(List<JournalEntry> entries) {
    _seeded
      ..clear()
      ..addAll(entries);
  }
}
