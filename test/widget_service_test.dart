import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/data/prompts.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/services/widget_service.dart';
import 'package:pagenote/utils/date_utils.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('小组件内容：连续天数、今日是否已写与今日一问（REQ-14）', () async {
    final db = AppDatabase.inMemory();
    final sqlite = await db.database;
    await sqlite.delete('entries');
    await sqlite.delete('templates');

    final journal = JournalProvider(database: db);
    final now = DateTime(2026, 8, 16, 20);
    String key(DateTime d) => DateUtils2.dateKey(d);

    // 空数据。
    var content = WidgetContent.from(journal, now);
    expect(content.streakDays, 0);
    expect(content.writtenToday, false);
    expect(content.prompt, promptForDate(key(now)));

    // 今天 + 昨天各一条 → 连续 2 天,今日已写。
    await journal.saveEntry(_e('t', key(now)));
    await journal.saveEntry(
      _e('y', key(now.subtract(const Duration(days: 1)))),
    );
    await journal.load();

    content = WidgetContent.from(journal, now);
    expect(content.streakDays, 2);
    expect(content.writtenToday, true);

    // 通道数据结构。
    expect(content.toChannelMap(), {
      'streak': 2,
      'writtenToday': true,
      'prompt': promptForDate(key(now)),
    });

    await db.close();
  });

  test('不同日期驱动今日一问内容', () {
    final content = WidgetContent.from(_emptyJournal(), DateTime(2026, 8, 15));
    expect(content.prompt, promptForDate('2026-08-15'));
  });
}

JournalEntry _e(String id, String date) {
  final now = DateTime.now();
  return JournalEntry(
    id: id,
    date: date,
    title: '',
    content: '内容$id',
    createdAt: now,
    updatedAt: now,
  );
}

JournalProvider _emptyJournal() {
  final db = AppDatabase.inMemory();
  return JournalProvider(database: db);
}
