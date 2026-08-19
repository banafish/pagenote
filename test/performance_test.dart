import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/utils/search_filter.dart';

/// NFR-02：条目 ≥2000 条时，全量内存加载方案下的核心计算保持流畅。
void main() {
  test('2000 条条目下统计 / 搜索 / 月报计算正常完成', () {
    final entries = List.generate(2000, (i) {
      final day = DateTime(2022, 1, 1).add(Duration(days: i ~/ 3));
      return JournalEntry(
        id: 'e$i',
        date:
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        title: '标题$i',
        content: '这是第 $i 篇手账的内容，记录一些日常 🌿',
        mood: Mood.values[i % Mood.values.length],
        tags: ['标签${i % 40}'],
        activities: [if (i % 2 == 0) '运动', if (i % 3 == 0) '阅读'],
        createdAt: day,
        updatedAt: day,
      );
    });
    expect(entries.length, 2000);

    final provider = _ProviderOf(entries);
    final sw = Stopwatch()..start();

    // 覆盖首页、统计页、月报的全部派生计算。
    expect(provider.totalCount, 2000);
    expect(provider.allTags.length, 40);
    provider.streakDays();
    provider.monthCount;
    provider.moodCounts;
    provider.lastWeekCounts;
    provider.totalWords;
    provider.dominantMood;
    provider.onThisDay();
    provider.moodAverages(90);
    provider.activityCounts;
    provider.activityMoodScores();
    provider.monthlyReport(2024, 6);

    // 关键词 + 筛选组合搜索。
    final results = filterEntries(
      entries,
      '手账',
      SearchFilters()..favoritesOnly = false,
    );
    expect(results.length, 2000);

    sw.stop();
    // 内存计算应在数百毫秒内完成（宽松上限，防止劣化）。
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: '2000 条全量派生计算耗时 ${sw.elapsed}',
    );
  });
}

class _ProviderOf extends JournalProvider {
  _ProviderOf(this.seed);
  final List<JournalEntry> seed;

  @override
  List<JournalEntry> get entries => seed;
}
