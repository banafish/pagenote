import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';

/// 月报页（REQ-10.2）：查看指定月份的写作报告，可切换历史月份。
class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key, this.initialYear, this.initialMonth});

  final int? initialYear;
  final int? initialMonth;

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.initialYear ?? now.year;
    _month = widget.initialMonth ?? now.month;
  }

  void _shift(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      if (m < 1) {
        m = 12;
        y--;
      } else if (m > 12) {
        m = 1;
        y++;
      }
      _month = m;
      _year = y;
    });
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final report = journal.monthlyReport(_year, _month);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('$_year 年 $_month 月报')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一月',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                DateUtils2.monthTitle(DateTime(_year, _month)),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: '下一月',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!report.hasData)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 42),
              alignment: Alignment.center,
              child: Text(
                '这个月还没有手账记录',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ReportStat(
                  icon: Icons.menu_book_rounded,
                  label: '篇数',
                  value: '${report.count}',
                  unit: '篇',
                  color: scheme.primary,
                ),
                _ReportStat(
                  icon: Icons.font_download_rounded,
                  label: '总字数',
                  value: '${report.words}',
                  unit: '字',
                  color: const Color(0xFF3E8468),
                ),
                _ReportStat(
                  icon: Icons.emoji_emotions_rounded,
                  label: '心情均值',
                  value: report.avgMood == null
                      ? '—'
                      : report.avgMood!.toStringAsFixed(1),
                  unit: '/10',
                  color: const Color(0xFFE8734A),
                ),
                _ReportStat(
                  icon: Icons.compare_arrows_rounded,
                  label: '对比上月',
                  value: report.delta > 0
                      ? '+${report.delta}'
                      : '${report.delta}',
                  unit: '篇',
                  color: report.delta >= 0
                      ? const Color(0xFF3E8468)
                      : const Color(0xFFE57373),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ReportCard(
              icon: Icons.sell_rounded,
              title: '高频标签 TOP5',
              child: report.topTags.isEmpty
                  ? const Text('本月未使用标签')
                  : Column(
                      children: [
                        for (var i = 0; i < report.topTags.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: i < 3
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '#${report.topTags[i].key}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${report.topTags[i].value} 次',
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
            ),
            const SizedBox(height: 12),
            _ReportCard(
              icon: Icons.calendar_view_week_rounded,
              title: '最常记录的星期',
              child: Text(
                report.busiestWeekday == null
                    ? '本月暂无记录'
                    : '周${_weekdayCN(report.busiestWeekday!)}',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _weekdayCN(int weekday) {
    const names = ['', '一', '二', '三', '四', '五', '六', '日'];
    return names[weekday];
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
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
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
