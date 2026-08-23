import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../models/template.dart' show JournalTemplate;
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';

/// 把素材移入素材包的完整流程（贴纸菜单、模板菜单与多选移动共用）：
/// 底部弹层列出「新建素材包 / 移回我的素材 / 现有包」，选定即移动。
/// 没有任何包且不想新建时，用户直接取消即可。
///
/// [move] 收到目标 packId 执行实际移动（null = 移回未分组）；
/// 返回移动目标的显示名（包名或「我的素材」），用户取消时为 null。
Future<String?> moveToPackFlow(
  BuildContext context, {
  required String title,
  String? currentPackId,
  required Future<void> Function(String? packId) move,
}) async {
  final provider = context.read<CustomStickerProvider>();
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      // 包多时条目可能超出可用高度，整体可滚动。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建素材包…'),
              onTap: () => Navigator.pop(sheetContext, '__new__'),
            ),
            if (currentPackId != null)
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('移回我的素材'),
                onTap: () => Navigator.pop(sheetContext, '__ungrouped__'),
              ),
            for (final pack in provider.packs)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(pack.name),
                subtitle: pack.author.trim().isEmpty
                    ? null
                    : Text('来自 ${pack.author}'),
                trailing: pack.id == currentPackId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, pack.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (action == null) return null;
  switch (action) {
    case '__new__':
      if (!context.mounted) return null;
      final name = await _promptPackName(context);
      if (name == null) return null;
      final pack = await provider.createPack(name);
      if (pack == null) return null;
      await move(pack.id);
      return pack.name;
    case '__ungrouped__':
      await move(null);
      return '我的素材';
    default:
      await move(action);
      return provider.packById(action)?.name ?? '素材包';
  }
}

/// 把一张贴纸移入素材包（详情页贴纸菜单入口）。
Future<void> moveStickerToPackFlow(
  BuildContext context,
  CustomSticker sticker,
) async {
  await moveToPackFlow(
    context,
    title: '移动「${sticker.name}」到…',
    currentPackId: sticker.packId,
    move: (packId) => context.read<CustomStickerProvider>().moveStickerToPack(
      sticker.id,
      packId,
    ),
  );
}

/// 把一套模板移入素材包（详情页模板菜单入口，与贴纸同一套弹层）。
Future<void> moveTemplateToPackFlow(
  BuildContext context,
  JournalTemplate template,
) async {
  await moveToPackFlow(
    context,
    title: '移动「${template.name}」到…',
    currentPackId: template.packId,
    move: (packId) => context.read<TemplateProvider>().moveTemplateToPack(
      template.id,
      packId,
    ),
  );
}

Future<String?> _promptPackName(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('新建素材包'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '包名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  // 对话框退出动画期间 TextField 仍依赖 controller，延后释放。
  Future.delayed(const Duration(milliseconds: 400), controller.dispose);
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
