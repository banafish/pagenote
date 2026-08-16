import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';
import '../utils/delete_flow.dart';
import '../widgets/entry_card.dart';
import 'share_card_page.dart';

/// 日历页：按月浏览手账记录。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.onOpenEditor});

  final void Function(BuildContext context, JournalEntry? entry) onOpenEditor;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedDay;

  Map<String, List<JournalEntry>> _entriesByDate(JournalProvider journal) {
    final map = <String, List<JournalEntry>>{};
    for (final e in journal.entries) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final byDate = _entriesByDate(journal);
    final todayKey = DateUtils2.dateKey(DateTime.now());
    _selectedDay ??= todayKey;
    if (!_sameMonth(_selectedDay!, _month)) {
      // 月份切换后选中该月第一天或今天。
      final now = DateTime.now();
      _selectedDay = (now.year == _month.year && now.month == _month.month)
          ? todayKey
          : DateUtils2.dateKey(DateTime(_month.year, _month.month, 1));
    }

    final isPhone = MediaQuery.sizeOf(context).width < 760;
    final calendar = _MonthCalendar(
      month: _month,
      byDate: byDate,
      todayKey: todayKey,
      selectedKey: _selectedDay!,
      onSelect: (key) => setState(() => _selectedDay = key),
    );

    final dayList = _DayEntries(
      dateKey: _selectedDay!,
      entries: byDate[_selectedDay!] ?? [],
      onOpen: (entry) => widget.onOpenEditor(context, entry),
      onToggleFavorite: (id) =>
          context.read<JournalProvider>().toggleFavorite(id),
      onDelete: (id) => deleteWithUndo(context, id),
      onShare: (entry) => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ShareCardPage(entry: entry))),
      onNewEntry: () => widget.onOpenEditor(
        context,
        JournalEntry(
          id: JournalProvider.newId(),
          date: _selectedDay!,
          title: '',
          content: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: isPhone
          ? ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [_header(), calendar, dayList],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1060),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: calendar),
                        const SizedBox(width: 20),
                        SizedBox(width: 400, child: dayList),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool _sameMonth(String key, DateTime month) {
    final d = DateUtils2.parseKey(key);
    return d.year == month.year && d.month == month.month;
  }

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '日历',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  DateUtils2.monthTitle(_month),
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '上一月',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() {
              _month = DateTime(_month.year, _month.month - 1);
              _selectedDay = null;
            }),
          ),
          IconButton(
            tooltip: '回到今天',
            icon: Icon(Icons.today_rounded, color: scheme.primary),
            onPressed: () => setState(() {
              final now = DateTime.now();
              _month = DateTime(now.year, now.month);
              _selectedDay = DateUtils2.dateKey(now);
            }),
          ),
          IconButton(
            tooltip: '下一月',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(() {
              _month = DateTime(_month.year, _month.month + 1);
              _selectedDay = null;
            }),
          ),
        ],
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.byDate,
    required this.todayKey,
    required this.selectedKey,
    required this.onSelect,
  });

  final DateTime month;
  final Map<String, List<JournalEntry>> byDate;
  final String todayKey;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils2.daysInMonth(month);
    // 周一为一周起点。
    final leading = (firstDay.weekday - 1) % 7;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in _weekLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(context, row * 7 + col, scheme)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int index, ColorScheme scheme) {
    final leading = (DateTime(month.year, month.month, 1).weekday - 1) % 7;
    final dayNumber = index - leading + 1;
    final valid = dayNumber >= 1 && dayNumber <= DateUtils2.daysInMonth(month);
    if (!valid) return const SizedBox(height: 64);

    final date = DateTime(month.year, month.month, dayNumber);
    final key = DateUtils2.dateKey(date);
    final entries = byDate[key] ?? [];
    final isToday = key == todayKey;
    final isSelected = key == selectedKey;
    final moodEmoji = entries.isNotEmpty ? entries.first.mood?.emoji : null;

    return GestureDetector(
      onTap: () => onSelect(key),
      child: Container(
        height: 64,
        margin: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer
              : entries.isNotEmpty
              ? scheme.secondaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isToday && !isSelected
              ? Border.all(color: scheme.primary, width: 1.4)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            if (moodEmoji != null)
              Text(moodEmoji, style: const TextStyle(fontSize: 15))
            else if (entries.isNotEmpty)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayEntries extends StatelessWidget {
  const _DayEntries({
    required this.dateKey,
    required this.entries,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.onShare,
    required this.onNewEntry,
  });

  final String dateKey;
  final List<JournalEntry> entries;
  final void Function(JournalEntry) onOpen;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<String> onDelete;
  final ValueChanged<JournalEntry> onShare;
  final VoidCallback onNewEntry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateUtils2.friendlyDate(dateKey),
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Text(
                '${entries.length} 篇',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '为此日写手账',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.edit_note_rounded,
                  color: scheme.primary,
                  size: 24,
                ),
                onPressed: onNewEntry,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.edit_calendar_outlined,
                    size: 34,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '这一天还是空白的一页',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: EntryCard(
                  entry: entry,
                  onTap: () => onOpen(entry),
                  onToggleFavorite: onToggleFavorite,
                  onDelete: onDelete,
                  onShare: (_) => onShare(entry),
                  compact: true,
                ),
              ),
        ],
      ),
    );
  }
}
