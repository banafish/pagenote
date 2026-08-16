import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/template.dart';
import '../providers/template_provider.dart';

/// 模板选择底部弹层（REQ-09.2）：新建手账时一键套用。
Future<JournalTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<JournalTemplate>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
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
            '将一键填充预设标题与分节结构',
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
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                    if (template.content.trim().isNotEmpty) ...[
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
