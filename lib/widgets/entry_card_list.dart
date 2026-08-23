import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../pages/share_card_page.dart';
import '../providers/journal_provider.dart';
import '../utils/delete_flow.dart';
import 'entry_card.dart';

/// 手账卡片列表的单列 / 自适应多列排布，时光页与回顾页共用。
///
/// 多列视图：条目左右交替流入自适应列数的纵向栏，栏宽过窄时卡片
/// 自动改用紧凑排布；单列的间距与是否紧凑由调用方决定。
class EntryCardList extends StatelessWidget {
  const EntryCardList({
    super.key,
    required this.entries,
    required this.onOpen,
    this.multiColumn = false,
    this.spacing = 14,
    this.compact = false,
  });

  final List<JournalEntry> entries;
  final void Function(JournalEntry) onOpen;

  /// 是否多列视图。
  final bool multiColumn;

  /// 相邻卡片的纵向间距。
  final double spacing;

  /// 单列模式下卡片是否用紧凑排布（回顾页当日列表用）。
  final bool compact;

  /// 多列视图中相邻两栏的间距。
  static const _columnSpacing = 12.0;

  /// 多列视图每栏的目标宽度，据此随屏宽自适应列数。
  static const _columnTargetWidth = 400.0;

  /// 栏宽低于该值时卡片改用紧凑排布（隐藏图片条、压缩留白）。
  static const _compactColumnWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    if (!multiColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: _entryCard(context, entry, compact: compact),
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 至少两列；宽屏从两列起步，更宽时按目标栏宽继续加列。
        final count = (constraints.maxWidth / _columnTargetWidth)
            .floor()
            .clamp(2, 6)
            .toInt();
        final columnWidth =
            (constraints.maxWidth - _columnSpacing * (count - 1)) / count;
        final dense = columnWidth < _compactColumnWidth;
        final cells = List.generate(count, (_) => <Widget>[]);
        for (var i = 0; i < entries.length; i++) {
          cells[i % count].add(
            Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: _entryCard(context, entries[i], compact: dense),
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < count; c++) ...[
              if (c > 0) const SizedBox(width: _columnSpacing),
              Expanded(child: Column(children: cells[c])),
            ],
          ],
        );
      },
    );
  }

  Widget _entryCard(
    BuildContext context,
    JournalEntry entry, {
    bool compact = false,
  }) {
    return EntryCard(
      entry: entry,
      compact: compact,
      onTap: () => onOpen(entry),
      onToggleFavorite: (id) =>
          context.read<JournalProvider>().toggleFavorite(id),
      onDelete: (id) => deleteWithUndo(context, id),
      onShare: (_) => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ShareCardPage(entry: entry))),
    );
  }
}
