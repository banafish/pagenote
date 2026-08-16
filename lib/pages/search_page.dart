import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';
import '../utils/delete_flow.dart';
import '../utils/search_filter.dart';
import '../widgets/entry_card.dart';
import 'editor_page.dart';
import 'share_card_page.dart';

/// 搜索页（REQ-06）：关键词 + 心情/天气/标签/日期区间/收藏/有图 组合筛选。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  final SearchFilters _filters = SearchFilters();
  bool _panelOpen = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final q = value.trim();
      if (!mounted) return;
      setState(() {
        _query = q;
        _searched = _searched || q.isNotEmpty;
      });
    });
  }

  bool get _filtersActive => !_filters.isEmpty;

  Future<void> _pickDateRange() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) => Localizations.override(
        context: dialogContext,
        locale: const Locale('zh'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Builder(
          builder: (innerContext) => Theme(
            data: Theme.of(innerContext),
            child: DateRangePickerDialog(
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: _dateRange(),
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _filters.startDate = DateUtils2.dateKey(picked.start);
      _filters.endDate = DateUtils2.dateKey(picked.end);
      _searched = true;
    });
  }

  DateTimeRange? _dateRange() {
    if (_filters.startDate == null || _filters.endDate == null) return null;
    return DateTimeRange(
      start: DateUtils2.parseKey(_filters.startDate!),
      end: DateUtils2.parseKey(_filters.endDate!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final recentTags = journal.allTags.take(10).toList();
    final showResults = _searched || _filtersActive;
    final results = showResults
        ? filterEntries(journal.entries, _query, _filters)
        : const <JournalEntry>[];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          decoration: InputDecoration(
            hintText: '搜索标题、内容或标签…',
            prefixIcon: const Icon(Icons.search, size: 21),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                      setState(() {});
                    },
                  ),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) {
            _onChanged(v);
            setState(() {});
          },
        ),
        actions: [
          IconButton(
            tooltip: '筛选',
            isSelected: _panelOpen || _filtersActive,
            selectedIcon: Badge(
              isLabelVisible: _filtersActive,
              child: const Icon(Icons.tune),
            ),
            icon: const Badge(
              isLabelVisible: false,
              child: Icon(Icons.tune_outlined),
            ),
            onPressed: () => setState(() => _panelOpen = !_panelOpen),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_panelOpen) _filterPanel(scheme, journal),
          if (_filtersActive) _activeChips(scheme),
          Expanded(
            child: !showResults
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (recentTags.isNotEmpty) ...[
                        Text(
                          '按标签浏览',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in recentTags)
                              ActionChip(
                                label: Text('#$tag'),
                                onPressed: () {
                                  _controller.text = tag;
                                  setState(() => _searched = true);
                                  _onChanged(tag);
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  )
                : ResultsView(
                    results: results,
                    query: _query,
                    onDeleted: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------- 筛选面板 ----------------

  Widget _filterPanel(ColorScheme scheme, JournalProvider journal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterSection('心情', [
            for (final m in Mood.values)
              _selectChip(
                '${m.emoji} ${m.label}',
                selected: _filters.moods.contains(m),
                onToggle: () => setState(() {
                  _filters.moods.contains(m)
                      ? _filters.moods.remove(m)
                      : _filters.moods.add(m);
                }),
              ),
          ]),
          _filterSection('天气', [
            for (final w in Weather.values)
              _selectChip(
                '${w.emoji} ${w.label}',
                selected: _filters.weathers.contains(w),
                onToggle: () => setState(() {
                  _filters.weathers.contains(w)
                      ? _filters.weathers.remove(w)
                      : _filters.weathers.add(w);
                }),
              ),
          ]),
          if (journal.allTags.isNotEmpty)
            _filterSection('标签', [
              for (final tag in journal.allTags.take(12))
                _selectChip(
                  '#$tag',
                  selected: _filters.tags.contains(tag),
                  onToggle: () => setState(() {
                    _filters.tags.contains(tag)
                        ? _filters.tags.remove(tag)
                        : _filters.tags.add(tag);
                  }),
                ),
            ]),
          _filterSection('日期与其他', [
            _selectChip(
              _filters.startDate == null
                  ? '日期区间'
                  : '${_filters.startDate!.substring(5)} ~ '
                        '${_filters.endDate!.substring(5)}',
              selected: _filters.startDate != null,
              onToggle: () {
                if (_filters.startDate != null) {
                  setState(() {
                    _filters.startDate = null;
                    _filters.endDate = null;
                  });
                } else {
                  _pickDateRange();
                }
              },
            ),
            _selectChip(
              '⭐ 只看收藏',
              selected: _filters.favoritesOnly,
              onToggle: () => setState(
                () => _filters.favoritesOnly = !_filters.favoritesOnly,
              ),
            ),
            _selectChip(
              '🖼️ 只看有图',
              selected: _filters.withImagesOnly,
              onToggle: () => setState(
                () => _filters.withImagesOnly = !_filters.withImagesOnly,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _filterSection(String title, List<Widget> chips) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _selectChip(
    String label, {
    required bool selected,
    required VoidCallback onToggle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.8)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.3,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  // ---------------- 已选条件 chips ----------------

  Widget _activeChips(ColorScheme scheme) {
    final chips = <Widget>[];

    void add(String label, VoidCallback onRemove) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InputChip(
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            onDeleted: onRemove,
            visualDensity: VisualDensity.compact,
            backgroundColor: scheme.primaryContainer.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    for (final m in _filters.moods) {
      add(
        '${m.emoji} ${m.label}',
        () => setState(() => _filters.moods.remove(m)),
      );
    }
    for (final w in _filters.weathers) {
      add(
        '${w.emoji} ${w.label}',
        () => setState(() => _filters.weathers.remove(w)),
      );
    }
    for (final t in _filters.tags) {
      add('#$t', () => setState(() => _filters.tags.remove(t)));
    }
    if (_filters.startDate != null) {
      add(
        '${_filters.startDate!.substring(5)} ~ ${_filters.endDate!.substring(5)}',
        () => setState(() {
          _filters.startDate = null;
          _filters.endDate = null;
        }),
      );
    }
    if (_filters.favoritesOnly) {
      add('只看收藏', () => setState(() => _filters.favoritesOnly = false));
    }
    if (_filters.withImagesOnly) {
      add('只看有图', () => setState(() => _filters.withImagesOnly = false));
    }
    chips.add(
      ActionChip(
        label: Text(
          '清空',
          style: TextStyle(fontSize: 12.5, color: scheme.primary),
        ),
        onPressed: () => setState(() {
          _filters.moods.clear();
          _filters.weathers.clear();
          _filters.tags.clear();
          _filters.startDate = null;
          _filters.endDate = null;
          _filters.favoritesOnly = false;
          _filters.withImagesOnly = false;
        }),
        visualDensity: VisualDensity.compact,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: chips),
      ),
    );
  }
}

/// 结果列表：命中数量 + 卡片。
class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.results,
    required this.query,
    this.onDeleted,
  });

  final List<JournalEntry> results;
  final String query;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            children: [
              Text(
                '找到 ${results.length} 篇',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 52,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        query.isEmpty ? '没有符合筛选条件的手账' : '没有找到「$query」相关的手账',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: results.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: EntryCard(
                      entry: results[i],
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditorPage(entry: results[i]),
                          ),
                        );
                        onDeleted?.call();
                      },
                      onToggleFavorite: (id) =>
                          context.read<JournalProvider>().toggleFavorite(id),
                      onDelete: (id) async {
                        await deleteWithUndo(context, id);
                        onDeleted?.call();
                      },
                      onShare: (id) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShareCardPage(entry: results[i]),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
