import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/template.dart';
import '../providers/template_provider.dart';

/// 模板管理页（REQ-09.3）：重命名、删除（内置不可删）。
class TemplateManagerPage extends StatelessWidget {
  const TemplateManagerPage({super.key});

  Future<void> _rename(BuildContext context, JournalTemplate template) async {
    final controller = TextEditingController(text: template.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名模板'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '模板名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    template.name = trimmed;
    if (context.mounted) {
      await context.read<TemplateProvider>().saveTemplate(template);
    }
  }

  Future<void> _delete(BuildContext context, JournalTemplate template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除模板？'),
        content: Text('「${template.name}」将被删除，已写的手账不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<TemplateProvider>().deleteTemplate(template.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemplateProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('手账模板')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (provider.builtinTemplates.isNotEmpty) ...[
            _sectionLabel(context, '内置模板'),
            for (final t in provider.builtinTemplates)
              _tile(context, t, canManage: false),
            const SizedBox(height: 18),
          ],
          if (provider.userTemplates.isNotEmpty) ...[
            _sectionLabel(context, '我的模板'),
            for (final t in provider.userTemplates)
              _tile(context, t, canManage: true),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    JournalTemplate template, {
    required bool canManage,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
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
          if (canManage) ...[
            IconButton(
              tooltip: '重命名',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.drive_file_rename_outline_rounded,
                size: 20,
              ),
              onPressed: () => _rename(context, template),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Color(0xFFE57373),
              ),
              onPressed: () => _delete(context, template),
            ),
          ],
        ],
      ),
    );
  }
}
