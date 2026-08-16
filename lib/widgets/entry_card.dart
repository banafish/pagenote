import 'dart:io';

import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/journal_entry.dart';
import '../utils/date_utils.dart';

/// 时间轴中的手账卡片。
class EntryCard extends StatelessWidget {
  const EntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDelete,
    this.onShare,
    this.compact = false,
  });

  final JournalEntry entry;
  final VoidCallback onTap;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<String> onDelete;

  /// 生成分享图（REQ-11.1），为空时隐藏菜单项。
  final ValueChanged<String>? onShare;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateUtils2.parseKey(entry.date);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, scheme, date),
              if (entry.title.trim().isNotEmpty) ...[
                SizedBox(height: compact ? 8 : 12),
                Text(
                  entry.title.trim(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (entry.plainContent.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  entry.plainContent,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (entry.images.isNotEmpty && !compact) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: entry.images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _ImageThumb(path: entry.images[i]),
                  ),
                ),
              ],
              if (entry.activities.isNotEmpty) ...[
                SizedBox(height: compact ? 10 : 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final activity in entry.activities.take(6))
                      Tooltip(
                        message: activity,
                        child: Text(
                          emojiOfActivity(activity),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    if (entry.activities.length > 6)
                      Text(
                        '+${entry.activities.length - 6}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              if (entry.tags.isNotEmpty) ...[
                SizedBox(height: compact ? 10 : 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag in entry.tags.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (entry.tags.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${entry.tags.length - 4}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme, DateTime date) {
    return Row(
      children: [
        if (entry.mood != null)
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: entry.mood!.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(entry.mood!.emoji, style: const TextStyle(fontSize: 21)),
          )
        else
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateUtils2.weekdayOf(entry.date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.month}月${date.day}日',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (entry.weather != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: entry.weather!.label,
              child: Text(entry.weather!.emoji,
                  style: const TextStyle(fontSize: 19)),
            ),
          ),
        _MenuButton(
          isFavorite: entry.isFavorite,
          canShare: onShare != null,
          onToggleFavorite: () => onToggleFavorite(entry.id),
          onDelete: () => onDelete(entry.id),
          onShare: onShare == null ? null : () => onShare!(entry.id),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.isFavorite,
    required this.canShare,
    required this.onToggleFavorite,
    required this.onDelete,
    this.onShare,
  });

  final bool isFavorite;
  final bool canShare;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFavorite)
          const Icon(Icons.favorite, size: 18, color: Color(0xFFE57373)),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz,
              size: 22, color: scheme.onSurfaceVariant),
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'favorite',
              child: Row(
                children: [
                  Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 19,
                    color: isFavorite ? const Color(0xFFE57373) : null,
                  ),
                  const SizedBox(width: 10),
                  Text(isFavorite ? '取消收藏' : '收藏'),
                ],
              ),
            ),
            if (canShare)
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 19),
                    SizedBox(width: 10),
                    Text('生成分享图'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 19, color: Color(0xFFE57373)),
                  SizedBox(width: 10),
                  Text('删除', style: TextStyle(color: Color(0xFFE57373))),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'favorite') onToggleFavorite();
            if (value == 'delete') onDelete();
            if (value == 'share') onShare?.call();
          },
        ),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return Image.file(
              file,
              width: 118,
              height: 92,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(context),
            );
          }
          return _fallback(context);
        },
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 118,
      height: 92,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined,
          size: 30, color: scheme.onSurfaceVariant),
    );
  }
}
