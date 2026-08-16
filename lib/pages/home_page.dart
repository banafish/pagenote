import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';
import '../widgets/entry_card.dart';
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

    final entries =
        _favoritesOnly ? _favoriteEntries(journal) : journal.entries;
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
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
            ),
            IconButton(
              tooltip: _favoritesOnly ? '显示全部' : '只看收藏',
              isSelected: _favoritesOnly,
              selectedIcon: const Icon(Icons.favorite,
                  color: Color(0xFFE57373)),
              icon: const Icon(Icons.favorite_border),
              onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
            ),
            const SizedBox(width: 4),
          ],
        ),
        if (journal.loaded && entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(favoritesOnly: _favoritesOnly),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.builder(
              itemCount: grouped.length,
              itemBuilder: (context, i) {
                final group = grouped[i];
                final isPhone = MediaQuery.sizeOf(context).width < 700;
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

  List<JournalEntry> _favoriteEntries(JournalProvider journal) =>
      journal.entries.where((e) => e.isFavorite).toList();

  String _greeting(DateTime now) {
    final streak = context.watch<JournalProvider>().streakDays;
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
              onDelete: (id) => _confirmDelete(context, id),
            ),
          ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这篇手账？'),
        content: const Text('删除后无法恢复，确定要删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<JournalProvider>().deleteEntry(id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.favoritesOnly});

  final bool favoritesOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              favoritesOnly ? '点击卡片右上角菜单即可收藏' : '记录今天的心情、天气和小小的日常',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
