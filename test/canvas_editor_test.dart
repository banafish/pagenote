import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/data/prompts.dart';
import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/pages/editor_page.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/utils/date_utils.dart';
import 'package:pagenote/widgets/canvas/canvas_editor.dart';
import 'package:pagenote/widgets/canvas/canvas_view.dart';
import 'package:pagenote/widgets/canvas/canvas_zoom.dart';

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

  Future<Widget> wrap() async {
    final journal = JournalProvider(database: db);
    await journal.load();
    final prefs = await SharedPreferences.getInstance();
    final templates = TemplateProvider(database: db);
    await templates.load();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: journal),
        ChangeNotifierProvider.value(value: SettingsProvider(prefs)),
        ChangeNotifierProvider.value(value: templates),
        ChangeNotifierProvider.value(
          value: CustomStickerProvider(database: db),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: EditorPage(),
      ),
    );
  }

  testWidgets('画布编辑器：加贴纸、选中出操作条、图层置顶置底（调研二阶段）', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();
    expect(find.byType(CanvasEditor), findsOneWidget);
    expect(find.byType(CanvasView), findsOneWidget, reason: '编辑层内嵌静态渲染层');

    // 添加两枚贴纸（列表顺序即 z 序,后加的在上）。
    // REQ-17.3：面板为常驻抽屉,点选后不关闭,可连续插入。
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
    for (final _ in [1, 2]) {
      await tester.tap(inGrid('🌸'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    // 选中第二枚贴纸（新增后自动选中）→ 操作条出现。
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('置底'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 删除选中贴纸。
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsNothing, reason: '删除后取消选中,操作条收起');

    // 撤销恢复被删的贴纸。
    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();

    // 输入标题后保存（空内容会被保存拦截）。
    final titleHint = find.text('点击输入标题…');
    await tester.tap(titleHint, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(titleHint, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '贴纸页');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    final journal = tester
        .element(find.byType(MaterialApp))
        .read<JournalProvider>();
    final saved = journal.entries.single;
    expect(saved.canvas, isNotNull);
    expect(
      saved.canvas!.elements.whereType<StickerElement>().length,
      2,
      reason: '两枚贴纸均持久化',
    );
  });

  testWidgets('素材面板：收藏与最近使用合并为一条可切换素材带', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(BottomSheet), matching: finder);
    Finder inGrid(String text) => inSheet(
      find.descendant(of: find.byType(GridView), matching: find.text(text)),
    );
    await tester.tap(find.byTooltip('贴纸'));
    await tester.pumpAndSettle();

    // 两侧都空时整条不出场,不占面板高度。
    expect(find.text('收藏'), findsNothing);
    expect(find.text('最近使用'), findsNothing);

    // 从网格选一枚 emoji：最近使用侧非空,带子出现且自动落到该侧。
    await tester.tap(inSheet(find.text('表情')));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('植物')));
    await tester.pumpAndSettle();
    await tester.tap(inGrid('🌸'));
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsOneWidget);
    // 收藏侧为空时不可点,点也不切走。
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsOneWidget, reason: '空侧切换应无效');

    // 收藏这枚 emoji（横条角标星标）：收藏侧非空,切得过去也切得回来。
    final star = inSheet(find.byIcon(Icons.star_border_rounded)).first;
    await tester.tap(star);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('长按可拖动排序'), findsOneWidget, reason: '收藏侧带排序提示');
    await tester.tap(find.text('最近使用'));
    await tester.pumpAndSettle();
    expect(find.text('长按可拖动排序'), findsNothing);
  });

  testWidgets('今日手账：一键套用并自动填入每日一问（调研二阶段第 3 条）', (tester) async {
    final prompt = promptForDate(DateUtils2.dateKey(DateTime.now()));

    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('今日手账'));
    await tester.pumpAndSettle();

    // 每日一问自动填入正文占位。
    expect(find.textContaining(prompt), findsOneWidget);
    expect(find.textContaining('今日一问'), findsOneWidget);

    // 保存后结构化 content 同步。
    final journal = tester
        .element(find.byType(EditorPage))
        .read<JournalProvider>();
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(journal.entries.single.content, contains(prompt));
  });

  testWidgets('添加自由文字：工具栏入口 + 花样字体编辑面板', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('文字'));
    await tester.pumpAndSettle();

    // 编辑面板弹出：内容输入 + 花样字体选项（调研一阶段）。
    await tester.enterText(find.byType(TextField), '自由文字块');
    await tester.tap(find.text('霞鹜文楷'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('自由文字块'), findsOneWidget);
  });

  testWidgets('旧条目在编辑器中自动合成等价画布（调研三阶段迁移）', (tester) async {
    final now = DateTime.now();
    final legacy = JournalEntry(
      id: 'legacy',
      date: DateUtils2.dateKey(now),
      title: '旧式手账',
      content: '纯文本流时代的正文',
      createdAt: now,
      updatedAt: now,
    );
    final journal = JournalProvider(database: db);
    await journal.saveEntry(legacy);

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

    // 打开已有条目先进查看态,点右上角编辑图标进入编辑。
    expect(find.byType(CanvasView), findsOneWidget);
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    // 标题与正文渲染在画布上,且是可选中元素。
    expect(find.text('旧式手账'), findsOneWidget);
    expect(find.text('纯文本流时代的正文'), findsOneWidget);

    // 保存后 canvas 列持久化,旧字段同步一致。
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    final saved = journal.entries.single;
    expect(saved.canvas, isNotNull);
    expect(saved.canvas!.firstOfRole('title')!.text, '旧式手账');
    expect(saved.title, '旧式手账');
    expect(saved.content, '纯文本流时代的正文');
  });

  testWidgets('查看态：整页自适应视口,缩放层替代滚动（免上下滑动）', (tester) async {
    final now = DateTime.now();
    final legacy = JournalEntry(
      id: 'legacy-view',
      date: DateUtils2.dateKey(now),
      title: '查看态手账',
      content: '正文内容',
      createdAt: now,
      updatedAt: now,
    );
    final journal = JournalProvider(database: db);
    await journal.saveEntry(legacy);
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

    // 查看态:整页由 CanvasZoom 适配视口,不再是纵向滚动视图。
    final zoom = tester.state(find.byType(CanvasZoom)) as CanvasZoomState;
    expect(zoom.widget.fitToViewport, isTrue);
    expect(zoom.widget.wheelMode, CanvasWheelMode.zoom);
    // 竖版 3:4 页面在 800×600 视口内按高度适配（小于 1 倍基准 720 宽）。
    await tester.pumpAndSettle();
    expect(zoom.scale, lessThan(1.0));

    // 切到编辑态同样有缩放层（空白处双指缩放画布）。
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    final editZoom = tester.state(find.byType(CanvasZoom)) as CanvasZoomState;
    expect(editZoom.widget.fitToViewport, isFalse);
  });

  testWidgets('画布比例：纸张面板切换 16:9 横版并等比重排元素', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    final editor = tester.state(find.byType(CanvasEditor)) as CanvasEditorState;
    expect(editor.widget.canvas.height, closeTo(4 / 3, 1e-9));

    await tester.tap(find.byTooltip('纸张'));
    await tester.pumpAndSettle();
    expect(find.text('画布比例'), findsOneWidget);
    await tester.tap(find.text('16:9 横版'));
    await tester.pumpAndSettle();

    final canvas = editor.widget.canvas;
    expect(canvas.height, closeTo(9 / 16, 1e-9), reason: '空白新页切横版后保持 16:9');
    // 元素纵坐标按新旧高度等比压缩（synthesizeCanvas 日期组件 y=0.05）。
    final k = (9 / 16) / (4 / 3);
    expect(
      canvas.componentOf(ComponentKind.date)!.y,
      closeTo(0.05 * k, 1e-9),
    );
  });

  testWidgets('画布比例：纸张面板切换 9:16 竖版并等比重排元素', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    final editor = tester.state(find.byType(CanvasEditor)) as CanvasEditorState;
    await tester.tap(find.byTooltip('纸张'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:16 竖版'));
    await tester.pumpAndSettle();

    final canvas = editor.widget.canvas;
    expect(canvas.height, closeTo(16 / 9, 1e-9), reason: '空白新页切竖版后保持 9:16');
    final k = (16 / 9) / (4 / 3);
    expect(
      canvas.componentOf(ComponentKind.date)!.y,
      closeTo(0.05 * k, 1e-9),
    );
  });

  testWidgets('画布比例：自定义宽高,超范围按上下限收拢', (tester) async {
    await tester.pumpWidget(await wrap());
    await tester.pumpAndSettle();

    final editor = tester.state(find.byType(CanvasEditor)) as CanvasEditorState;
    await tester.tap(find.byTooltip('纸张'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义画布比例'), findsOneWidget);

    // 输入框预填当前 3:4。
    expect(find.text('约为 3:4 竖版'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('确定'),
    );
    await tester.enterText(fields.at(0), '5');
    await tester.enterText(fields.at(1), '7');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(editor.widget.canvas.height, closeTo(1.4, 1e-9));

    // 重新打开面板：自定义 chip 选中并带出当前比例 5:7。
    await tester.tap(find.byTooltip('纸张'));
    await tester.pumpAndSettle();
    expect(find.text('自定义 5:7'), findsOneWidget);

    // 10:1 → 高 0.1 倍页宽,低于下限收到 0.5（预览需提示已限制）。
    await tester.tap(find.text('自定义 5:7'));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(0), '10');
    await tester.enterText(fields.at(1), '1');
    await tester.pump();
    expect(find.textContaining('已限制在'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(editor.widget.canvas.height, closeTo(0.5, 1e-9));
  });
}
