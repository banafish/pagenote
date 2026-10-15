import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/utils/attachments.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  JournalEntry entry(
    String id, {
    String date = '2026-08-16',
    String content = '内容',
    List<String> images = const [],
  }) {
    final now = DateTime(2026, 8, 16, 12, 0);
    return JournalEntry(
      id: id,
      date: date,
      title: '标题 $id',
      content: content,
      images: images,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('软删除进入回收站并从时间轴/搜索/统计中移除（REQ-02.1/2.3）', () async {
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.saveEntry(entry('e1'));
    await provider.saveEntry(entry('e2'));
    expect(provider.totalCount, 2);

    await provider.softDelete('e1');
    expect(provider.entries.map((e) => e.id), ['e2']);
    expect(provider.trashedEntries.map((e) => e.id), ['e1']);
    expect(provider.totalCount, 1);

    // 数据库层：软删除条目不出现在常规查询中。
    expect((await db.getAllEntries()).map((e) => e.id), ['e2']);
    expect((await db.search('内容')).map((e) => e.id), ['e2']);
    expect((await db.getEntriesByDate('2026-08-16')).length, 1);

    await provider.restoreEntry('e1');
    expect(provider.totalCount, 2);
    expect(provider.trashedEntries, isEmpty);

    await db.close();
  });

  test('彻底删除与清空回收站，连同附件文件（REQ-02.2/2.4）', () async {
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);

    final deletedFiles = <String>[];
    // 拦截附件删除，记录被清理的文件。
    Attachments.delete = (path) async => deletedFiles.add(path);

    await provider.saveEntry(entry('e1', images: ['/tmp/a.jpg', '/tmp/b.jpg']));
    await provider.softDelete('e1');

    await provider.permanentDelete('e1');
    expect(provider.entries, isEmpty);
    expect(provider.trashedEntries, isEmpty);
    expect(deletedFiles, containsAll(['/tmp/a.jpg', '/tmp/b.jpg']));

    // 清空回收站。
    await provider.saveEntry(entry('e2', images: ['/tmp/c.jpg']));
    await provider.softDelete('e2');
    await provider.emptyTrash();
    expect(provider.trashedEntries, isEmpty);
    expect(deletedFiles, contains('/tmp/c.jpg'));

    Attachments.delete = Attachments.deleteFile;
    await db.close();
  });

  test('超期 30 天的回收站条目在 load 时被物理清除（REQ-02.4）', () async {
    final db = AppDatabase.inMemory();

    final now = DateTime.now();
    final old = entry('old')..deletedAt = now.subtract(const Duration(days: 45));
    final fresh = entry('fresh')..deletedAt = now.subtract(const Duration(days: 5));
    await db.insertEntry(old);
    await db.insertEntry(fresh);

    final provider = JournalProvider(database: db);
    await provider.load();
    // old 超过 30 天在 load 时被自动清除，fresh 保留。
    expect(provider.trashedEntries.map((e) => e.id), ['fresh']);

    final rows = await db.getTrashedEntries();
    expect(rows.map((e) => e.id), ['fresh']);

    await db.close();
  });

  test('回收站条目不计入统计与那年今天', () async {
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    final old = entry('old', date: '2025-08-16')
      ..deletedAt = DateTime(2026, 8, 1);
    await db.insertEntry(old);
    await provider.load();

    expect(provider.totalCount, 0);
    expect(provider.onThisDay(DateTime(2026, 8, 16)), isEmpty);

    await db.close();
  });
}
