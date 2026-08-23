import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/template.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../utils/date_utils.dart';
import 'canvas/canvas_view.dart';

/// 模板选择底部弹层（REQ-09.2 + REQ-28）：整页版式模板直接展示画布预览,
/// 「新建 → 选模板 → 替换文字」三步成稿。
///
/// 列表按「内置模板 → 我的模板（自建、不在包里）→ 各素材包」分节（REQ-28.1）：
/// 包顺序与素材页包列表一致（手动排序）,管理侧整理好的结构在取用的
/// 那一刻同样可见；空节不显示,tile 的渲染、预览与套用返回逻辑不变。
Future<JournalTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<JournalTemplate>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      builder: (_, controller) {
        final provider = sheetContext.watch<TemplateProvider>();
        final packs = sheetContext.watch<CustomStickerProvider>().packs;
        final builtin = provider.builtinTemplates;
        final ungrouped = [
          for (final t in provider.templates)
            if (!t.builtin && t.packId == null) t,
        ];
        final sections = <(String, List<JournalTemplate>)>[
          if (builtin.isNotEmpty) ('内置模板', builtin),
          if (ungrouped.isNotEmpty) ('我的模板', ungrouped),
          for (final pack in packs)
            if (provider.templatesOfPack(pack.id).isNotEmpty)
              (pack.name, provider.templatesOfPack(pack.id)),
        ];
        return ListView(
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
            for (final (name, items) in sections) ...[
              _SectionLabel(name: name, count: items.length),
              for (final template in items)
                _TemplateTile(
                  template: template,
                  onTap: () => Navigator.pop(sheetContext, template),
                ),
            ],
          ],
        );
      },
    ),
  );
}

/// 节头（REQ-28.1）：节名 + 数量，样式与素材页包头同一套观感。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '共 $count 套',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
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
