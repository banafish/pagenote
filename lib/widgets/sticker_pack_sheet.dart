import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../providers/custom_sticker_provider.dart';

/// 把一张贴纸移入素材包的完整流程（素材管理页与素材面板的角标菜单共用）：
/// 底部弹层列出「新建素材包 / 移回我的素材 / 现有包」，选定即移动。
/// 没有任何包且不想新建时，用户直接取消即可。
Future<void> moveStickerToPackFlow(
  BuildContext context,
  CustomSticker sticker,
) async {
  final provider = context.read<CustomStickerProvider>();
  final packs = provider.packs;
  final current = sticker.packId;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '移动「${sticker.name}」到…',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('新建素材包…'),
            onTap: () => Navigator.pop(sheetContext, '__new__'),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('移回我的素材'),
              onTap: () => Navigator.pop(sheetContext, '__ungrouped__'),
            ),
          for (final pack in packs)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(pack.name),
              subtitle: pack.author.trim().isEmpty
                  ? null
                  : Text('来自 ${pack.author}'),
              trailing: pack.id == current
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(sheetContext, pack.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null) return;
  switch (action) {
    case '__new__':
      if (!context.mounted) return;
      final name = await _promptPackName(context);
      if (name == null) return;
      final pack = await provider.createPack(name);
      if (pack != null) await provider.moveStickerToPack(sticker.id, pack.id);
    case '__ungrouped__':
      await provider.moveStickerToPack(sticker.id, null);
    default:
      await provider.moveStickerToPack(sticker.id, action);
  }
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
