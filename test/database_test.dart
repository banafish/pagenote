import 'package:flutter_test/flutter_test.dart';
import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('建表与条目 CRUD 往返', () async {
    
    final appDb = AppDatabase.inMemory();

    final now = DateTime(2026, 8, 16, 10, 30);
    final entry = JournalEntry(
      id: 'e1',
      date: '2026-08-16',
      title: '海边散步',
      content: '傍晚的海风很舒服',
      mood: Mood.happy,
      weather: Weather.sunny,
      tags: ['旅行', '夏日'],
      images: ['/tmp/a.jpg'],
      isFavorite: true,
      createdAt: now,
      updatedAt: now,
    );

    await appDb.insertEntry(entry);
    final all = await appDb.getAllEntries();
    expect(all.length, 1);
    expect(all.first.title, '海边散步');
    expect(all.first.mood, Mood.happy);
    expect(all.first.weather, Weather.sunny);
    expect(all.first.tags, ['旅行', '夏日']);
    expect(all.first.images, ['/tmp/a.jpg']);
    expect(all.first.isFavorite, true);

    final byDate = await appDb.getEntriesByDate('2026-08-16');
    expect(byDate.length, 1);

    entry
      ..title = '海边散步（改）'
      ..content = '涨潮了'
      ..isFavorite = false;
    await appDb.updateEntry(entry);
    final updated = await appDb.getAllEntries();
    expect(updated.first.title, '海边散步（改）');
    expect(updated.first.isFavorite, false);
    expect((await appDb.getFavorites()), isEmpty);

    await appDb.deleteEntry('e1');
    expect((await appDb.getAllEntries()), isEmpty);

    await appDb.close();
  });

  test('搜索覆盖标题、正文与标签', () async {
    
    final appDb = AppDatabase.inMemory();
    final now = DateTime(2026, 8, 15);

    Future<void> add(String id, String title, String content, String tags) async {
      await appDb.insertEntry(JournalEntry(
        id: id,
        date: '2026-08-15',
        title: title,
        content: content,
        tags: tags.split(',').where((t) => t.isNotEmpty).toList(),
        createdAt: now,
        updatedAt: now,
      ));
    }

    await add('1', '晨跑', '今天跑了五公里', '运动');
    await add('2', '读书笔记', '读完了第一章', '阅读,日常');
    await add('3', '无关', '完全无关的内容', '');

    expect((await appDb.search('晨跑')).map((e) => e.id), ['1']);
    expect((await appDb.search('第一章')).map((e) => e.id), ['2']);
    expect((await appDb.search('阅读')).map((e) => e.id), ['2']);
    expect((await appDb.search('不存在')), isEmpty);

    await appDb.close();
  });

  test('多条目按日期倒序排列', () async {
    
    final appDb = AppDatabase.inMemory();
    final now = DateTime(2026, 8, 14);

    for (final d in ['2026-08-10', '2026-08-14', '2026-08-12']) {
      await appDb.insertEntry(JournalEntry(
        id: d,
        date: d,
        title: '',
        content: d,
        createdAt: now,
        updatedAt: now,
      ));
    }

    final order = (await appDb.getAllEntries()).map((e) => e.date).toList();
    expect(order, ['2026-08-14', '2026-08-12', '2026-08-10']);

    await appDb.close();
  });
}
