import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';

/// 回收站（REQ-02）：软删除条目保留 30 天，可恢复 / 彻底删除 / 清空。
class TrashPage extends StatelessWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final trashed = journal.trashedEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (trashed.isNotEmpty)
            TextButton(
              onPressed: () => _confirmEmptyAll(context),
              child: const Text('清空', style: TextStyle(color: Color(0xFFE57373))),
            ),
        ],
      ),
      body: trashed.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 52, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    '回收站是空的',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '删除的手账会在这里保留 30 天',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: trashed.length,
              itemBuilder: (context, i) =>
                  _TrashItem(entry: trashed[i]),
            ),
    );
  }

  void _confirmEmptyAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('回收站中的全部手账及其图片将被彻底删除，无法恢复。'),
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
              context.read<JournalProvider>().emptyTrash();
            },
            child: const Text('彻底清空'),
          ),
        ],
      ),
    );
  }
}

class _TrashItem extends StatelessWidget {
  const _TrashItem({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysLeft = entry.deletedAt == null
        ? JournalProvider.trashRetentionDays
        : JournalProvider.trashRetentionDays -
            DateTime.now().difference(entry.deletedAt!).inDays;
    final preview = entry.title.trim().isNotEmpty
        ? entry.title.trim()
        : entry.plainContent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.isEmpty ? '（无内容）' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateUtils2.fullDate(entry.date)} · ${daysLeft > 0 ? '$daysLeft 天后自动清除' : '即将清除'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '恢复',
            icon: Icon(Icons.restore_rounded, color: scheme.primary),
            onPressed: () =>
                context.read<JournalProvider>().restoreEntry(entry.id),
          ),
          IconButton(
            tooltip: '彻底删除',
            icon: const Icon(Icons.delete_forever_rounded,
                color: Color(0xFFE57373)),
            onPressed: () => _confirmDeleteForever(context),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteForever(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('彻底删除？'),
        content: const Text('这篇手账及其图片将被永久删除，无法恢复。'),
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
              context.read<JournalProvider>().permanentDelete(entry.id);
            },
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
  }
}
