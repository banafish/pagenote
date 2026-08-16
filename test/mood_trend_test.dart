import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/providers/journal_provider.dart';

JournalEntry _e(String id, String date, Mood? mood) {
  final now = DateTime(2026, 8, 16);
  return JournalEntry(
    id: id,
    date: date,
    title: '',
    content: '内容',
    mood: mood,
    createdAt: now,
    updatedAt: now,
  );
}

class ProviderForTest extends JournalProvider {
  ProviderForTest(this.seed) : super();

  final List<JournalEntry> seed;

  @override
  List<JournalEntry> get entries => seed;
}

void main() {
  final today = DateTime(2026, 8, 16);
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  test('心情枚举映射为 1–10 分值（REQ-05.1）', () {
    expect(Mood.values.length, 10);
    final scores = Mood.values.map((m) => m.score).toSet();
    expect(scores, {1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
    expect(Mood.excited.score, greaterThan(Mood.sad.score));
  });

  test('一天多条取当日平均，仅含有数据的日期（REQ-05.1）', () {
    final seed = [
      _e('1', key(today), Mood.happy), // 9
      _e('2', key(today), Mood.sad), // 2 → 当日平均 5.5
      _e('3', key(today.subtract(const Duration(days: 1))), Mood.excited), // 10
      // days 2 前无记录 → 不出现（断点处理）
      _e('4', key(today.subtract(const Duration(days: 3))), Mood.neutral), // 5
    ];
    final provider = ProviderForTest(seed);
    final points = provider.moodAverages(7, today);

    expect(points.length, 3);
    expect(points[0].date, key(today.subtract(const Duration(days: 3))));
    expect(points[0].score, 5.0);
    expect(points[1].date, key(today.subtract(const Duration(days: 1))));
    expect(points[1].score, 10.0);
    expect(points[2].date, key(today));
    expect(points[2].score, closeTo(5.5, 0.001));
  });

  test('区间外的日期不计入', () {
    final seed = [
      _e('1', key(today.subtract(const Duration(days: 10))), Mood.happy),
      _e('2', key(today), Mood.calm),
    ];
    final provider = ProviderForTest(seed);
    expect(provider.moodAverages(7, today).length, 1);
  });

  test('无心情记录时为空，图表显示占位提示', () {
    final provider = ProviderForTest([_e('1', key(today), null)]);
    expect(provider.moodAverages(7, today), isEmpty);
  });
}
