import 'package:flutter/material.dart';

/// 每日一问卡片（REQ-04）：展示当日一问，可插入正文 / 换一条。
class DailyPromptCard extends StatefulWidget {
  const DailyPromptCard({
    super.key,
    required this.prompt,
    this.onInsert,
    this.onRefresh,
    this.refreshRemaining = 0,
    this.initiallyExpanded = true,
    this.compact = false,
  });

  final String prompt;

  /// 一键将问题插入正文开头；null 时不显示该按钮。
  final VoidCallback? onInsert;

  /// 换一条；null 时不显示该按钮（每日 3 次，由调用方限流）。
  final VoidCallback? onRefresh;
  final int refreshRemaining;
  final bool initiallyExpanded;
  final bool compact;

  @override
  State<DailyPromptCard> createState() => _DailyPromptCardState();
}

class _DailyPromptCardState extends State<DailyPromptCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(widget.compact ? 14 : 16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.secondaryContainer.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates_outlined,
                    size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  '今日一问',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Text(
              widget.prompt,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.6,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            if (widget.onInsert != null || widget.onRefresh != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.onInsert != null)
                    ActionChip(
                      avatar: Icon(Icons.format_quote_rounded,
                          size: 15, color: scheme.primary),
                      label: const Text('插入正文'),
                      onPressed: widget.onInsert,
                    ),
                  const SizedBox(width: 8),
                  if (widget.onRefresh != null)
                    ActionChip(
                      avatar: Icon(Icons.refresh_rounded,
                          size: 15, color: scheme.primary),
                      label: Text(
                        widget.refreshRemaining > 0
                            ? '换一条 (${widget.refreshRemaining})'
                            : '今日已换 3 次',
                      ),
                      onPressed: widget.refreshRemaining > 0
                          ? widget.onRefresh
                          : null,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
