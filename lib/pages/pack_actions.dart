import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../models/template.dart' show JournalTemplate;
import '../providers/custom_sticker_provider.dart';
import '../providers/journal_provider.dart';
import '../providers/template_provider.dart';
import '../services/share_pack_service.dart';
import '../utils/pack_cover_store.dart';
import '../utils/sticker_store.dart';

// ---------------- 分享包导出的公共件（REQ-21.1/21.2，导出页与各处菜单复用） ----------------

/// 导出用的模板副本，画布内的本机照片路径一律清空只留占位框
/// （FIX-01 + REQ-21.4：包内不得含任何本机绝对路径）。本机模板不受影响。
/// 用户勾选「包含照片」时不走这里，改由 buildPack 把照片一并打包。
JournalTemplate templateWithoutPhotos(JournalTemplate template) {
  if (!(template.canvas?.hasImagePaths ?? false)) return template;
  final copy = template.copy();
  copy.canvas?.clearImagePaths();
  return copy;
}

/// 这批模板引用到的自定义贴纸 sha1（REQ-21.3：随包带上，接收方开箱即用）。
Set<String> referencedStickerIds(Iterable<JournalTemplate> templates) => {
  for (final t in templates)
    for (final key in t.canvas?.stickerKeys ?? const <String>{})
      if (key.startsWith(stickerKeyImage))
        key.substring(stickerKeyImage.length),
};

/// 导出前的照片开关（FIX-01.2 / REQ-21.4）：默认不勾，只保留占位框；
/// 勾选后照片一并进包，由 [SharePackService.buildPack] 改写成纯文件名。
///
/// 返回 true 表示带照片导出，false 表示只导出占位框，null 表示用户取消。
Future<bool?> askIncludeTemplatePhotos(
  BuildContext context,
  List<JournalTemplate> withPhotos,
) {
  final names = withPhotos.take(3).map((t) => '「${t.name}」').join('、');
  final suffix = withPhotos.length > 3 ? ' 等 ${withPhotos.length} 套模板' : '';
  final limitMb = SharePackService.maxPackBytes ~/ (1024 * 1024);
  var include = false;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      // 勾选态由对话框自管理：外层 setState 不会重建 showDialog 的 builder。
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('模板里还留着照片'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$names$suffix的版式里还有本机照片。'),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: include,
              onChanged: (v) => setDialogState(() => include = v ?? false),
              title: const Text('包含照片', style: TextStyle(fontSize: 14)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            Text(
              include
                  ? '照片会随包发给对方，先确认里面没有不方便外传的内容；'
                        '带照片的包容易超过 $limitMb MB，超了对方就导不进来。'
                  : '素材包是发给别人的，通常不该带上私人照片：导出的模板只保留照片占位框，'
                        '接收方套用后填自己的图。本机模板不受影响。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, include),
            child: Text(include ? '带照片导出' : '导出'),
          ),
        ],
      ),
    ),
  );
}

/// 导出前的去向选择（REQ-21.5）：移动端在导出的最后一步问一次
/// 「存到文件夹」还是「系统分享」——分享面板由接收方决定落点，
/// 只有文件选择器才能让用户自己挑保存位置。
///
/// 返回所选去向，null 表示用户取消；桌面端本来就能在保存对话框里挑目录，
/// 不必多问一步，直接按 saveToFolder 走。
Future<PackExportDestination?> askPackExportDestination(
  BuildContext context,
) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return PackExportDestination.saveToFolder;
  }
  return showDialog<PackExportDestination>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('素材包导出到'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(dialogContext, PackExportDestination.saveToFolder),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_open_rounded),
            title: Text('保存到文件夹', style: TextStyle(fontSize: 15)),
            subtitle: Text('挑选位置，zip 直接存到本机或网盘'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(dialogContext, PackExportDestination.systemShare),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.share_outlined),
            title: Text('系统分享', style: TextStyle(fontSize: 15)),
            subtitle: Text('发给微信、QQ 好友等'),
          ),
        ),
      ],
    ),
  );
}

/// 把选中的模板打成分享包（REQ-18.2 / REQ-21.1）：单个模板走更多菜单，
/// 多个走多选态。只带被模板引用的自定义贴纸，接收方无需再找素材（REQ-21.3）。
/// 画布带照片时先问一次「包含照片」（FIX-01.2），默认不带。
Future<void> exportTemplatesAsPack(
  BuildContext context,
  List<JournalTemplate> targets,
) async {
  if (targets.isEmpty) return;
  final withPhotos = targets
      .where((t) => t.canvas?.hasImagePaths ?? false)
      .toList();
  var includePhotos = false;
  if (withPhotos.isNotEmpty) {
    final choice = await askIncludeTemplatePhotos(context, withPhotos);
    if (choice == null || !context.mounted) return;
    includePhotos = choice;
  }
  final meta = await askPackMeta(
    context,
    targets.length == 1 ? targets.first.name : '我的模板包',
  );
  if (meta == null || !context.mounted) return;
  final destination = await askPackExportDestination(context);
  if (destination == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final stickers = context.read<CustomStickerProvider>();
  // 带照片时把原始模板交给 buildPack（照片入包 + 路径改写为纯文件名），
  // 不带时先在这里清干净；两条路都不会把本机绝对路径带进包（REQ-21.4）。
  final packed = includePhotos
      ? targets
      : [for (final t in targets) templateWithoutPhotos(t)];
  final ids = referencedStickerIds(packed);
  try {
    final path = await SharePackService.instance.exportPack(
      packName: meta.name,
      author: meta.author,
      templates: packed,
      stickers: [
        for (final s in stickers.stickers)
          if (ids.contains(s.id)) s,
      ],
      stickerBytes: await stickers.exportBytes(ids: ids),
      includePhotos: includePhotos,
      destination: destination,
    );
    // 用户在系统对话框里取消时返回 null，不打扰。
    if (path != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('素材包已导出：$path')));
    }
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
  }
}

/// 把选中的素材（可连同模板混选）打成分享包（REQ-21.2 / REQ-26.7）。
/// 只带素材文件时不带任何模板，接收方装完即可在「我的」页签里用。
/// [packTemplates] 与 [pack] 非空表示从包发起的整包导出：
/// 包内模板一并带上（v8），包名与署名直接预填，pack.json 的 id
/// 用包的稳定 originId，封面写入 cover.png（REQ-27.6）——
/// 接收方导入后归位到同一个包，而不是每次转发都裂出一个新包。
Future<void> exportStickersAsPack(
  BuildContext context,
  List<CustomSticker> targets,
  List<JournalTemplate> packTemplates,
  StickerPack? pack,
) async {
  if (targets.isEmpty && packTemplates.isEmpty) return;
  final withPhotos = packTemplates
      .where((t) => t.canvas?.hasImagePaths ?? false)
      .toList();
  var includePhotos = false;
  if (withPhotos.isNotEmpty) {
    final choice = await askIncludeTemplatePhotos(context, withPhotos);
    if (choice == null || !context.mounted) return;
    includePhotos = choice;
  }
  final meta = await askPackMeta(
    context,
    pack?.name ?? (targets.length == 1 ? targets.first.name : '我的素材包'),
    defaultAuthor: pack?.author ?? '',
  );
  if (meta == null || !context.mounted) return;
  final destination = await askPackExportDestination(context);
  if (destination == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final provider = context.read<CustomStickerProvider>();
  try {
    // 包身份：整包导出复用包的稳定 originId（手工包首次导出时分配并落库）。
    final shareId = pack == null
        ? null
        : await provider.ensurePackOriginId(pack.id);
    // 带照片时把原始模板交给 buildPack（照片入包 + 路径改写为纯文件名），
    // 不带时先在这里清干净；两条路都不会把本机绝对路径带进包（REQ-21.4）。
    final packedTemplates = includePhotos
        ? packTemplates
        : [for (final t in packTemplates) templateWithoutPhotos(t)];
    // 包内模板引用到的贴纸一并带上（REQ-21.3：接收方开箱即用）。
    final ids = {
      for (final s in targets) s.id,
      ...referencedStickerIds(packedTemplates),
    };
    final path = await SharePackService.instance.exportPack(
      packName: meta.name,
      author: meta.author,
      templates: packedTemplates,
      stickers: [
        for (final s in provider.stickers)
          if (ids.contains(s.id)) s,
      ],
      stickerBytes: await provider.exportBytes(ids: ids),
      includePhotos: includePhotos,
      packId: shareId,
      // 整包导出带上封面（REQ-27.6）；文件缺失时静默不带，导出仍可完成。
      coverBytes: pack?.coverPath == null
          ? null
          : await PackCoverStore.readBytes(pack!.coverPath!),
      destination: destination,
    );
    // 用户在系统对话框里取消时返回 null，不打扰。
    if (path != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('素材包已导出：$path')));
    }
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
  }
}

/// 包名与署名（附录 pack.json 的 name / author）；署名可留空。
Future<({String name, String author})?> askPackMeta(
  BuildContext context,
  String defaultName, {
  String defaultAuthor = '',
}) async {
  final nameController = TextEditingController(text: defaultName);
  final authorController = TextEditingController(text: defaultAuthor);
  final meta = await showDialog<({String name, String author})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导出为素材包'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '包名',
              hintText: '如：秋日旅行模板集',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: authorController,
            decoration: const InputDecoration(labelText: '署名（可留空）'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, (
            name: nameController.text.trim(),
            author: authorController.text.trim(),
          )),
          child: const Text('导出'),
        ),
      ],
    ),
  );
  // 对话框关闭还有退出动画，TextField 仍在树中依赖 controller，
  // 立刻 dispose 会触发 _dependents.isEmpty 断言，等动画结束再释放。
  Future.delayed(const Duration(milliseconds: 400), () {
    nameController.dispose();
    authorController.dispose();
  });
  if (meta == null) return null;
  return meta.name.isEmpty ? (name: defaultName, author: meta.author) : meta;
}

// ---------------- 导入图片（REQ-20.1/20.3/20.5，详情页分节标题与空态共用） ----------------

/// 从相册导入图片作为贴纸：先问一句要不要去白底（REQ-20.3），
/// 超限的图片由仓库自动压缩，提示里如实报出压缩张数与压缩后尺寸（REQ-20.5）。
/// [packId] 指定落位素材包（在包详情页导入直接进包）；null 为未分组。
Future<void> importStickersFromGallery(
  BuildContext context, {
  String? packId,
}) async {
  final files = await StickerStore.pickImages();
  if (!context.mounted || files.isEmpty) return;
  final cutWhite = await _askImportOptions(context, files.length);
  if (!context.mounted || cutWhite == null) return;
  final provider = context.read<CustomStickerProvider>();
  final messenger = ScaffoldMessenger.of(context);
  var done = 0;
  var failed = 0;
  final shrunk = <String>[];
  for (final file in files) {
    final result = await _importOne(
      provider,
      file,
      cutWhite: cutWhite,
      packId: packId,
    );
    if (!result.ok) {
      failed++;
      continue;
    }
    done++;
    if (result.shrunk != null) shrunk.add(result.shrunk!);
  }
  if (!context.mounted) return;
  final parts = <String>[
    if (done > 0) '已导入 $done 张素材',
    if (failed > 0) '$failed 张图片无法识别，已跳过',
    if (shrunk.length == 1) '1 张超出上限，已压缩为 ${shrunk.first}',
    if (shrunk.length > 1)
      '${shrunk.length} 张超出上限，已压缩到 ${StickerStore.maxEdge} 像素内',
  ];
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(parts.join('；'))));
}

/// 导入前的选项（REQ-20.3）；返回 null 表示放弃导入。
Future<bool?> _askImportOptions(BuildContext context, int count) {
  var cutWhite = false;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setLocal) => AlertDialog(
        title: const Text('导入为贴纸'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已选择 $count 张图片，长边超过 ${StickerStore.maxEdge} 像素的会自动压缩。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: cutWhite,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('去除白色背景', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '适合白底的手绘与印章；透明 PNG 不必勾选',
                style: TextStyle(fontSize: 11.5),
              ),
              onChanged: (value) => setLocal(() => cutWhite = value ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, cutWhite),
            child: const Text('导入'),
          ),
        ],
      ),
    ),
  );
}

/// 导入单张：按需先去白底，再交给仓库统一压缩落盘。
/// [ok] 为 false 表示图片无法识别；[shrunk] 非空表示触发了压缩，值为压缩后尺寸。
Future<({bool ok, String? shrunk})> _importOne(
  CustomStickerProvider provider,
  XFile file, {
  required bool cutWhite,
  String? packId,
}) async {
  final Uint8List source;
  try {
    final raw = await file.readAsBytes();
    source = cutWhite ? await StickerStore.removeWhiteBackground(raw) : raw;
  } on IOException {
    return (ok: false, shrunk: null);
  }
  final sticker = await provider.importFromFile(
    cutWhite
        ? XFile.fromData(source, path: file.name, mimeType: 'image/png')
        : file,
    packId: packId,
  );
  if (sticker == null) return (ok: false, shrunk: null);
  final before = await pixelSize(source);
  final oversize =
      source.length > StickerStore.maxBytes ||
      (before != null && before.longestSide > StickerStore.maxEdge);
  if (!oversize) return (ok: true, shrunk: null);
  final saved = await StickerStore.readBytes(sticker.id, sticker.ext);
  final after = saved == null ? null : await pixelSize(saved);
  return (
    ok: true,
    shrunk: after == null
        ? '${StickerStore.maxEdge} 像素内'
        : '${after.width.round()}×${after.height.round()}',
  );
}

/// 只读图片头拿像素尺寸（不整张解码），用于如实提示压缩结果（REQ-20.5）；
/// 格式不受支持时返回 null。
Future<Size?> pixelSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  } on Exception {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

// ---------------- 包级操作菜单（详情页右上角与素材首页包卡片共用） ----------------

/// 素材包操作菜单：重命名 / 封面 / 导出整包 / 解散 / 删除（REQ-26.3）。
/// 详情页传 [popWhenRemoved] —— 包没了本页随之出栈；
/// 素材首页不出栈，网格会随数据刷新自行收掉该卡片。
Future<void> showPackMenu(
  BuildContext context,
  StickerPack pack, {
  bool popWhenRemoved = false,
}) async {
  final hasCover = pack.coverPath != null;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (menuContext) => SafeArea(
      // 包菜单条目多，小屏 / 横屏可能超出可用高度，整体可滚动。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pack.name,
                  style: Theme.of(
                    menuContext,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名素材包'),
              onTap: () => Navigator.pop(menuContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(hasCover ? '更换封面' : '上传封面'),
              subtitle: const Text('从相册选一张，长边超 1024 像素会自动压缩'),
              onTap: () => Navigator.pop(menuContext, 'cover'),
            ),
            if (hasCover)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('移除封面'),
                onTap: () => Navigator.pop(menuContext, 'removeCover'),
              ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出整个包'),
              onTap: () => Navigator.pop(menuContext, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('解散素材包'),
              subtitle: const Text('素材保留，移入我的素材'),
              onTap: () => Navigator.pop(menuContext, 'dissolve'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFE57373),
              ),
              title: const Text(
                '删除包与素材',
                style: TextStyle(color: Color(0xFFE57373)),
              ),
              onTap: () => Navigator.pop(menuContext, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final provider = context.read<CustomStickerProvider>();
  final templates = context.read<TemplateProvider>();
  switch (action) {
    case 'rename':
      final name = await promptText(context, '重命名素材包', '包名称', pack.name);
      if (!context.mounted || name == null) return;
      await provider.renamePack(pack.id, name);
    case 'cover':
      await changePackCover(context, pack);
    case 'removeCover':
      await provider.setPackCover(pack.id, null);
    case 'export':
      // 整包导出带上包内模板（v8）与封面（REQ-27.6），
      // 接收方导入后仍是同一个包。
      if (context.mounted) {
        await exportStickersAsPack(
          context,
          provider.stickersOfPack(pack.id),
          templates.templatesOfPack(pack.id),
          pack,
        );
      }
    case 'dissolve':
      // 解散不动素材与模板本身；模板同步移回未分组，
      // 否则会挂着已删除的包 id。
      await provider.dissolvePack(pack.id);
      await templates.detachPack(pack.id);
      if (popWhenRemoved && context.mounted) Navigator.of(context).pop();
    case 'delete':
      await _deletePackWithConfirm(
        context,
        pack,
        popWhenRemoved: popWhenRemoved,
      );
  }
}

/// 上传 / 更换封面（REQ-27.2 / 27.4）：从相册选一张，
/// 超限自动压缩并提示。
Future<void> changePackCover(BuildContext context, StickerPack pack) async {
  final provider = context.read<CustomStickerProvider>();
  final files = await StickerStore.pickImages();
  if (!context.mounted || files.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final Uint8List bytes;
  try {
    bytes = await files.first.readAsBytes();
  } on Exception {
    messenger.showSnackBar(const SnackBar(content: Text('读取封面图片失败')));
    return;
  }
  final stored = await PackCoverStore.importFromBytes(bytes);
  if (stored == null) {
    messenger.showSnackBar(const SnackBar(content: Text('封面图片无法识别或尺寸超限，请换一张')));
    return;
  }
  await provider.setPackCover(pack.id, stored);
  if (!context.mounted) return;
  // 如实提示压缩结果（REQ-27.4，对齐 REQ-20.5 的贴纸约束）。
  final before = await pixelSize(bytes);
  final oversize =
      bytes.length > PackCoverStore.maxBytes ||
      (before != null && before.longestSide > PackCoverStore.maxEdge);
  if (oversize) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('封面超出上限，已自动压缩到 1024 像素内')));
  }
}

/// 删除包与包内全部素材；有素材被手账或模板引用时先说明后果再确认。
/// 包内模板不跟随删除——移回未分组保留（v8）。
Future<void> _deletePackWithConfirm(
  BuildContext context,
  StickerPack pack, {
  required bool popWhenRemoved,
}) async {
  final provider = context.read<CustomStickerProvider>();
  final templates = context.read<TemplateProvider>();
  final items = provider.stickersOfPack(pack.id);
  final packTemplates = templates.templatesOfPack(pack.id);
  final referenced = items
      .where(
        (s) => provider.isReferenced(
          s.id,
          context.read<JournalProvider>().entries,
          templates.templates,
        ),
      )
      .length;
  final templateNote = packTemplates.isEmpty
      ? ''
      : '\n包内 ${packTemplates.length} 套模板会保留，移回我的素材。';
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除素材包？'),
      content: Text(
        referenced > 0
            ? '「${pack.name}」共 ${items.length} 张素材，其中 $referenced 张正被手账或模板使用，'
                  '删除后那些位置会显示缺失占位。$templateNote'
            : '「${pack.name}」与包内 ${items.length} 张素材将被移除。$templateNote\n'
                  '只想去掉这个包的话，用「解散素材包」可以保留素材。',
      ),
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
  if (ok != true || !context.mounted) return;
  await provider.deletePack(pack.id);
  // 模板保留，只解除对已删包的归属。
  await templates.detachPack(pack.id);
  if (popWhenRemoved && context.mounted) Navigator.of(context).pop();
}

/// 单行文本输入对话框（重命名 / 起名共用）；空输入视为取消。
Future<String?> promptText(
  BuildContext context,
  String title,
  String hint,
  String initial,
) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
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
  // 对话框退出动画期间 TextField 仍依赖 controller，延后释放。
  Future.delayed(const Duration(milliseconds: 400), controller.dispose);
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
