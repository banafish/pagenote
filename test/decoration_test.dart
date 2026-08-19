import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/pages/editor_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('内置纸张 ≥8 款纹理 + 素笺,id 查找正确（REQ-13）', () {
    expect(
      paperStyles.length,
      greaterThanOrEqualTo(9),
      reason: '8 款纹理 + 1 款素笺',
    );
    expect(
      paperStyles.where((p) => !p.isPlain).length,
      greaterThanOrEqualTo(8),
      reason: '至少 8 款程序绘制的纹理',
    );
    expect(paperById(''), isNull);
    expect(paperById('unknown'), isNull);
    expect(paperById('dots')!.name, '云点');
  });

  test('贴纸 JSON 序列化往返,损坏数据退化为空列表（REQ-13）', () {
    final stickers = [
      Sticker(emoji: '🌸', dx: 0.25, dy: 0.1, scale: 1.4, rotation: -30),
      Sticker(emoji: '⭐️'),
    ];
    final raw = encodeStickers(stickers);
    expect(raw, isNotEmpty);

    final decoded = decodeStickers(raw);
    expect(decoded.length, 2);
    expect(decoded.first.emoji, '🌸');
    expect(decoded.first.dx, closeTo(0.25, 1e-9));
    expect(decoded.first.scale, closeTo(1.4, 1e-9));
    expect(decoded.first.rotation, closeTo(-30, 1e-9));
    expect(decoded.last.dx, 0.5);

    // 空 / 非法输入。
    expect(decodeStickers(''), isEmpty);
    expect(decodeStickers('not-json'), isEmpty);
    expect(decodeStickers('[{"x":0.5}]'), isEmpty, reason: '缺 emoji 的项被丢弃');
  });

  test('条目 toMap/fromMap 往返保留装饰与速记标记', () {
    final now = DateTime(2026, 8, 16, 10);
    final entry = JournalEntry(
      id: 'd1',
      date: '2026-08-16',
      title: '装饰页',
      content: '内容',
      paper: 'stars',
      stickers: [Sticker(emoji: '🌙', dx: 0.8, dy: 0.2, rotation: 15)],
      isQuickNote: true,
      createdAt: now,
      updatedAt: now,
    );

    final restored = JournalEntry.fromMap(entry.toMap());
    expect(restored.paper, 'stars');
    expect(restored.stickers.length, 1);
    expect(restored.stickers.first.emoji, '🌙');
    expect(restored.stickers.first.rotation, 15);
    expect(restored.isQuickNote, true);
  });

  test('装饰随备份 zip 导出并在导入后保留（REQ-13 + REQ-03）', () async {
    final now = DateTime(2026, 8, 16, 10);
    final entry = JournalEntry(
      id: 'd2',
      date: '2026-08-16',
      title: '带装饰的备份',
      content: '内容',
      paper: 'petals',
      stickers: [Sticker(emoji: '🌷', dx: 0.1, dy: 0.9, scale: 2)],
      createdAt: now,
      updatedAt: now,
    );

    final bytes = await BackupService.instance.buildZip(
      entries: [entry],
      templates: [],
    );
    final data = BackupService.instance.parseBackup(bytes);

    expect(data.entries.single.paper, 'petals');
    expect(data.entries.single.stickers.single.emoji, '🌷');
    expect(data.entries.single.stickers.single.scale, 2);
  });

  test('PaperPainter 各纸样在浅/深两种模式下均可绘制', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (final paper in paperStyles) {
      for (final dark in [false, true]) {
        PaperPainter(paper, dark: dark).paint(canvas, const Size(400, 800));
      }
    }
    recorder.endRecording().dispose();
  });

  testWidgets('编辑页装饰：选纸张、加贴纸并保存后持久化（REQ-13 画布版）', (tester) async {
    final db = AppDatabase.inMemory();
    final sqlite = await db.database;
    await sqlite.delete('entries');
    await sqlite.delete('templates');

    final journal = JournalProvider(database: db);
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final templates = TemplateProvider(database: db);
    await templates.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: journal),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: templates),
          ChangeNotifierProvider.value(
            value: CustomStickerProvider(database: db),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const EditorPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 底部工具栏打开贴纸面板,切到「表情」页签的「植物」类目添加一枚 emoji 贴纸;
    // 面板为常驻抽屉（REQ-17.3）,插入后需手动收起才能继续操作工具栏。
    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(BottomSheet), matching: finder);
    // 最近使用横条里也会出现同一枚 emoji,限定在页签网格内点选。
    Finder inGrid(String text) => inSheet(
      find.descendant(of: find.byType(GridView), matching: find.text(text)),
    );
    await tester.tap(find.byTooltip('贴纸'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('表情')));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('植物')));
    await tester.pumpAndSettle();
    await tester.tap(inGrid('🌸'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    // 选择「方格」纸张。
    await tester.tap(find.byTooltip('纸张'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('方格'));
    await tester.pumpAndSettle();

    // 点标题占位（首点选中,再点打开文字编辑）输入标题。
    final titleHint = find.text('点击输入标题…');
    await tester.tap(titleHint, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(titleHint, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '装饰的手账');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 保存。
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    final saved = journal.entries.single;
    expect(saved.paper, 'grid', reason: '画布纸张同步进结构化字段');
    expect(saved.title, '装饰的手账');
    final canvas = saved.canvas!;
    expect(canvas.paperId, 'grid');
    final sticker = canvas.elements.whereType<StickerElement>().single;
    expect(sticker.key, 'emoji:🌸');
    expect(canvas.firstOfRole('title')?.text, '装饰的手账');

    await db.close();
  });
}
