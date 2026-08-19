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
import '../utils/sticker_store.dart';

/// 素材格子的目标宽度与比例（图 + 一行名字），窄屏自动减列。
const _cellExtent = 110.0;
const _cellRatio = 0.80;
const _cellSpacing = 12.0;
const _gridPadding = 16.0;

/// 新导入素材的高亮时长（REQ-21.9）：呼吸描边亮一小会儿即回落，
/// 不做成常驻标记，否则下次进页面还带着「新」字反而误导。
const _highlightDuration = Duration(seconds: 4);

/// 我的素材管理页（REQ-20.4 + REQ-21.2 / 21.9）。
///
/// 素材面板的「我的」页签在编辑器底部弹层里，空间只够单个素材的角标菜单；
/// 打包导出要多选、导入后要跳转高亮，都得有一个能从根 Navigator push 的
/// 独立页面来承载，因此把这两件事收在这里，与模板管理页一一对应。
class StickerManagerPage extends StatefulWidget {
  const StickerManagerPage({super.key, this.highlightStickerIds = const []});

  /// 刚从分享包装进来的素材 sha1，进页后高亮并滚到第一个（REQ-21.9）。
  final List<String> highlightStickerIds;

  @override
  State<StickerManagerPage> createState() => _StickerManagerPageState();
}

class _StickerManagerPageState extends State<StickerManagerPage>
    with SingleTickerProviderStateMixin {
  /// 多选态（REQ-21.2）：顶栏按钮或长按素材进入，与单个素材的菜单错开。
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  /// 仍在高亮中的素材 id；到点清空，卡片随即回到常态。
  final Set<String> _highlightIds = {};

  /// 高亮素材的格子 key，用于自动滚动到第一个。
  final Map<String, GlobalKey> _highlightKeys = {};

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.highlightStickerIds.isEmpty) return;
    _highlightIds.addAll(widget.highlightStickerIds);
    for (final id in _highlightIds) {
      _highlightKeys[id] = GlobalKey();
    }
    _pulse.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHighlight();
      _scheduleHighlightFade();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 滚到第一个新导入的素材（REQ-21.9）。懒加载的网格首帧未必建到目标格子，
  /// 拿不到 context 时退几帧再试，仍拿不到就放弃滚动，只保留描边。
  void _scrollToHighlight([int attempt = 0]) {
    if (!mounted || _highlightIds.isEmpty) return;
    final ordered = [
      for (final group in _grouped(
        context.read<CustomStickerProvider>().stickers,
      ))
        for (final sticker in group.items)
          if (_highlightIds.contains(sticker.id)) sticker,
    ];
    if (ordered.isEmpty) return;
    final target = _highlightKeys[ordered.first.id]?.currentContext;
    if (target == null) {
      if (attempt >= 3) return;
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _scrollToHighlight(attempt + 1),
      );
      return;
    }
    Scrollable.ensureVisible(
      target,
      alignment: 0.3,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleHighlightFade() {
    Future.delayed(_highlightDuration, () {
      if (!mounted) return;
      _pulse.stop();
      setState(_highlightIds.clear);
    });
  }

  // ---------------- 导入（REQ-20.1/20.3/20.5） ----------------

  /// 从相册导入图片作为贴纸：先问一句要不要去白底（REQ-20.3），
  /// 超限的图片由仓库自动压缩，提示里如实报出压缩张数与压缩后尺寸（REQ-20.5）。
  Future<void> _importStickers() async {
    final files = await StickerStore.pickImages();
    if (!mounted || files.isEmpty) return;
    final cutWhite = await _askImportOptions(files.length);
    if (!mounted || cutWhite == null) return;
    final provider = context.read<CustomStickerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    var done = 0;
    var failed = 0;
    final shrunk = <String>[];
    for (final file in files) {
      final result = await _importOne(provider, file, cutWhite: cutWhite);
      if (!result.ok) {
        failed++;
        continue;
      }
      done++;
      if (result.shrunk != null) shrunk.add(result.shrunk!);
    }
    if (!mounted) return;
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
  Future<bool?> _askImportOptions(int count) {
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
    );
    if (sticker == null) return (ok: false, shrunk: null);
    final before = await _pixelSize(source);
    final oversize =
        source.length > StickerStore.maxBytes ||
        (before != null && before.longestSide > StickerStore.maxEdge);
    if (!oversize) return (ok: true, shrunk: null);
    final saved = await StickerStore.readBytes(sticker.id, sticker.ext);
    final after = saved == null ? null : await _pixelSize(saved);
    return (
      ok: true,
      shrunk: after == null
          ? '${StickerStore.maxEdge} 像素内'
          : '${after.width.round()}×${after.height.round()}',
    );
  }

  /// 只读图片头拿像素尺寸（不整张解码），用于如实提示压缩结果（REQ-20.5）；
  /// 格式不受支持时返回 null。
  Future<Size?> _pixelSize(Uint8List bytes) async {
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

  // ---------------- 单个素材的操作（REQ-20.4） ----------------

  /// 素材操作菜单：重命名 / 分组 / 导出 / 删除。
  Future<void> _stickerMenu(CustomSticker sticker) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (menuContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名'),
              subtitle: Text(sticker.name),
              onTap: () => Navigator.pop(menuContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('分组'),
              subtitle: Text(sticker.category),
              onTap: () => Navigator.pop(menuContext, 'category'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出为素材包'),
              onTap: () => Navigator.pop(menuContext, 'export'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFE57373),
              ),
              title: const Text(
                '删除',
                style: TextStyle(color: Color(0xFFE57373)),
              ),
              onTap: () => Navigator.pop(menuContext, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        final name = await _promptText('重命名素材', '素材名称', sticker.name);
        if (!mounted || name == null) return;
        await context.read<CustomStickerProvider>().rename(sticker.id, name);
      case 'category':
        final group = await _promptText('素材分组', '分组名称', sticker.category);
        if (!mounted || group == null) return;
        await context.read<CustomStickerProvider>().setCategory(
          sticker.id,
          group,
        );
      case 'export':
        await _exportPack([sticker]);
      case 'delete':
        await _delete(sticker);
    }
  }

  Future<String?> _promptText(String title, String hint, String initial) async {
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
    controller.dispose();
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 删除素材；被手账或模板引用时先说明后果再确认（REQ-20.4）。
  Future<void> _delete(CustomSticker sticker) async {
    final provider = context.read<CustomStickerProvider>();
    final referenced = provider.isReferenced(
      sticker.id,
      context.read<JournalProvider>().entries,
      context.read<TemplateProvider>().templates,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除素材？'),
        content: Text(
          referenced
              ? '有手账正在使用「${sticker.name}」，删除后那些位置会显示缺失占位。'
              : '「${sticker.name}」将从素材库移除。',
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
    if (ok != true || !mounted) return;
    await provider.delete(sticker.id);
    if (!mounted) return;
    setState(() => _selectedIds.remove(sticker.id));
  }

  // ---------------- 导出素材包（REQ-21.2） ----------------

  /// 把选中的素材打成 kind = sticker 的分享包（REQ-21.2）：
  /// 只带素材文件，不带任何模板，接收方装完即可在「我的」页签里用。
  Future<void> _exportPack(List<CustomSticker> targets) async {
    if (targets.isEmpty) return;
    final meta = await _askPackMeta(
      targets.length == 1 ? targets.first.name : '我的素材包',
    );
    if (meta == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<CustomStickerProvider>();
    try {
      final path = await SharePackService.instance.exportPack(
        packName: meta.name,
        author: meta.author,
        templates: const <JournalTemplate>[],
        stickers: targets,
        stickerBytes: await provider.exportBytes(
          ids: [for (final s in targets) s.id],
        ),
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
    if (mounted && _selecting) _exitSelection();
  }

  /// 包名与署名（附录 pack.json 的 name / author）；署名可留空。
  Future<({String name, String author})?> _askPackMeta(
    String defaultName,
  ) async {
    final nameController = TextEditingController(text: defaultName);
    final authorController = TextEditingController();
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
                hintText: '如：手绘小花贴纸',
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
    nameController.dispose();
    authorController.dispose();
    if (meta == null) return null;
    return meta.name.isEmpty ? (name: defaultName, author: meta.author) : meta;
  }

  void _toggleSelect(CustomSticker sticker) {
    setState(() {
      if (!_selectedIds.remove(sticker.id)) _selectedIds.add(sticker.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  // ---------------- 布局 ----------------

  /// 按分组切段（与素材面板「我的」页签同一套分组语义）。
  List<({String category, List<CustomSticker> items})> _grouped(
    List<CustomSticker> all,
  ) {
    final names = all.map((s) => s.category).toSet().toList()..sort();
    return [
      for (final name in names)
        (
          category: name,
          items: [
            for (final sticker in all)
              if (sticker.category == name) sticker,
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final stickers = context.watch<CustomStickerProvider>().stickers;
    return Scaffold(
      appBar: _selecting
          ? _selectionBar(stickers)
          : AppBar(
              title: const Text('我的素材'),
              actions: [
                IconButton(
                  tooltip: '导入图片',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: _importStickers,
                ),
                IconButton(
                  tooltip: '多选导出',
                  icon: const Icon(Icons.checklist_rounded),
                  onPressed: stickers.isEmpty
                      ? null
                      : () => setState(() => _selecting = true),
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: stickers.isEmpty
          ? _emptyGuide()
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hintBar()),
                for (final group in _grouped(stickers)) ...[
                  _sectionLabel(group.category, '共 ${group.items.length} 张'),
                  _grid(group.items),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
    );
  }

  /// 多选态顶栏（REQ-21.2）：已选计数 + 全选 + 明确的退出入口。
  PreferredSizeWidget _selectionBar(List<CustomSticker> all) {
    final allSelected = all.isNotEmpty && _selectedIds.length == all.length;
    return AppBar(
      leading: IconButton(
        tooltip: '退出多选',
        icon: const Icon(Icons.close_rounded),
        onPressed: _exitSelection,
      ),
      title: Text('已选 ${_selectedIds.length} 张'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _selectedIds.clear();
            if (!allSelected) _selectedIds.addAll(all.map((s) => s.id));
          }),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        IconButton(
          tooltip: '导出为素材包',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: _selectedIds.isEmpty
              ? null
              : () => _exportPack([
                  for (final s in all)
                    if (_selectedIds.contains(s.id)) s,
                ]),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _hintBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding + 4, 12, _gridPadding, 2),
      child: Text(
        _selecting ? '点素材勾选，选好后点右上角导出为素材包' : '点素材可重命名 / 分组 / 删除，长按进入多选',
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _sectionLabel(String text, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _gridPadding + 4,
          14,
          _gridPadding,
          8,
        ),
        child: Row(
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              hint,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<CustomSticker> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _cellExtent,
          mainAxisSpacing: _cellSpacing,
          crossAxisSpacing: _cellSpacing,
          childAspectRatio: _cellRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _cell(items[i]),
      ),
    );
  }

  /// 高亮素材做呼吸描边（REQ-21.9），其余格子不订阅动画，避免整页重建。
  Widget _cell(CustomSticker sticker) {
    if (!_highlightIds.contains(sticker.id)) {
      return _cellBody(sticker, glow: 0);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => _cellBody(sticker, glow: _pulse.value),
    );
  }

  Widget _cellBody(CustomSticker sticker, {required double glow}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedIds.contains(sticker.id);
    final highlighted = _highlightIds.contains(sticker.id);
    final Color border;
    if (selected) {
      border = scheme.primary;
    } else if (highlighted) {
      border = scheme.tertiary.withValues(alpha: 0.45 + 0.55 * glow);
    } else {
      border = scheme.outlineVariant.withValues(alpha: 0.5);
    }
    return Container(
      key: _highlightKeys[sticker.id],
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: border,
          width: selected || highlighted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (_selecting) {
            _toggleSelect(sticker);
          } else {
            _stickerMenu(sticker);
          }
        },
        onLongPress: _selecting
            ? null
            : () => setState(() {
                _selecting = true;
                _selectedIds.add(sticker.id);
              }),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                    child: Image.file(
                      File(StickerStore.pathOf(sticker.id, sticker.ext)),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
                  child: Text(
                    sticker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (highlighted)
              const Positioned(left: 5, top: 5, child: _NewBadge()),
            if (_selecting)
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyGuide() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 38,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有自己的素材',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '从相册导入图片做成自己的贴纸，就能像内置贴纸一样贴到手账上，'
              '也能打包成素材包分享给朋友',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _importStickers,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('导入图片'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新导入素材的角标（REQ-21.9），与模板管理页的「新导入」标记同一套观感。
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '新导入',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
