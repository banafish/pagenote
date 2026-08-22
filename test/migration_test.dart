import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/sticker_assets.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('全新安装直接建最新表结构（v5）', () async {
    final db = AppDatabase.inMemory();
    final sqlite = await db.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);

    final entriesColumns =
        await sqlite.rawQuery('PRAGMA table_info(entries)');
    final names = entriesColumns.map((c) => c['name']).toSet();
    expect(names, containsAll([
      'id', 'date', 'title', 'content', 'mood', 'weather', 'tags',
      'images', 'activities', 'isFavorite', 'createdAt', 'updatedAt',
      'deletedAt', 'paper', 'stickers', 'canvas', 'isQuickNote',
    ]));

    final templateColumns =
        await sqlite.rawQuery('PRAGMA table_info(templates)');
    expect(templateColumns.map((c) => c['name']), containsAll(
        ['id', 'name', 'title', 'content', 'tags', 'builtin', 'canvas']));
    // v8：模板归属列。
    expect(templateColumns.map((c) => c['name']), contains('packId'));

    // v7：素材包表与贴纸归属列。
    final stickerColumns =
        await sqlite.rawQuery('PRAGMA table_info(custom_stickers)');
    expect(stickerColumns.map((c) => c['name']), contains('packId'));
    final packColumns = await sqlite.rawQuery('PRAGMA table_info(sticker_packs)');
    expect(packColumns.map((c) => c['name']), containsAll(
        ['id', 'name', 'author', 'originId', 'createdAt']));

    await db.close();
  });

  test('v1 → v4 迁移：旧数据保留，新列可用（NFR-01）', () async {
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

    // 用正式路径打开：应自动迁移到 v4。
    final appDb = AppDatabase.atPath(path);
    final entries = await appDb.getAllEntries();
    expect(entries.length, 1);
    expect(entries.first.title, '旧数据');
    expect(entries.first.activities, isEmpty);
    expect(entries.first.deletedAt, isNull);
    expect(entries.first.paper, isEmpty, reason: 'v4 前的条目无装饰');
    expect(entries.first.stickers, isEmpty);
    expect(entries.first.isQuickNote, false);

    // 迁移后新列可写（软删除 + 活动 + 装饰 + 速记）。
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
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v2 → v4 迁移：补 activities/paper/stickers/isQuickNote 列', () async {
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
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    final columns =
        (await sqlite.rawQuery('PRAGMA table_info(entries)'))
            .map((c) => c['name'])
            .toSet();
    expect(columns, containsAll(['activities', 'paper', 'stickers', 'isQuickNote']));
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v3 → v4 迁移：补装饰与速记三列,旧数据原样保留（REQ-13/16）', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v3.db');
    await databaseFactory.deleteDatabase(path);

    final v3 = await openDatabase(path, version: 3, onCreate: (db, _) async {
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
          activities TEXT NOT NULL DEFAULT '',
          isFavorite INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          deletedAt INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '',
          builtin INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      await db.execute(
          "INSERT INTO entries VALUES ('e3', '2026-01-02', 'v3条目', 'v3 内容', NULL, NULL, '旧', '', '运动', 0, 1, 2, NULL)");
    });
    await v3.close();

    final appDb = AppDatabase.atPath(path);
    final entries = await appDb.getAllEntries();
    expect(entries.length, 1);
    expect(entries.first.title, 'v3条目');
    expect(entries.first.tags, ['旧']);
    expect(entries.first.activities, ['运动']);
    expect(entries.first.paper, '');

    // v4 新列可写并读回。
    final entry = entries.first;
    entry
      ..paper = 'dots'
      ..isQuickNote = true;
    await appDb.updateEntry(entry);
    final reloaded = (await appDb.getAllEntries()).first;
    expect(reloaded.paper, 'dots');
    expect(reloaded.isQuickNote, true);

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v4 → v5 迁移：补 entries/templates 的 canvas 列,旧数据原样保留（调研三阶段）', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v4.db');
    await databaseFactory.deleteDatabase(path);

    final v4 = await openDatabase(path, version: 4, onCreate: (db, _) async {
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
          activities TEXT NOT NULL DEFAULT '',
          paper TEXT NOT NULL DEFAULT '',
          stickers TEXT NOT NULL DEFAULT '',
          isQuickNote INTEGER NOT NULL DEFAULT 0,
          isFavorite INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          deletedAt INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '',
          builtin INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      await db.execute(
          "INSERT INTO entries VALUES ('e4', '2026-05-01', 'v4条目', '带装饰的旧手账', NULL, NULL, '', '', '', 'stars', '[]', 0, 0, 1, 2, NULL)");
      await db.execute(
          "INSERT INTO templates VALUES ('t4', '旧模板', '', '内容', '', 0, 1, 2)");
    });
    await v4.close();

    final appDb = AppDatabase.atPath(path);
    final entries = await appDb.getAllEntries();
    expect(entries.length, 1);
    expect(entries.first.title, 'v4条目');
    expect(entries.first.paper, 'stars');
    expect(entries.first.canvas, isNull, reason: 'v4 条目无画布,展示时惰性合成');

    // canvas 列可写可读。
    final entry = entries.first;
    entry.canvas = synthesizeCanvas(entry);
    await appDb.updateEntry(entry);
    final reloaded = (await appDb.getAllEntries()).first;
    expect(reloaded.canvas, isNotNull);
    expect(reloaded.canvas!.firstOfRole('title')!.text, 'v4条目');

    // 模板 canvas 列同样可用。
    final templates = await appDb.getAllTemplates();
    expect(templates.single.canvas, isNull);
    templates.single.canvas = JournalCanvas(paperId: 'sakura');
    await appDb.insertTemplate(templates.single);
    expect(
      (await appDb.getAllTemplates()).single.canvas!.paperId,
      'sakura',
    );

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    final entryColumns =
        (await sqlite.rawQuery('PRAGMA table_info(entries)'))
            .map((c) => c['name'])
            .toSet();
    expect(entryColumns, contains('canvas'));
    final templateColumns =
        (await sqlite.rawQuery('PRAGMA table_info(templates)'))
            .map((c) => c['name'])
            .toSet();
    expect(templateColumns, contains('canvas'));
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v6 → v7 迁移：建 sticker_packs 表，custom_stickers 补 packId,旧数据原样保留（v7）', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v6.db');
    await databaseFactory.deleteDatabase(path);

    // 手工建一个 v6 库：custom_stickers 是无 packId 的老结构，
    // templates 是 v6 结构（有 canvas 与溯源列、无 packId）。
    final v6 = await openDatabase(path, version: 6, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '',
          builtin INTEGER NOT NULL DEFAULT 0,
          canvas TEXT NOT NULL DEFAULT '',
          originId TEXT,
          lastUsedAt INTEGER,
          sortIndex INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE custom_stickers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT '',
          keywords TEXT NOT NULL DEFAULT '',
          ext TEXT NOT NULL DEFAULT '.png',
          createdAt INTEGER NOT NULL
        )
      ''');
      await db.execute(
          "INSERT INTO custom_stickers VALUES ('abc123', '旧素材', '我的', '', '.png', 1700000000000)");
    });
    await v6.close();

    final appDb = AppDatabase.atPath(path);
    final stickers = await appDb.getAllCustomStickers();
    expect(stickers.single.id, 'abc123');
    expect(stickers.single.name, '旧素材');
    expect(stickers.single.packId, isNull, reason: '存量贴纸归入未分组');

    // 新列可写可读：建包、挂贴纸、读回。
    await appDb.insertStickerPack(
      StickerPack(id: 'pack-1', name: '迁移后的包'),
    );
    await appDb.setCustomStickerPack('abc123', 'pack-1');
    expect((await appDb.getAllCustomStickers()).single.packId, 'pack-1');
    expect((await appDb.getAllStickerPacks()).single.name, '迁移后的包');

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    final stickerColumns =
        (await sqlite.rawQuery('PRAGMA table_info(custom_stickers)'))
            .map((c) => c['name'])
            .toSet();
    expect(stickerColumns, contains('packId'));
    final packColumns =
        (await sqlite.rawQuery('PRAGMA table_info(sticker_packs)'))
            .map((c) => c['name'])
            .toSet();
    expect(packColumns, containsAll(['id', 'name', 'author', 'originId', 'createdAt']));
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('v7 → v8 迁移：templates 补 packId,旧数据原样保留（v8）', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'pagenote-migration-test-v7.db');
    await databaseFactory.deleteDatabase(path);

    // 手工建一个 v7 库：templates 是无 packId 的 v7 结构。
    final v7 = await openDatabase(path, version: 7, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE sticker_packs (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '',
          originId TEXT,
          createdAt INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '',
          builtin INTEGER NOT NULL DEFAULT 0,
          canvas TEXT NOT NULL DEFAULT '',
          originId TEXT,
          lastUsedAt INTEGER,
          sortIndex INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      await db.execute(
          "INSERT INTO sticker_packs VALUES ('pack-1', '老包', '阿拾', 'pack-old', 1)");
      await db.execute(
          "INSERT INTO templates VALUES ('t7', '旧模板', '', '内容', '', 0, '', 'tpl-origin', NULL, 0, 1, 2)");
    });
    await v7.close();

    final appDb = AppDatabase.atPath(path);
    final templates = await appDb.getAllTemplates();
    expect(templates.single.name, '旧模板');
    expect(templates.single.originId, 'tpl-origin');
    expect(templates.single.packId, isNull, reason: '存量模板归入未分组');

    // 新列可写可读：挂包、读回、整包解除。
    final t = templates.single;
    t.packId = 'pack-1';
    await appDb.insertTemplate(t);
    expect((await appDb.getAllTemplates()).single.packId, 'pack-1');
    await appDb.clearTemplatePack('pack-1');
    expect((await appDb.getAllTemplates()).single.packId, isNull);
    expect((await appDb.getAllStickerPacks()).single.id, 'pack-1');

    final sqlite = await appDb.database;
    expect(await sqlite.getVersion(), AppDatabase.dbVersion);
    final columns =
        (await sqlite.rawQuery('PRAGMA table_info(templates)'))
            .map((c) => c['name'])
            .toSet();
    expect(columns, contains('packId'));
    await appDb.close();
    await databaseFactory.deleteDatabase(path);
  });
}
