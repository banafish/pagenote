import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/pages/editor_page.dart';
import 'package:pagenote/pages/home_page.dart';
import 'package:pagenote/pages/quick_note_page.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
    final sqlite = await db.database;
    await sqlite.delete('entries');
    await sqlite.delete('templates');
  });

  Future<Widget> wrap(
    Widget child, {
    List<JournalEntry> seed = const [],
  }) async {
    final journal = JournalProvider(database: db);
    for (final e in seed) {
      await journal.saveEntry(e);
    }
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final templates = TemplateProvider(database: db);
    await templates.load();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: SettingsProvider(prefs)),
        ChangeNotifierProvider.value(value: templates),
      ],
      child: MaterialApp(
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

  JournalEntry quickEntry() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return JournalEntry(
      id: 'q1',
      date: '${now.year}-${two(now.month)}-${two(now.day)}',
      title: '',
      content: '地铁上想到的一个点子',
      isQuickNote: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('速记页：一句话直接入库并标记未整理（REQ-16）', (tester) async {
    final journal = JournalProvider(database: db);
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final templates = TemplateProvider(database: db);
    await templates.load();

    // 模拟生产栈:速记页叠加在主界面 Scaffold 之上,保证提示条有宿主。
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: journal),
          ChangeNotifierProvider.value(value: SettingsProvider(prefs)),
          ChangeNotifierProvider.value(value: templates),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const QuickNotePage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '一句话记下此刻…'),
      '楼下咖啡店的猫超乖',
    );
    await tester.pump();
    await tester.tap(find.text('记下'));
    await tester.pumpAndSettle();

    expect(journal.entries.single.isQuickNote, true);
    expect(journal.entries.single.content, '楼下咖啡店的猫超乖');
    expect(find.text('已存入速记,可稍后整理 ✨'), findsOneWidget);
  });

  testWidgets('时间轴卡片显示「未整理」徽标（REQ-16）', (tester) async {
    await tester.pumpWidget(
      await wrap(HomePage(onOpenEditor: (_, _) {}), seed: [quickEntry()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('未整理'), findsOneWidget);
  });

  testWidgets('编辑速记：保存后 isQuickNote 清除（整理转正,REQ-16）', (tester) async {
    final journal = JournalProvider(database: db);
    await journal.saveEntry(quickEntry());
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final templates = TemplateProvider(database: db);
    await templates.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: journal),
          ChangeNotifierProvider.value(value: SettingsProvider(prefs)),
          ChangeNotifierProvider.value(value: templates),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: EditorPage(entry: journal.entries.single),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 画布上可见速记内容（旧数据自动合成为正文文本框）。
    expect(find.textContaining('地铁上想到的一个点子'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(journal.entries.single.isQuickNote, false, reason: '编辑页保存即转为正式手账');
  });
}
