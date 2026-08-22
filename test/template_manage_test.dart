import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/template_provider.dart';

/// 模板管理页的数据层（REQ-18）：手动排序、套用记录、复制。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final builtinCount = builtinTemplates.length;

  /// 每个用例一套独立的库，用完即关。
  Future<TemplateProvider> newProvider() async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = TemplateProvider(database: db);
    await provider.load();
    return provider;
  }

  Future<JournalTemplate> addUser(
    TemplateProvider provider,
    String id,
    String name, {
    required DateTime createdAt,
    DateTime? lastUsedAt,
    int sortIndex = 0,
  }) async {
    final template = JournalTemplate(
      id: id,
      name: name,
      content: '正文',
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      sortIndex: sortIndex,
    );
    await provider.saveTemplate(template);
    return template;
  }

  List<String> userNames(TemplateProvider provider) =>
      provider.userTemplates.map((t) => t.name).toList();

  /// 内置模板恒在整表最前（REQ-18.4）。
  void expectBuiltinFirst(TemplateProvider provider) {
    expect(
      provider.templates.take(builtinCount).every((t) => t.builtin),
      isTrue,
      reason: '内置模板恒在最前',
    );
  }

  test('用户模板按 sortIndex 升序，内置模板恒在最前（REQ-18.4）', () async {
    final provider = await newProvider();
    await addUser(
      provider,
      'u-jia',
      '甲',
      createdAt: DateTime(2026, 8, 1),
      lastUsedAt: DateTime(2026, 8, 18),
      sortIndex: 2,
    );
    await addUser(
      provider,
      'u-yi',
      '乙',
      createdAt: DateTime(2026, 8, 10),
      sortIndex: 0,
    );
    await addUser(
      provider,
      'u-bing',
      '丙',
      createdAt: DateTime(2026, 8, 15),
      lastUsedAt: DateTime(2026, 8, 12),
      sortIndex: 1,
    );

    expect(userNames(provider), ['乙', '丙', '甲'], reason: 'sortIndex 升序');
    expectBuiltinFirst(provider);
  });

  test('markUsed 只刷新 lastUsedAt，不改变列表次序（REQ-18.4）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = TemplateProvider(database: db);
    await provider.load();
    await addUser(
      provider,
      'u-jia',
      '甲',
      createdAt: DateTime(2026, 8, 1),
      sortIndex: 2,
    );
    await addUser(
      provider,
      'u-yi',
      '乙',
      createdAt: DateTime(2026, 8, 2),
      sortIndex: 0,
    );
    await addUser(provider, 'u-bing', '丙', createdAt: DateTime(2026, 8, 3), sortIndex: 1);

    await provider.markUsed('u-jia');
    expect(provider.byId('u-jia')!.lastUsedAt, isNotNull, reason: '套用时间已记录');
    expect(userNames(provider), ['乙', '丙', '甲'], reason: '套用不改变手动序');
    expectBuiltinFirst(provider);

    // 落库后重新读出，lastUsedAt 与次序都还在。
    final reopened = TemplateProvider(database: db);
    await reopened.load();
    expect(reopened.byId('u-jia')!.lastUsedAt, isNotNull);
    expect(userNames(reopened), ['乙', '丙', '甲']);
  });

  test('复制内置模板得到可编辑的副本，画布为深拷贝（REQ-18.3）', () async {
    final provider = await newProvider();
    final builtin = provider.byId('builtin-daily-review')!;
    final originPaper = builtin.canvas!.paperId;
    final originKey = builtin.canvas!.stickers.first.key;

    final copy = await provider.duplicateTemplate(builtin);
    expect(copy.builtin, isFalse, reason: '副本可改名、编辑、删除');
    expect(copy.id, isNot(builtin.id));
    expect(copy.name, '${builtin.name} 副本');
    expect(provider.userTemplates.single.id, copy.id);
    expect(provider.builtinTemplates.length, builtinCount, reason: '原模板仍在');

    // 改副本不影响原模板。
    copy.canvas!.paperId = 'sakura';
    copy.canvas!.stickers.first.key = 'vec:cat';
    expect(builtin.canvas!.paperId, originPaper);
    expect(builtin.canvas!.stickers.first.key, originKey);
    expect(provider.byId(builtin.id)!.canvas!.paperId, originPaper);
    expect(provider.byId(builtin.id)!.canvas!.stickers.first.key, originKey);

    // 再复制一次自动去重命名。
    final again = await provider.duplicateTemplate(builtin);
    expect(again.name, '${builtin.name} 副本 (2)');

    // 副本可删除。
    await provider.deleteTemplate(copy.id);
    expect(provider.userTemplates.single.id, again.id);
  });

  test('手动排序持久化，重新 load 顺序不变且不影响内置（REQ-18.4）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = TemplateProvider(database: db);
    await provider.load();

    final a = await addUser(
      provider,
      'u-a',
      '甲',
      createdAt: DateTime(2026, 8, 1),
      sortIndex: 0,
    );
    final b = await addUser(
      provider,
      'u-b',
      '乙',
      createdAt: DateTime(2026, 8, 2),
      sortIndex: 1,
    );
    final c = await addUser(
      provider,
      'u-c',
      '丙',
      createdAt: DateTime(2026, 8, 3),
      sortIndex: 2,
    );

    await provider.reorderUserTemplates([c.id, a.id, b.id]);
    expect(userNames(provider), ['丙', '甲', '乙']);

    // 换一个 provider 重新读库：顺序与 sortIndex 都还在。
    final reopened = TemplateProvider(database: db);
    await reopened.load();
    expect(userNames(reopened), ['丙', '甲', '乙']);
    expect(reopened.byId(c.id)!.sortIndex, 0);
    expect(reopened.byId(a.id)!.sortIndex, 1);
    expect(reopened.byId(b.id)!.sortIndex, 2);

    expect(reopened.builtinTemplates.length, builtinCount);
    expect(
      reopened.builtinTemplates.every((t) => t.sortIndex == 0),
      isTrue,
      reason: '内置模板不参与拖拽',
    );
    expectBuiltinFirst(reopened);
  });
}
