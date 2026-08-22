import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../models/template.dart' show JournalTemplate;
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../services/share_pack_service.dart';
import '../utils/sticker_store.dart';
import 'sticker_manager_page.dart';
import 'template_manager_page.dart';

/// 素材库的两个子页签（REQ-23.2）：默认落在「模板」——
/// 内置模板保证首屏永不为空，新用户不会看到一个空白的一级入口。
enum LibraryTab { templates, stickers }

/// 素材库宿主页（REQ-23）：「手账模板」与「我的素材」从设置页提为一级入口，
/// 合并为一个「素材」目的地，内部分「模板 / 贴纸」两个子页签。
///
/// 两个管理页已拆为纯 body（[TemplateManagerBody] / [StickerManagerBody]），
/// 顶栏——含多选态的整体替换（REQ-21.1 / 21.2）与导入按钮——由本宿主统一渲染，
/// 子页签里不会出现双层 AppBar。多选状态与导出回调随之上提到这里。
/// 独立整页形态（[TemplateManagerPage] / [StickerManagerPage]）是
/// 「同一副壳 + 单个 body」的薄封装：编辑器贴纸面板的「管理」与素材包
/// 导入回跳仍以整页打开它们（REQ-23.5），两种形态共用一套实现。
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.initialTab = LibraryTab.templates,
    this.showTabs = true,
    this.templateHighlightIds = const [],
    this.stickerHighlightIds = const [],
  });

  /// 打开时落在哪个子页签：一级入口恒为模板，整页形态由调用方指定。
  final LibraryTab initialTab;

  /// false = 独立整页形态：不渲染子页签栏，只挂 [initialTab] 对应的 body。
  final bool showTabs;

  /// 刚从分享包装进来的模板 id，高亮定位与整页形态同一套表现（REQ-23.6）。
  final List<String> templateHighlightIds;

  /// 刚从分享包装进来的素材 sha1，高亮定位与整页形态同一套表现（REQ-23.6）。
  final List<String> stickerHighlightIds;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late LibraryTab _tab = widget.initialTab;

  /// 两个子页签各自的多选态（REQ-21.1 / 21.2）：状态随宿主保存，
  /// 切页签、进出一级入口都不丢（REQ-23.3）。
  bool _templateSelecting = false;
  final Set<String> _selectedTemplateIds = {};
  bool _stickerSelecting = false;
  final Set<String> _selectedStickerIds = {};

  // ---------------- 多选状态（上提自两个管理页） ----------------

  void _toggleTemplateSelect(JournalTemplate template) => setState(() {
    if (!_selectedTemplateIds.remove(template.id)) {
      _selectedTemplateIds.add(template.id);
    }
  });

  void _exitTemplateSelection() => setState(() {
    _templateSelecting = false;
    _selectedTemplateIds.clear();
  });

  void _toggleStickerSelect(CustomSticker sticker) => setState(() {
    if (!_selectedStickerIds.remove(sticker.id)) {
      _selectedStickerIds.add(sticker.id);
    }
  });

  /// 长按素材进入多选并带上这一张（REQ-21.2）。
  void _longPressSelectSticker(CustomSticker sticker) => setState(() {
    _stickerSelecting = true;
    _selectedStickerIds.add(sticker.id);
  });

  void _exitStickerSelection() => setState(() {
    _stickerSelecting = false;
    _selectedStickerIds.clear();
  });

  // ---------------- 导出素材包（REQ-21.1 / 21.2） ----------------

  /// 模板导出分享（REQ-18.2 / REQ-21.1）：单个模板走更多菜单，多个走多选态。
  /// 只带被模板引用的自定义贴纸，接收方无需再找素材（REQ-21.3）。
  /// 画布带照片时先问一次「包含照片」（FIX-01.2），默认不带。
  Future<void> _exportTemplates(List<JournalTemplate> targets) async {
    if (targets.isEmpty) return;
    final withPhotos = targets
        .where((t) => t.canvas?.hasImagePaths ?? false)
        .toList();
    var includePhotos = false;
    if (withPhotos.isNotEmpty) {
      final choice = await askIncludeTemplatePhotos(context, withPhotos);
      if (choice == null || !mounted) return;
      includePhotos = choice;
    }
    final meta = await _askPackMeta(
      targets.length == 1 ? targets.first.name : '我的模板包',
    );
    if (meta == null || !mounted) return;
    final destination = await askPackExportDestination(context);
    if (destination == null || !mounted) return;

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
    if (mounted && _templateSelecting) _exitTemplateSelection();
  }

  /// 把选中的素材打成分享包（REQ-21.2）：只带素材文件时不带任何模板，
  /// 接收方装完即可在「我的」页签里用。
  /// [packTemplates] 与 [pack] 非空表示从包菜单发起的整包导出：
  /// 包内模板一并带上（v8），包名与署名直接预填，pack.json 的 id
  /// 用包的稳定 originId——接收方导入后归位到同一个包，
  /// 而不是每次转发都裂出一个新包。
  Future<void> _exportStickers(
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
      if (choice == null || !mounted) return;
      includePhotos = choice;
    }
    final meta = await _askPackMeta(
      pack?.name ??
          (targets.length == 1 ? targets.first.name : '我的素材包'),
      defaultAuthor: pack?.author ?? '',
    );
    if (meta == null || !mounted) return;
    final destination = await askPackExportDestination(context);
    if (destination == null || !mounted) return;

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
    if (mounted && _stickerSelecting) _exitStickerSelection();
  }

  /// 包名与署名（附录 pack.json 的 name / author）；署名可留空。
  Future<({String name, String author})?> _askPackMeta(
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

  // ---------------- 导入图片（REQ-20.1/20.3/20.5） ----------------

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

  // ---------------- 顶栏与布局 ----------------

  @override
  Widget build(BuildContext context) {
    final isTemplates = _tab == LibraryTab.templates;
    final selecting = isTemplates ? _templateSelecting : _stickerSelecting;
    // 只 watch 当前子页签的仓库：另一个 body 活在 IndexedStack 里，
    // 自己会跟随各自的 provider，宿主顶栏不必陪着整页重建。
    final templates = isTemplates
        ? context.watch<TemplateProvider>().templates
        : const <JournalTemplate>[];
    final stickers = isTemplates
        ? const <CustomSticker>[]
        : context.watch<CustomStickerProvider>().stickers;

    final templateBody = TemplateManagerBody(
      selecting: _templateSelecting,
      selectedIds: _selectedTemplateIds,
      highlightIds: widget.templateHighlightIds,
      onToggleSelect: _toggleTemplateSelect,
      onExport: _exportTemplates,
    );
    final stickerBody = StickerManagerBody(
      selecting: _stickerSelecting,
      selectedIds: _selectedStickerIds,
      highlightStickerIds: widget.stickerHighlightIds,
      onToggleSelect: _toggleStickerSelect,
      onLongPressSelect: _longPressSelectSticker,
      onSelectionChanged: () => setState(() {}),
      onImport: _importStickers,
      onExport: _exportStickers,
    );

    return DefaultTabController(
      initialIndex: widget.initialTab.index,
      length: 2,
      child: Scaffold(
        appBar: selecting
            ? _selectionBar(
                isTemplates: isTemplates,
                templates: templates,
                stickers: stickers,
              )
            : AppBar(
                title: Text(
                  widget.showTabs
                      ? '素材'
                      : (isTemplates ? '手账模板' : '我的素材'),
                ),
                actions: [
                  if (isTemplates)
                    IconButton(
                      tooltip: '多选导出',
                      icon: const Icon(Icons.checklist_rounded),
                      onPressed: templates.isEmpty
                          ? null
                          : () => setState(() => _templateSelecting = true),
                    )
                  else ...[
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
                          : () => setState(() => _stickerSelecting = true),
                    ),
                  ],
                  const SizedBox(width: 4),
                ],
                // 多选态下隐藏子页签栏（REQ-23.4），
                // 避免用户误以为可以跨页签混选。
                bottom: (widget.showTabs && !selecting)
                    ? TabBar(
                        onTap: (index) =>
                            setState(() => _tab = LibraryTab.values[index]),
                        tabs: const [Tab(text: '模板'), Tab(text: '贴纸')],
                      )
                    : null,
              ),
        // 子页签用 IndexedStack 切换：滚动位置、排序方式与网格状态
        // 在页签切换、一级入口进出后都保留（REQ-23.3 / NFR-09）。
        body: widget.showTabs
            ? IndexedStack(
                index: _tab.index,
                children: [templateBody, stickerBody],
              )
            : (isTemplates ? templateBody : stickerBody),
      ),
    );
  }

  /// 多选态顶栏（REQ-21.1 / 21.2）：已选计数 + 全选 + 明确的退出入口。
  /// 整体替换常驻顶栏，且不区分子页签形态——两种形态同一套交互（REQ-23.4）。
  PreferredSizeWidget _selectionBar({
    required bool isTemplates,
    required List<JournalTemplate> templates,
    required List<CustomSticker> stickers,
  }) {
    final selectedIds = isTemplates ? _selectedTemplateIds : _selectedStickerIds;
    final total = isTemplates ? templates.length : stickers.length;
    final unit = isTemplates ? '套' : '张';
    final allSelected = total > 0 && selectedIds.length == total;

    return AppBar(
      leading: IconButton(
        tooltip: '退出多选',
        icon: const Icon(Icons.close_rounded),
        onPressed: isTemplates ? _exitTemplateSelection : _exitStickerSelection,
      ),
      title: Text('已选 ${selectedIds.length} $unit'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            selectedIds.clear();
            if (!allSelected) {
              selectedIds.addAll(
                isTemplates
                    ? templates.map((t) => t.id)
                    : stickers.map((s) => s.id),
              );
            }
          }),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        IconButton(
          tooltip: '导出为素材包',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: selectedIds.isEmpty
              ? null
              : () => isTemplates
              ? _exportTemplates([
                  for (final t in templates)
                    if (selectedIds.contains(t.id)) t,
                ])
              : _exportStickers([
                  for (final s in stickers)
                    if (selectedIds.contains(s.id)) s,
                ], const <JournalTemplate>[], null),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// 模板管理整页形态（REQ-23.5）：素材包导入回跳（`main.dart`）以整页打开。
/// 壳与「素材」一级入口共用 [LibraryPage]，只是不带子页签栏，
/// 高亮定位等行为与子页签形态完全一致（REQ-23.6）。
class TemplateManagerPage extends StatelessWidget {
  const TemplateManagerPage({super.key, this.highlightIds = const []});

  /// 刚从分享包装进来的模板 id，卡片上做高亮标记（REQ-21.9）。
  final List<String> highlightIds;

  @override
  Widget build(BuildContext context) {
    return LibraryPage(
      initialTab: LibraryTab.templates,
      showTabs: false,
      templateHighlightIds: highlightIds,
    );
  }
}

/// 素材管理整页形态（REQ-23.5）：编辑器贴纸面板的「管理」（`canvas_tool_sheets`）
/// 与素材包导入回跳（`main.dart`）以整页打开，行为与子页签形态完全一致。
class StickerManagerPage extends StatelessWidget {
  const StickerManagerPage({super.key, this.highlightStickerIds = const []});

  /// 刚从分享包装进来的素材 sha1，进页后高亮并滚到第一个（REQ-21.9）。
  final List<String> highlightStickerIds;

  @override
  Widget build(BuildContext context) {
    return LibraryPage(
      initialTab: LibraryTab.stickers,
      showTabs: false,
      stickerHighlightIds: highlightStickerIds,
    );
  }
}
