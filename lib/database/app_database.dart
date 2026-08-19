import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/journal_entry.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart';

/// 手账数据库：负责建表、版本迁移与条目的增删改查。
///
/// 版本历史：
/// - v1：entries 基础表。
/// - v2：entries 新增 deletedAt（回收站软删除，REQ-02）。
/// - v3：entries 新增 activities（活动打卡，REQ-12）；新建 templates 表（REQ-09）。
/// - v4：entries 新增 paper/stickers（装饰排版，REQ-13）与 isQuickNote（快速速记，REQ-16）。
/// - v5：entries 新增 canvas（画布元素树）；templates 新增 canvas（整页版式模板）。
/// - v6：templates 新增 originId / lastUsedAt / sortIndex（分享包安装与排序，
///   FIX-02 + REQ-18）；新建 custom_stickers 表（自定义图片贴纸，REQ-20）。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// 测试用：内存 SQLite，自动建表。
  /// 注意：同一进程内多个实例共享同一条 :memory: 连接，
  /// 需要隔离时请自行清表。
  factory AppDatabase.inMemory() {
    final db = AppDatabase._();
    db._inMemory = true;
    return db;
  }

  /// 测试用：打开指定路径的数据库文件（用于验证旧版本迁移）。
  @visibleForTesting
  factory AppDatabase.atPath(String path) {
    final db = AppDatabase._();
    db._overridePath = path;
    return db;
  }

  static const _dbName = 'pagenote.db';
  static const dbVersion = 6;

  Database? _db;
  bool _inMemory = false;
  String? _overridePath;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path =
        _overridePath ??
        (_inMemory
            ? inMemoryDatabasePath
            : p.join(await getDatabasesPath(), _dbName));
    return openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) => _createAll(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        // 逐级迁移：保证任意旧版本都能沿正式路径升级到最新。
        for (var v = oldVersion + 1; v <= newVersion; v++) {
          final migrate = _migrations[v];
          if (migrate != null) await migrate(db);
        }
      },
    );
  }

  /// 各版本的增量迁移脚本（key 为目标版本号）。
  static final Map<int, Future<void> Function(Database)> _migrations = {
    2: (db) async {
      await db.execute('ALTER TABLE entries ADD COLUMN deletedAt INTEGER');
    },
    3: (db) async {
      await db.execute(
        "ALTER TABLE entries ADD COLUMN activities TEXT NOT NULL DEFAULT ''",
      );
      await _createTemplatesTable(db, withCanvas: false, withSharing: false);
    },
    4: (db) async {
      await db.execute(
        "ALTER TABLE entries ADD COLUMN paper TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE entries ADD COLUMN stickers TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE entries ADD COLUMN isQuickNote INTEGER NOT NULL DEFAULT 0',
      );
    },
    5: (db) async {
      await db.execute(
        "ALTER TABLE entries ADD COLUMN canvas TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE templates ADD COLUMN canvas TEXT NOT NULL DEFAULT ''",
      );
    },
    6: (db) async {
      await db.execute('ALTER TABLE templates ADD COLUMN originId TEXT');
      await db.execute('ALTER TABLE templates ADD COLUMN lastUsedAt INTEGER');
      await db.execute(
        'ALTER TABLE templates ADD COLUMN sortIndex INTEGER NOT NULL DEFAULT 0',
      );
      await _createCustomStickersTable(db);
    },
  };

  static Future<void> _createAll(Database db) async {
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
        canvas TEXT NOT NULL DEFAULT '',
        isQuickNote INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        deletedAt INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_entries_date ON entries(date)');
    await _createTemplatesTable(db);
    await _createCustomStickersTable(db);
  }

  /// [withCanvas] 为 false 时建 v3 时期的老结构（迁移链上 canvas 由 v5 补加）；
  /// [withSharing] 为 false 时不含 v6 的 originId / lastUsedAt / sortIndex。
  static Future<void> _createTemplatesTable(
    Database db, {
    bool withCanvas = true,
    bool withSharing = true,
  }) async {
    await db.execute('''
      CREATE TABLE templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        builtin INTEGER NOT NULL DEFAULT 0,
        ${withCanvas ? "canvas TEXT NOT NULL DEFAULT ''," : ''}
        ${withSharing ? 'originId TEXT, lastUsedAt INTEGER, sortIndex INTEGER NOT NULL DEFAULT 0,' : ''}
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }

  /// 自定义图片贴纸（REQ-20）：id 为文件内容 sha1，天然跨设备稳定。
  static Future<void> _createCustomStickersTable(Database db) async {
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
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<JournalEntry>> getAllEntries() async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'deletedAt IS NULL',
      orderBy: 'date DESC, updatedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getTrashedEntries() async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'deletedAt IS NOT NULL',
      orderBy: 'deletedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getEntriesByDate(String date) async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'date = ? AND deletedAt IS NULL',
      whereArgs: [date],
      orderBy: 'updatedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getFavorites() async {
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'isFavorite = 1 AND deletedAt IS NULL',
      orderBy: 'date DESC, updatedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> search(String query) async {
    final q = '%$query%';
    final db = await database;
    final rows = await db.query(
      'entries',
      where:
          'deletedAt IS NULL AND (title LIKE ? OR content LIKE ? OR tags LIKE ?)',
      whereArgs: [q, q, q],
      orderBy: 'date DESC, updatedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<void> insertEntry(JournalEntry entry) async {
    final db = await database;
    await db.insert(
      'entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateEntry(JournalEntry entry) async {
    final db = await database;
    await db.update(
      'entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllTrashed() async {
    final db = await database;
    await db.delete('entries', where: 'deletedAt IS NOT NULL');
  }

  Future<void> deleteAllEntries() async {
    final db = await database;
    await db.delete('entries');
  }

  Future<void> insertTemplate(JournalTemplate template) async {
    final db = await database;
    await db.insert(
      'templates',
      template.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTemplate(String id) async {
    final db = await database;
    await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllTemplates() async {
    final db = await database;
    await db.delete('templates');
  }

  Future<List<JournalTemplate>> getAllTemplates() async {
    final db = await database;
    final rows = await db.query(
      'templates',
      orderBy: 'builtin DESC, updatedAt DESC',
    );
    return rows.map(JournalTemplate.fromMap).toList();
  }

  // ---------------- 自定义贴纸（REQ-20） ----------------

  Future<List<CustomSticker>> getAllCustomStickers() async {
    final db = await database;
    final rows = await db.query('custom_stickers', orderBy: 'createdAt DESC');
    return rows.map(CustomSticker.fromMap).toList();
  }

  Future<void> insertCustomSticker(CustomSticker sticker) async {
    final db = await database;
    await db.insert(
      'custom_stickers',
      sticker.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCustomSticker(String id) async {
    final db = await database;
    await db.delete('custom_stickers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllCustomStickers() async {
    final db = await database;
    await db.delete('custom_stickers');
  }
}
