import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/prompts.dart';
import '../models/journal_entry.dart';
import '../pages/editor_page.dart';
import '../pages/monthly_report_page.dart';
import '../pages/quick_note_page.dart';
import '../pages/share_card_page.dart';
import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/date_utils.dart';
import '../utils/delete_flow.dart';
import '../widgets/daily_prompt_card.dart';
import '../widgets/entry_card.dart';
import '../widgets/on_this_day_card.dart';
import 'search_page.dart';

/// 首页：手账时间轴。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenEditor});

  final void Function(BuildContext context, JournalEntry? entry) onOpenEditor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final entries = _favoritesOnly
        ? _favoriteEntries(journal)
        : journal.entries;
    final grouped = _groupByDate(entries);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('拾页', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 1),
              Text(
                _greeting(now),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            // 快速速记入口（REQ-16）。
            IconButton(
              tooltip: '速记',
              icon: const Icon(Icons.bolt_rounded),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const QuickNotePage())),
            ),
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
            IconButton(
              tooltip: _favoritesOnly ? '显示全部' : '只看收藏',
              isSelected: _favoritesOnly,
              selectedIcon: const Icon(
                Icons.favorite,
                color: Color(0xFFE57373),
              ),
              icon: const Icon(Icons.favorite_border),
              onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
            ),
            const SizedBox(width: 4),
          ],
        ),
        if (journal.loaded && entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              favoritesOnly: _favoritesOnly,
              onStartWithPrompt: _startWithPrompt,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.builder(
              itemCount: grouped.length + 1,
              itemBuilder: (context, i) {
                final isPhone = MediaQuery.sizeOf(context).width < 700;

                // 顶部：那年今天 + 月报引导。
                if (i == 0) {
                  final child = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OnThisDayCard(
                        byYear: journal.onThisDay(),
                        onOpen: (entry) => widget.onOpenEditor(context, entry),
                      ),
                      _MonthlyReportCard(onOpen: _openLastMonthReport),
                    ],
                  );
                  return isPhone
                      ? child
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: child,
                        );
                }

                final group = grouped[i - 1];
                final child = _DateGroupView(
                  dateKey: group.date,
                  entries: group.entries,
                  onOpen: (entry) => widget.onOpenEditor(context, entry),
                );
                if (!isPhone) {
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: child,
                  );
                }
                return child;
              },
            ),
          ),
      ],
    );
  }

  void _startWithPrompt() {
    final now = DateTime.now();
    final prompt = promptForDate(DateUtils2.dateKey(now));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          entry: JournalEntry(
            id: JournalProvider.newId(),
            date: DateUtils2.dateKey(now),
            title: '',
            content: '$prompt\n',
            createdAt: now,
            updatedAt: now,
          ),
          isNew: true,
        ),
      ),
    );
  }

  void _openLastMonthReport(int year, int month) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MonthlyReportPage(initialYear: year, initialMonth: month),
      ),
    );
  }

  List<JournalEntry> _favoriteEntries(JournalProvider journal) =>
      journal.entries.where((e) => e.isFavorite).toList();

  String _greeting(DateTime now) {
    final streak = context.watch<JournalProvider>().streakDays();
    final base = switch (now.hour) {
      < 5 => '夜深了',
      < 11 => '早上好',
      < 14 => '中午好',
      < 18 => '下午好',
      _ => '晚上好',
    };
    if (streak >= 2) return '$base，已连续记录 $streak 天 ✍️';
    if (streak == 1) return '$base，今天也记得写手账哦 ✍️';
    return base;
  }
}

class _EntryGroup {
  _EntryGroup(this.date, this.entries);
  final String date;
  final List<JournalEntry> entries;
}

List<_EntryGroup> _groupByDate(List<JournalEntry> entries) {
  final groups = <String, List<JournalEntry>>{};
  for (final e in entries) {
    groups.putIfAbsent(e.date, () => []).add(e);
  }
  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) _EntryGroup(k, groups[k]!)];
}

class _MonthlyReportCard extends StatelessWidget {
  const _MonthlyReportCard({required this.onOpen});

  final void Function(int year, int month) onOpen;

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final lastMonth = now.month == 1
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, now.month - 1, 1);
    final ym = DateUtils2.ym(lastMonth);
    final report = journal.monthlyReport(lastMonth.year, lastMonth.month);

    // 每月首次打开且上月有数据时展示（REQ-10.3）。
    if (report.count == 0 || settings.reportPromptMonth == ym) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.tertiaryContainer.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 24,
            color: scheme.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '上月月报已生成',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${lastMonth.month} 月写了 ${report.count} 篇 · 累计 ${report.words} 字',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              settings.setReportPromptMonth(ym);
              onOpen(lastMonth.year, lastMonth.month);
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }
}

class _DateGroupView extends StatelessWidget {
  const _DateGroupView({
    required this.dateKey,
    required this.entries,
    required this.onOpen,
  });

  final String dateKey;
  final List<JournalEntry> entries;
  final void Function(JournalEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 10, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                DateUtils2.friendlyDate(dateKey),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entries.length} 篇',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EntryCard(
              entry: entry,
              onTap: () => onOpen(entry),
              onToggleFavorite: (id) =>
                  context.read<JournalProvider>().toggleFavorite(id),
              onDelete: (id) => deleteWithUndo(context, id),
              onShare: (id) => _openShare(context, entry),
            ),
          ),
      ],
    );
  }

  void _openShare(BuildContext context, JournalEntry entry) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ShareCardPage(entry: entry)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.favoritesOnly,
    required this.onStartWithPrompt,
  });

  final bool favoritesOnly;
  final VoidCallback onStartWithPrompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final todayKey = DateUtils2.dateKey(DateTime.now());
    final prompt = promptForDate(todayKey);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                favoritesOnly ? Icons.favorite_outline : Icons.auto_stories,
                size: 52,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              favoritesOnly ? '还没有收藏的手账' : '写下你的第一页',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              favoritesOnly ? '点击卡片右上角菜单即可收藏' : '记录今天的心情、天气和小小的日常',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            // 空状态展示今日一问，引导开始写作（REQ-04.4）。
            if (!favoritesOnly) ...[
              const SizedBox(height: 26),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DailyPromptCard(prompt: prompt, compact: true),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onStartWithPrompt,
                icon: const Icon(Icons.edit_rounded, size: 19),
                label: const Text('以此开始写作'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
