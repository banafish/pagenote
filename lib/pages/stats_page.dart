import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../models/mood.dart';
import '../providers/journal_provider.dart';
import '../widgets/mood_trend_chart.dart';
import 'monthly_report_page.dart';

/// 统计页：记录数据总览。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _trendDays = 7;

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final now = DateTime.now();

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _pageTitle(context, '统计'),
        const SizedBox(height: 14),
        _sectionTitle(context, '记录足迹'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              icon: Icons.menu_book_rounded,
              label: '总篇数',
              value: '${journal.totalCount}',
              unit: '篇',
              color: scheme.primary,
            ),
            _StatCard(
              icon: Icons.local_fire_department_rounded,
              label: '连续记录',
              value: '${journal.streakDays}',
              unit: '天',
              color: const Color(0xFFE8734A),
            ),
            _StatCard(
              icon: Icons.calendar_month_rounded,
              label: '本月',
              value: '${journal.monthCount}',
              unit: '篇',
              color: const Color(0xFF3F6C9C),
            ),
            _StatCard(
              icon: Icons.font_download_rounded,
              label: '累计字数',
              value: '${journal.totalWords}',
              unit: '字',
              color: const Color(0xFF3E8468),
            ),
          ],
        ),
        const SizedBox(height: 26),

        // 月报入口（REQ-10.2）。
        _MonthlyReportEntry(
          report: journal.monthlyReport(now.year, now.month),
        ),
        const SizedBox(height: 26),

        _sectionTitle(context, '心情趋势'),
        const SizedBox(height: 10),
        _TrendCard(
          days: _trendDays,
          onChanged: (days) => setState(() => _trendDays = days),
          points: [
            for (final p in journal.moodAverages(_trendDays))
              (p.date, p.score),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '最近 7 天'),
        const SizedBox(height: 10),
        _WeekBarChart(counts: journal.lastWeekCounts),
        const SizedBox(height: 26),
        if (journal.moodCounts.isNotEmpty) ...[
          _sectionTitle(context, '心情分布'),
          const SizedBox(height: 10),
          _MoodBars(counts: journal.moodCounts, total: journal.totalCount),
          const SizedBox(height: 26),
        ],
        if (journal.activityCounts.isNotEmpty) ...[
          _sectionTitle(context, '活动打卡'),
          const SizedBox(height: 10),
          _ActivityStats(journal: journal),
          const SizedBox(height: 26),
        ],
        if (journal.allTags.isNotEmpty) ...[
          _sectionTitle(context, '常用标签'),
          const SizedBox(height: 10),
          _TagRanking(tags: journal.allTags, entries: journal.entries),
        ],
      ],
    );

    return width < 900
        ? content
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: content,
            ),
          );
  }

  Widget _pageTitle(BuildContext context, String text) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, left: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// 月报入口卡片（REQ-10.2）：点击进入当月报告，可切换历史月份。
class _MonthlyReportEntry extends StatelessWidget {
  const _MonthlyReportEntry({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MonthlyReportPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.tertiaryContainer.withValues(alpha: 0.5),
              scheme.secondaryContainer.withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.tertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.workspace_premium_outlined,
                  size: 22, color: scheme.tertiary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.month} 月月报',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    report.hasData
                        ? '${report.count} 篇 · ${report.words} 字 · 心情 ${report.avgMood == null ? '—' : report.avgMood!.toStringAsFixed(1)}'
                        : '本月还没有记录，先去写一篇吧',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 心情趋势卡片（REQ-05.2）：7 / 30 / 90 天切换。
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.days,
    required this.onChanged,
    required this.points,
  });

  final int days;
  final ValueChanged<int> onChanged;
  final List<(String, double)> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '情绪随时间的变化',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 天')),
                  ButtonSegment(value: 30, label: Text('30 天')),
                  ButtonSegment(value: 90, label: Text('90 天')),
                ],
                selected: {days},
                onSelectionChanged: (set) => onChanged(set.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MoodTrendChart(points: points),
        ],
      ),
    );
  }
}

/// 活动统计（REQ-12.3）：频率排行 + 心情交叉。
class _ActivityStats extends StatelessWidget {
  const _ActivityStats({required this.journal});

  final JournalProvider journal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = journal.activityCounts;
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    final moodScores = journal.activityMoodScores();
    final bestMood = moodScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '活动频率排行',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < ranked.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i < 3 ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(emojiOfActivity(ranked[i].key),
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ranked[i].key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${ranked[i].value} 次',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (bestMood.isNotEmpty) ...[
            const Divider(height: 26),
            Text(
              '做什么的时候心情最好',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            for (final e in bestMood.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(emojiOfActivity(e.key),
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: (e.value - 1) / 9,
                          minHeight: 8,
                          backgroundColor: scheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          valueColor: AlwaysStoppedAnimation(
                              scheme.primary.withValues(alpha: 0.8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 30,
                      child: Text(
                        e.value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBarChart extends StatelessWidget {
  const _WeekBarChart({required this.counts});

  final List<int> counts;

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    final today = DateTime.now().weekday - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (counts[i] > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${counts[i]}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: counts[i] == 0
                                ? 6
                                : 14.0 + (counts[i] / (maxCount == 0 ? 1 : maxCount)) * 76,
                            decoration: BoxDecoration(
                              color: counts[i] == 0
                                  ? scheme.surfaceContainerHighest
                                  : (6 - i) == today
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: (6 - i) == today
                          ? BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        _labels[DateTime.now()
                                .subtract(Duration(days: 6 - i))
                                .weekday -
                            1],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (6 - i) == today
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodBars extends StatelessWidget {
  const _MoodBars({required this.counts, required this.total});

  final Map<Mood, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.first.value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (final e in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Text(e.key.emoji, style: const TextStyle(fontSize: 21)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 42,
                    child: Text(
                      e.key.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 10,
                        backgroundColor:
                            scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        valueColor:
                            AlwaysStoppedAnimation(e.key.color.withValues(alpha: 0.85)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 62,
                    child: Text(
                      '${e.value} 篇 · ${(e.value * 100 / total).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TagRanking extends StatelessWidget {
  const _TagRanking({required this.tags, required this.entries});

  final List<String> tags;
  final List entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final e in entries) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final top = tags.take(10).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i < 3
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '#${top[i]}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${counts[top[i]]} 篇',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
