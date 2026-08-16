import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/providers/journal_provider.dart';

JournalEntry _e(String id, String date) {
  final now = DateTime(2026, 8, 16);
  return JournalEntry(
    id: id,
    date: date,
    title: '标题$id',
    content: '内容',
    createdAt: now,
    updatedAt: now,
  );
}

class ProviderForTest extends JournalProvider {
  ProviderForTest(this.seed);
  final List<JournalEntry> seed;

  @override
  List<JournalEntry> get entries => seed;
}

void main() {
  final now = DateTime(2026, 8, 16);

  test('那年今天：去年及以前同月同日，按年份分组（REQ-01.1/2）', () {
    final provider = ProviderForTest([
      _e('a', '2025-08-16'), // 去年今天 ✓
      _e('b', '2024-08-16'), // 前年今天 ✓
      _e('c', '2023-08-16'), // 大前年今天 ✓
      _e('d', '2025-08-15'), // 去年但非今日 ✗
      _e('e', '2026-08-16'), // 今年今天 ✗（补写不算历史）
      _e('f', '2026-08-15'), // ✗
    ]);
    final result = provider.onThisDay(now);
    expect(result.keys.toList(), [2025, 2024, 2023]);
    expect(result[2025]!.map((e) => e.id), ['a']);
    expect(result[2024]!.map((e) => e.id), ['b']);
  });

  test('无历史记录时不返回内容（REQ-01.1：不显示不占位）', () {
    final provider = ProviderForTest([
      _e('a', '2026-08-16'),
      _e('b', '2026-08-01'),
    ]);
    expect(provider.onThisDay(now), isEmpty);
  });

  test('当天补写的新条目不影响历史展示（REQ-01.4）', () {
    final seed = [_e('old', '2025-08-16'), _e('new', '2026-08-16')];
    final provider = ProviderForTest(seed);
    var result = provider.onThisDay(now);
    expect(result.length, 1);
    expect(result[2025]!.single.id, 'old');

    seed.add(_e('new2', '2026-08-16'));
    result = provider.onThisDay(now);
    expect(result[2025]!.length, 1);
    expect(result.containsKey(2026), isFalse);
  });

  test('月报：篇数/字数/均值/标签TOP5/星期/环比（REQ-10.1）', () {
    final ts = DateTime(2026, 8, 16);
    JournalEntry entry(
      String id,
      String date,
      List<String> tags, {
      int words = 10,
      Mood? mood,
    }) {
      return JournalEntry(
        id: id,
        date: date,
        title: '',
        content: '字' * words,
        mood: mood,
        tags: tags,
        createdAt: ts,
        updatedAt: ts,
      );
    }

    final provider = ProviderForTest([
      entry('1', '2026-08-03', ['工作', '日常'], words: 20, mood: Mood.happy),
      entry('2', '2026-08-04', ['工作'], words: 10, mood: Mood.angry),
      entry('3', '2026-08-11', ['工作', '阅读'], words: 30, mood: Mood.neutral),
      entry('4', '2026-09-01', ['下月'], words: 100),
      entry('5', '2026-07-30', ['上月'], words: 50),
    ]);
    final report = provider.monthlyReport(2026, 8);

    expect(report.count, 3, reason: '只统计 8 月（不含 9 月与 7 月）');
    expect(report.words, 60);
    // (9 + 1 + 5) / 3 = 5
    expect(report.avgMood, closeTo(5.0, 0.001));
    expect(report.topTags.length, 3);
    expect(report.topTags.first.key, '工作');
    expect(report.topTags.first.value, 3);
    expect(report.prevCount, 1, reason: '上月（7 月）1 篇');
    expect(report.delta, 2);
    // 8/3 周一、8/4 周二、8/11 周二 → 最常记录的星期为周二。
    expect(report.busiestWeekday, 2);
    expect(report.hasData, isTrue);
  });

  test('活动统计：频率排行与心情交叉（REQ-12.3）', () {
    final ts = DateTime(2026, 8, 16);
    JournalEntry entry(String id, List<String> activities, Mood? mood) {
      return JournalEntry(
        id: id,
        date: '2026-08-16',
        title: '',
        content: '内容',
        mood: mood,
        activities: activities,
        createdAt: ts,
        updatedAt: ts,
      );
    }

    final provider = ProviderForTest([
      entry('1', ['运动', '阅读'], Mood.excited), // 运动 10
      entry('2', ['运动'], Mood.happy), // 运动 (10+9)/2 = 9.5
      entry('3', ['阅读'], Mood.sad), // 阅读 (10+2)/2 = 6
      entry('4', [], Mood.angry), // 无活动不计
    ]);

    final counts = provider.activityCounts;
    expect(counts['运动'], 2);
    expect(counts['阅读'], 2);

    final scores = provider.activityMoodScores();
    expect(scores['运动'], closeTo(9.5, 0.001));
    expect(scores['阅读'], closeTo(6.0, 0.001));
    // 心情最好的活动排序：运动 > 阅读。
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    expect(ranked.first.key, '运动');
  });
}
