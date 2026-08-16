import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('全新安装直接建最新表结构（v3）', () async {
    final db = AppDatabase.inMemory();
    final sqlite = await db.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);

    final entriesColumns =
        await sqlite.rawQuery('PRAGMA table_info(entries)');
    final names = entriesColumns.map((c) => c['name']).toSet();
    expect(names, containsAll([
      'id', 'date', 'title', 'content', 'mood', 'weather', 'tags',
      'images', 'activities', 'isFavorite', 'createdAt', 'updatedAt',
      'deletedAt',
    ]));

    final templateColumns =
        await sqlite.rawQuery('PRAGMA table_info(templates)');
    expect(templateColumns.map((c) => c['name']), containsAll(
        ['id', 'name', 'title', 'content', 'tags', 'builtin']));

    await db.close();
  });

  test('v1 → v3 迁移：旧数据保留，新列可用（NFR-01）', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v1.db');
    await databaseFactory.deleteDatabase(path);

    // 手工建一个 v1 库并写入数据。
    final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE entries (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          mood TEXT,
          weather TEXT,
          tags TEXT NOT NULL DEFAULT '',
          images TEXT NOT NULL DEFAULT '',
          isFavorite INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      await db.execute(
          "INSERT INTO entries VALUES ('e1', '2025-08-16', '旧数据', 'v1 写的手账', NULL, NULL, '', '', 0, 1, 1)");
    });
    await v1.close();

    // 用正式路径打开：应自动迁移到 v3。
    final appDb = AppDatabase.atPath(path);
    final entries = await appDb.getAllEntries();
    expect(entries.length, 1);
    expect(entries.first.title, '旧数据');
    expect(entries.first.activities, isEmpty);
    expect(entries.first.deletedAt, isNull);

    // 迁移后新列可写（软删除 + 活动）。
    final entry = entries.first;
    entry
      ..activities = ['运动']
      ..deletedAt = DateTime.now();
    await appDb.updateEntry(entry);
    final trashed = await appDb.getTrashedEntries();
    expect(trashed.length, 1);
    expect(trashed.first.activities, ['运动']);
    expect((await appDb.getAllEntries()), isEmpty);

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), 3);
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v2 → v3 迁移：补 activities 列与 templates 表', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v2.db');
    await databaseFactory.deleteDatabase(path);

    final v2 = await openDatabase(path, version: 2, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE entries (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          mood TEXT,
          weather TEXT,
          tags TEXT NOT NULL DEFAULT '',
          images TEXT NOT NULL DEFAULT '',
          isFavorite INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          deletedAt INTEGER
        )
      ''');
      await db.execute(
          "INSERT INTO entries VALUES ('e2', '2025-01-01', 'v2', '已删除的', NULL, NULL, '', '', 0, 1, 2, 1700000000000)");
    });
    await v2.close();

    final appDb = AppDatabase.atPath(path);
    expect((await appDb.getTrashedEntries()).length, 1);
    expect((await appDb.getAllEntries()), isEmpty);

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), 3);
    final columns =
        (await sqlite.rawQuery('PRAGMA table_info(entries)'))
            .map((c) => c['name'])
            .toSet();
    expect(columns, contains('activities'));
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });
}
