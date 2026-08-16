import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/journal_entry.dart';

/// 手账数据库：负责建表与条目的增删改查。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// 测试用：使用内存 SQLite，自动建表。
  factory AppDatabase.inMemory() {
    final db = AppDatabase._();
    db._inMemory = true;
    return db;
  }

  static const _dbName = 'pagenote.db';
  static const _dbVersion = 1;

  Database? _db;
  bool _inMemory = false;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _inMemory
        ? inMemoryDatabasePath
        : p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
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
        await db.execute('CREATE INDEX idx_entries_date ON entries(date)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<JournalEntry>> getAllEntries() async {
    final db = await database;
    final rows = await db.query('entries', orderBy: 'date DESC, updatedAt DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getEntriesByDate(String date) async {
    final db = await database;
    final rows = await db.query('entries',
        where: 'date = ?', whereArgs: [date], orderBy: 'updatedAt DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getFavorites() async {
    final db = await database;
    final rows = await db.query('entries',
        where: 'isFavorite = 1', orderBy: 'date DESC, updatedAt DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> search(String query) async {
    final q = '%$query%';
    final db = await database;
    final rows = await db.query(
      'entries',
      where: 'title LIKE ? OR content LIKE ? OR tags LIKE ?',
      whereArgs: [q, q, q],
      orderBy: 'date DESC, updatedAt DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<void> insertEntry(JournalEntry entry) async {
    final db = await database;
    await db.insert('entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateEntry(JournalEntry entry) async {
    final db = await database;
    await db
        .update('entries', entry.toMap(), where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }
}
