import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/template_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('内置模板 ≥4 套且 load 自动补种（REQ-09.1）', () async {
    expect(builtinTemplates.length, greaterThanOrEqualTo(4));
    expect(
      builtinTemplates.map((t) => t.name),
      containsAll(['每日复盘', '读书笔记', '旅行手账', '周记']),
    );

    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();
    expect(provider.builtinTemplates.length, builtinTemplates.length);

    // 删除内置模板的行后再次 load，应重新补种。
    await db.deleteAllTemplates();
    await provider.load();
    expect(provider.builtinTemplates.length, builtinTemplates.length);

    await db.close();
  });

  test('另存为模板 / 重命名 / 删除（内置不可删）（REQ-09.3）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final entry = JournalEntry(
      id: 'e1',
      date: '2026-08-16',
      title: '我的模板标题',
      content: '【分节】\n',
      tags: ['自定义'],
      createdAt: DateTime(2026, 8, 16),
      updatedAt: DateTime(2026, 8, 16),
    );
    final saved = await provider.saveFromEntry(entry, '我的模板');
    expect(provider.userTemplates.length, 1);
    expect(saved.title, '我的模板标题');
    expect(saved.tags, ['自定义']);
    expect(saved.builtin, isFalse);

    // 重命名。
    saved.name = '改名后';
    await provider.saveTemplate(saved);
    expect(provider.userTemplates.single.name, '改名后');

    // 删除自建模板。
    await provider.deleteTemplate(saved.id);
    expect(provider.userTemplates, isEmpty);

    // 内置模板不可删。
    final builtin = provider.builtinTemplates.first;
    await provider.deleteTemplate(builtin.id);
    expect(
      provider.templates.where((t) => t.id == builtin.id).single,
      isNotNull,
    );

    await db.close();
  });

  test('模板导入：合并去重与覆盖（REQ-09.4）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final incoming = [
      JournalTemplate(
        id: 'tpl-x',
        name: '备份模板',
        content: '内容',
        updatedAt: DateTime(2026, 8, 16),
      ),
      // 与内置同 id 的较旧版本 → 不覆盖。
      builtinTemplates.first.copy()
        ..name = '被篡改的内置名'
        ..updatedAt = DateTime(2020, 1, 1),
    ];

    await provider.importTemplates(incoming, overwrite: false);
    expect(
      provider.templates.where((t) => t.id == 'tpl-x').single.name,
      '备份模板',
    );
    expect(provider.builtinTemplates.first.name, isNot('被篡改的内置名'));

    // 覆盖导入后重新补种内置模板。
    await provider.importTemplates([], overwrite: true);
    expect(provider.builtinTemplates.length, builtinTemplates.length);
    expect(provider.userTemplates, isEmpty);

    await db.close();
  });
}
