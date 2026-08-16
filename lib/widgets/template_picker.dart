import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/template.dart';
import '../providers/template_provider.dart';
import '../utils/date_utils.dart';
import 'canvas/canvas_view.dart';

/// 模板选择底部弹层（REQ-09.2 + 调研二阶段）：
/// 整页版式模板直接展示画布预览,「新建 → 选模板 → 替换文字」三步成稿。
Future<JournalTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<JournalTemplate>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            '选择模板',
            style: Theme.of(
              sheetContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '套用整页版式,替换文字即可成稿',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (final template
              in sheetContext.watch<TemplateProvider>().templates)
            _TemplateTile(
              template: template,
              onTap: () => Navigator.pop(sheetContext, template),
            ),
        ],
      ),
    ),
  );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.template, required this.onTap});

  final JournalTemplate template;
  final VoidCallback onTap;

  /// 预览用条目：组件元素（日期/心情等）从它读取展示数据。
  static final _previewEntry = JournalEntry(
    id: 'preview',
    date: DateUtils2.dateKey(DateTime.now()),
    title: '',
    content: '',
    mood: Mood.calm,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 整页版式预览（纯文本模板回退为图标）。
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: template.canvas == null
                      ? Container(
                          color: scheme.primaryContainer.withValues(alpha: 0.6),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.description_outlined,
                            size: 20,
                            color: scheme.onPrimaryContainer,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: 112,
                            child: AspectRatio(
                              aspectRatio: 1 / template.canvas!.effectiveHeight,
                              child: CanvasView(
                                canvas: template.canvas!,
                                entry: _previewEntry,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (template.isTodayTemplate) ...[
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            template.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (template.builtin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withValues(
                                alpha: 0.7,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '内置',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (template.isTodayTemplate) ...[
                      const SizedBox(height: 3),
                      Text(
                        '自动填入今日一问',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (template.content.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        template.content.trim().replaceAll('\n', ' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
