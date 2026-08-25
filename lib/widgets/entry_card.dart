
import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/canvas_page.dart';
import '../models/decoration.dart';
import '../models/journal_entry.dart';
import '../utils/date_utils.dart';
import 'canvas/canvas_view.dart';
import 'stored_image.dart';

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

  /// 旧数据（无 canvas 列）首次展示时合成等价画布并记忆在条目上,
  /// 随条目下次落库自然持久化 —— 非破坏性的渐进迁移。
  JournalCanvas? get _canvas {
    if (entry.canvas != null) return entry.canvas;
    if (!_hasLegacyContent) return null;
    return entry.canvas = synthesizeCanvas(entry);
  }

  bool get _hasLegacyContent =>
      entry.title.trim().isNotEmpty ||
      entry.content.trim().isNotEmpty ||
      entry.images.isNotEmpty ||
      entry.stickers.isNotEmpty ||
      entry.paper.isNotEmpty;

  /// 按画布纵横比渲染整页。
  Widget _page(JournalCanvas canvas) => AspectRatio(
    aspectRatio: 1 / canvas.effectiveHeight,
    child: CanvasView(canvas: canvas, entry: entry),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final canvas = _canvas;
    if (canvas != null) {
      // 画布条目：整页 WYSIWYG 预览（与编辑器、分享长图同一渲染器）。
      final capped = canvas.effectiveHeight > 1.9;
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onTap,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(19),
                    ),
                    child: capped
                        ? SizedBox(
                            height: 1.9 * (compact ? 300.0 : 360.0),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: compact ? 300.0 : 360.0,
                                  child: _page(canvas),
                                ),
                              ),
                            ),
                          )
                        : _page(canvas),
                  ),
                ),
                if (entry.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final tag in entry.tags.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.55,
                              ),
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
                          Text(
                            '+${entry.tags.length - 4}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            // 快速速记「未整理」标记（REQ-16）。
            if (entry.isQuickNote)
              Positioned(
                top: 10,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0x33E6A23C)),
                  ),
                  child: const Text(
                    '未整理',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9C6B1F),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: _MenuButton(
                isFavorite: entry.isFavorite,
                canShare: onShare != null,
                onToggleFavorite: () => onToggleFavorite(entry.id),
                onDelete: () => onDelete(entry.id),
                onShare: onShare == null ? null : () => onShare!(entry.id),
              ),
            ),
          ],
        ),
      );
    }

    // 纸张装饰背景（REQ-13）：设置过纸张的条目以纸张纹理为卡片底。
    final paper = paperById(entry.paper);
    final date = DateUtils2.parseKey(entry.date);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: paper == null ? null : resolvePaperBase(paper, dark: isDark),
      child: Stack(
        children: [
          if (paper != null)
            Positioned.fill(
              child: CustomPaint(painter: PaperPainter(paper, dark: isDark)),
            ),
          InkWell(
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
                        itemBuilder: (context, i) =>
                            _ImageThumb(path: entry.images[i]),
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
                  if (entry.stickers.isNotEmpty) ...[
                    SizedBox(height: compact ? 8 : 10),
                    Text(
                      [
                        for (final s in entry.stickers.take(8)) s.emoji,
                      ].join(' '),
                      style: const TextStyle(fontSize: 14, height: 1.2),
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
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.55,
                              ),
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
        ],
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
            child: Text(
              entry.mood!.emoji,
              style: const TextStyle(fontSize: 21),
            ),
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
              child: Text(
                entry.weather!.emoji,
                style: const TextStyle(fontSize: 19),
              ),
            ),
          ),
        // 快速速记「未整理」标记（REQ-16）。
        if (entry.isQuickNote)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x33E6A23C)),
            ),
            child: const Text(
              '未整理',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9C6B1F),
              ),
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
          icon: Icon(
            Icons.more_horiz,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                  Icon(
                    Icons.delete_outline,
                    size: 19,
                    color: Color(0xFFE57373),
                  ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      // 缺文件 / 解码失败均由 errorBuilder 兜底，无需预先探测存在性。
      child: Image(
        image: storedImageProvider(path),
        width: 118,
        height: 92,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 118,
      height: 92,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        size: 30,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
