import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import '../utils/date_utils.dart';

/// 那年今天卡片（REQ-01）：展示历史上同月同日写过的手账。
/// 无历史记录时不渲染（不占位）。
class OnThisDayCard extends StatelessWidget {
  const OnThisDayCard({
    super.key,
    required this.byYear,
    required this.onOpen,
  });

  /// 年份（新→旧）→ 该年今天的条目。
  final Map<int, List<JournalEntry>> byYear;
  final void Function(JournalEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (byYear.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.65),
            scheme.secondaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '那年今天',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final year in byYear.keys)
            for (final entry in byYear[year]!)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(entry),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            entry.mood?.emoji ?? '📔',
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$year 年的今天',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  entry.title.trim().isNotEmpty
                                      ? entry.title.trim()
                                      : entry.plainContent,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateUtils2.monthDay(entry.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
