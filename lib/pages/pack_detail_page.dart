import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/journal_provider.dart';
import '../providers/template_provider.dart';
import '../utils/pack_cover_store.dart';
import '../utils/sticker_store.dart';
import '../widgets/canvas/canvas_view.dart';
import '../widgets/pack_cover.dart';
import '../widgets/sticker_pack_sheet.dart';
import 'editor_page.dart';
import 'pack_actions.dart';

/// 缩略图用的预览条目：组件元素（日期/心情等）从它读取展示数据。
final _previewEntry = JournalEntry(
  id: 'pack-detail-preview',
  date: '2026-08-22',
  title: '',
  content: '',
  mood: Mood.calm,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// 贴纸格子的目标宽度与比例（图 + 一行名字），窄屏自动减列。
const _stickerExtent = 110.0;
const _stickerRatio = 0.80;

/// 模板格子的目标宽度与比例（缩略图 + 底部名字栏）。
const _templateExtent = 200.0;
const _templateRatio = 0.62;

const _cellSpacing = 12.0;
const _gridPadding = 16.0;

/// 新导入内容的高亮时长（REQ-21.9）：呼吸描边亮一小会儿即回落。
const _highlightDuration = Duration(seconds: 4);

/// 详情页的数据源（REQ-26.2）：内置模板、未分组与各素材包三处
/// 使用同一个页面组件、不同数据源。
enum PackDetailSource {
  /// 内置模板：只读网格 + 复制为我的模板（现状行为）。
  builtin,

  /// 未分组：`packId` 为 null 的贴纸（保留 category 分节）
  /// + 自建模板（继承三档排序与长按拖排）。
  ungrouped,

  /// 指定包：该包的贴纸网格 + 模板网格。
  pack,
}

/// 素材详情页（REQ-26）：素材首页「内置模板 / 未分组 / 各素材包」三处
/// 固定入口与包卡片的统一落点，同屏浏览贴纸与模板。
///
/// 由 [TemplateManagerBody] / [StickerManagerBody] 合并而来——包级操作
/// 上移到本页（重命名 / 封面 / 整包导出 / 解散 / 删除），多选态随之下沉
/// （REQ-26.3 / 26.7），不再由宿主页跨内容上提。
/// 页面可独立 push：素材首页、导入回跳（直达包详情并高亮）与
/// 编辑器「管理我的素材」都以整页打开（REQ-26.4 / 26.9）。
class PackDetailPage extends StatefulWidget {
  const PackDetailPage.builtin({super.key})
    : source = PackDetailSource.builtin,
      packId = null,
      highlightTemplateIds = const [],
      highlightStickerIds = const [];

  const PackDetailPage.ungrouped({
    super.key,
    this.highlightTemplateIds = const [],
    this.highlightStickerIds = const [],
  }) : source = PackDetailSource.ungrouped,
       packId = null;

  const PackDetailPage.pack(
    this.packId, {
    super.key,
    this.highlightTemplateIds = const [],
    this.highlightStickerIds = const [],
  }) : source = PackDetailSource.pack;

  final PackDetailSource source;

  /// [PackDetailSource.pack] 时的目标包 id。
  final String? packId;

  /// 刚从分享包装进来的模板 id（REQ-26.4 回跳高亮）。
  final List<String> highlightTemplateIds;

  /// 刚从分享包装进来的素材 sha1（REQ-26.4 回跳高亮）。
  final List<String> highlightStickerIds;

  @override
  State<PackDetailPage> createState() => _PackDetailPageState();
}

class _PackDetailPageState extends State<PackDetailPage>
    with SingleTickerProviderStateMixin {
  // ---------------- 多选（REQ-26.7：状态随详情页，不再上提宿主） ----------------

  bool _selecting = false;
  final Set<String> _selectedTemplateIds = {};
  final Set<String> _selectedStickerIds = {};

  // ---------------- 新导入高亮（REQ-21.9 / REQ-26.4） ----------------

  /// 仍在高亮中的素材 id；到点清空，卡片随即回到常态。
  final Set<String> _highlightStickerIds = {};

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
    if (widget.highlightStickerIds.isNotEmpty) {
      _highlightStickerIds.addAll(widget.highlightStickerIds);
      for (final id in _highlightStickerIds) {
        _highlightKeys[id] = GlobalKey();
      }
      _pulse.repeat(reverse: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlight();
        _scheduleHighlightFade();
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 滚到第一个新导入的素材（REQ-21.9）。懒加载的网格首帧未必建到目标格子，
  /// 拿不到 context 时退几帧再试，仍拿不到就放弃滚动，只保留描边。
  void _scrollToHighlight([int attempt = 0]) {
    if (!mounted || _highlightStickerIds.isEmpty) return;
    final provider = context.read<CustomStickerProvider>();
    final ordered = [
      for (final sticker in _visibleStickers(provider))
        if (_highlightStickerIds.contains(sticker.id)) sticker,
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
      setState(_highlightStickerIds.clear);
    });
  }

  // ---------------- 数据源 ----------------

  /// 当前详情页的贴纸（未分组详情保留插入序，包详情按包过滤）。
  List<CustomSticker> _visibleStickers(CustomStickerProvider provider) {
    return switch (widget.source) {
      PackDetailSource.builtin => const [],
      PackDetailSource.ungrouped => provider.ungroupedStickers,
      PackDetailSource.pack => provider.stickersOfPack(widget.packId!),
    };
  }

  /// 当前详情页的模板。
  List<JournalTemplate> _visibleTemplates(TemplateProvider provider) {
    return switch (widget.source) {
      PackDetailSource.builtin => provider.builtinTemplates,
      PackDetailSource.ungrouped => [
        for (final t in provider.templates)
          if (!t.builtin && t.packId == null) t,
      ],
      PackDetailSource.pack => provider.templatesOfPack(widget.packId!),
    };
  }

  /// 按分组切段（未分组贴纸沿用 category 语义，与素材面板「我的」页签一致）。
  List<({String label, List<CustomSticker> items})> _stickerSections(
    CustomStickerProvider provider,
  ) {
    return switch (widget.source) {
      PackDetailSource.builtin => const [],
      PackDetailSource.ungrouped => () {
        final all = provider.ungroupedStickers;
        final names = all.map((s) => s.category).toSet().toList()..sort();
        return [
          for (final name in names)
            (
              label: name,
              items: [
                for (final sticker in all)
                  if (sticker.category == name) sticker,
              ],
            ),
        ];
      }(),
      PackDetailSource.pack => [
        (label: '贴纸', items: provider.stickersOfPack(widget.packId!)),
      ],
    };
  }

  // ---------------- 模板手动排序（REQ-18.4） ----------------

  /// 拖拽落位：整体重排这批模板并持久化（REQ-18.4）。
  /// 只传当前详情页可见的 id——重编号只影响这一节，其余模板的原顺序不动。
  Future<void> _reorder(List<JournalTemplate> users, int from, int to) async {
    final ids = users.map((t) => t.id).toList();
    final moved = ids.removeAt(from);
    ids.insert(to.clamp(0, ids.length), moved);
    await context.read<TemplateProvider>().reorderUserTemplates(ids);
  }

  // ---------------- 单个贴纸的操作（REQ-20.4，与现状一致） ----------------

  /// 贴纸操作菜单：重命名 / 移动到素材包 / 分组 / 导出 / 删除。
  Future<void> _stickerMenu(CustomSticker sticker) async {
    final provider = context.read<CustomStickerProvider>();
    final packName = provider.packById(sticker.packId ?? '')?.name;
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
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('移动到素材包'),
              subtitle: Text(packName ?? '未分组'),
              onTap: () => Navigator.pop(menuContext, 'pack'),
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
      case 'pack':
        if (mounted) await moveStickerToPackFlow(context, sticker);
      case 'category':
        final group = await _promptText('素材分组', '分组名称', sticker.category);
        if (!mounted || group == null) return;
        await context.read<CustomStickerProvider>().setCategory(
          sticker.id,
          group,
        );
      case 'export':
        if (context.mounted) {
          await exportStickersAsPack(context, [sticker], const [], null);
        }
      case 'delete':
        await _deleteSticker(sticker);
    }
  }

  /// 删除贴纸；被手账或模板引用时先说明后果再确认（REQ-20.4）。
  Future<void> _deleteSticker(CustomSticker sticker) async {
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
    setState(() => _selectedStickerIds.remove(sticker.id));
  }

  // ---------------- 单个模板的操作（与现状一致） ----------------

  Future<void> _onTemplateAction(String action, JournalTemplate template) async {
    switch (action) {
      case 'edit':
        await _editTemplate(template);
      case 'rename':
        await _renameTemplate(template);
      case 'duplicate':
        await _duplicateTemplate(template);
      case 'export':
        if (context.mounted) {
          await exportTemplatesAsPack(context, [template]);
        }
      case 'delete':
        await _deleteTemplate(template);
    }
  }

  /// 模板区标题右侧的「新增」：先起名，再进编辑器从零搭版式；
  /// 保存后落在当前包 / 未分组（编辑器模板模式对未入库模板就地落库），
  /// 中途退出则什么都不留。
  Future<void> _addTemplate() async {
    // 默认名撞车时自动带序号，避免攒出一排「新模板」。
    final taken = context
        .read<TemplateProvider>()
        .templates
        .map((t) => t.name)
        .toSet();
    var initial = '新模板';
    for (var i = 2; taken.contains(initial); i++) {
      initial = '新模板 $i';
    }
    final name = await _promptText('新建模板', '模板名称', initial);
    if (!mounted || name == null) return;
    final template = JournalTemplate(
      id: newTemplateId(),
      name: name,
      packId: widget.source == PackDetailSource.pack ? widget.packId : null,
    );
    final saved =
        await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => EditorPage(editingTemplate: template),
          ),
        ) ??
        false;
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建模板「$name」✨')),
      );
    }
  }

  /// 编辑模板整页版式（就地更新）：复用手账编辑器，保存回写该模板本身。
  /// 网格刷新由 TemplateProvider.saveTemplate 的 notifyListeners 驱动。
  Future<void> _editTemplate(JournalTemplate template) async {
    final saved =
        await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => EditorPage(editingTemplate: template),
          ),
        ) ??
        false;
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已更新模板「${template.name}」✨')),
      );
    }
  }

  Future<void> _renameTemplate(JournalTemplate template) async {
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
    if (trimmed.isEmpty || !mounted) return;
    template.name = trimmed;
    await context.read<TemplateProvider>().saveTemplate(template);
  }

  /// 复制一份（REQ-18.2）；内置模板走同一入口，副本可自由改名编辑（REQ-18.3）。
  Future<void> _duplicateTemplate(JournalTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = await context.read<TemplateProvider>().duplicateTemplate(
      template,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已复制为「${copy.name}」，在「未分组」里可找到 ✨')));
  }

  Future<void> _deleteTemplate(JournalTemplate template) async {
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
    if (ok == true && mounted) {
      await context.read<TemplateProvider>().deleteTemplate(template.id);
    }
  }

  /// 点卡片看大图：网格缩略图偏小，放大后能确认版式细节。
  void _previewTemplate(JournalTemplate template) {
    final scheme = Theme.of(context).colorScheme;
    final canvas = template.canvas;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  template.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: canvas == null
                      ? Text(
                          template.content.trim().isEmpty
                              ? '这是一份纯文本模板，套用后直接开写。'
                              : template.content.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 1 / canvas.effectiveHeight,
                            child: CanvasView(
                              canvas: canvas,
                              entry: _previewEntry,
                            ),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 包级操作（REQ-26.3 + REQ-27.2，上移到详情页） ----------------

  /// 包操作菜单：重命名 / 封面 / 导出整包 / 解散 / 删除。
  Future<void> _packMenu(StickerPack pack) async {
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
                    style: Theme.of(menuContext)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
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
                subtitle: const Text('素材保留，移入未分组'),
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
    if (!mounted || action == null) return;
    final provider = context.read<CustomStickerProvider>();
    final templates = context.read<TemplateProvider>();
    switch (action) {
      case 'rename':
        final name = await _promptText('重命名素材包', '包名称', pack.name);
        if (!mounted || name == null) return;
        await provider.renamePack(pack.id, name);
      case 'cover':
        await _changeCover(pack);
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
        // 否则会挂着已删除的包 id。包没了，本页随之出栈。
        await provider.dissolvePack(pack.id);
        await templates.detachPack(pack.id);
        if (mounted) Navigator.of(context).pop();
      case 'delete':
        await _deletePack(pack);
    }
  }

  /// 上传 / 更换封面（REQ-27.2 / 27.4）：从相册选一张，
  /// 超限自动压缩并提示。
  Future<void> _changeCover(StickerPack pack) async {
    final provider = context.read<CustomStickerProvider>();
    final files = await StickerStore.pickImages();
    if (!mounted || files.isEmpty) return;
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
    if (!mounted) return;
    // 如实提示压缩结果（REQ-27.4，对齐 REQ-20.5 的贴纸约束）。
    final before = await pixelSize(bytes);
    final oversize =
        bytes.length > PackCoverStore.maxBytes ||
        (before != null && before.longestSide > PackCoverStore.maxEdge);
    if (oversize) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('封面超出上限，已自动压缩到 1024 像素内')),
        );
    }
  }

  /// 删除包与包内全部素材；有素材被手账或模板引用时先说明后果再确认。
  /// 包内模板不跟随删除——移回未分组保留（v8）。
  Future<void> _deletePack(StickerPack pack) async {
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
        : '\n包内 ${packTemplates.length} 套模板会保留，移回未分组。';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除素材包？'),
        content: Text(
          referenced > 0
              ? '「${pack.name}」共 ${items.length} 张素材，其中 $referenced 张正被手账或模板使用，'
                    '删除后那些位置会显示缺失占位。$templateNote'
              : '「${pack.name}」与包内 ${items.length} 张素材将被移除。$templateNote\n'
                    '只想去掉分组的话，用「解散素材包」可以保留素材。',
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
    await provider.deletePack(pack.id);
    // 模板保留，只解除对已删包的归属。
    await templates.detachPack(pack.id);
    if (!mounted) return;
    setState(() {
      _selectedStickerIds.removeWhere((id) => provider.byId(id) == null);
    });
    Navigator.of(context).pop();
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
    // 对话框退出动画期间 TextField 仍依赖 controller，延后释放。
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---------------- 多选导出（REQ-26.7） ----------------

  void _exitSelection() => setState(() {
    _selecting = false;
    _selectedTemplateIds.clear();
    _selectedStickerIds.clear();
  });

  Future<void> _exportSelection({
    required List<JournalTemplate> templates,
    required List<CustomSticker> stickers,
    required StickerPack? pack,
  }) async {
    if (templates.isEmpty && stickers.isEmpty) return;
    if (pack != null || stickers.isNotEmpty) {
      // 混选 / 含素材：走素材导出（带上包身份时即整包语义）。
      await exportStickersAsPack(context, stickers, templates, pack);
    } else {
      await exportTemplatesAsPack(context, templates);
    }
    if (mounted && _selecting) _exitSelection();
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    final stickerProvider = context.watch<CustomStickerProvider>();
    final templateProvider = context.watch<TemplateProvider>();
    final pack = widget.source == PackDetailSource.pack
        ? stickerProvider.packById(widget.packId!)
        : null;
    // 包在详情页打开期间被解散 / 删除（本页或别处操作）：直接出栈回首页。
    if (widget.source == PackDetailSource.pack && pack == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stickers = _visibleStickers(stickerProvider);
    final templates = _visibleTemplates(templateProvider);
    final sections = _stickerSections(stickerProvider);
    // 未分组模板的长按拖排迁移至此（REQ-26.2 / REQ-18.4）；
    // 多选态下让出长按手势，两者不同时生效。
    final draggable =
        widget.source == PackDetailSource.ungrouped &&
        !_selecting &&
        templates.length > 1;
    // 导入贴纸的落位：包详情直接进包，未分组落在默认分组。
    final importPackId = widget.source == PackDetailSource.pack
        ? widget.packId
        : null;
    // 内置模板只读，不提供新增入口；多选态是挑内容导出的模式，也让出 ＋。
    final canAdd = widget.source != PackDetailSource.builtin && !_selecting;

    return Scaffold(
      appBar: _selecting
          ? _selectionBar(templates: templates, stickers: stickers, pack: pack)
          : AppBar(
              title: Text(switch (widget.source) {
                PackDetailSource.builtin => '内置模板',
                PackDetailSource.ungrouped => '未分组',
                PackDetailSource.pack => pack!.name,
              }),
              actions: [
                IconButton(
                  tooltip: '多选导出',
                  icon: const Icon(Icons.checklist_rounded),
                  onPressed: templates.isEmpty && stickers.isEmpty
                      ? null
                      : () => setState(() => _selecting = true),
                ),
                if (widget.source == PackDetailSource.pack)
                  IconButton(
                    tooltip: '素材包操作',
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _packMenu(pack!),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      body: (stickers.isEmpty && templates.isEmpty)
          ? _emptyGuide()
          : CustomScrollView(
              slivers: [
                if (widget.source == PackDetailSource.pack)
                  SliverToBoxAdapter(child: _packHeader(pack!)),
                SliverToBoxAdapter(child: _hintBar()),
                for (final section in sections) ...[
                  _sectionLabel(
                    section.label,
                    '共 ${section.items.length} 张',
                    addTooltip: '导入贴纸',
                    onAdd: canAdd
                        ? () => importStickersFromGallery(
                            context,
                            packId: importPackId,
                            // 未分组按分节导入：加进点开的那个分组；
                            // 包内不细分组，落默认分组。
                            category: widget.source == PackDetailSource.pack
                                ? null
                                : section.label,
                          )
                        : null,
                  ),
                  _stickerGrid(section.items),
                ],
                if (stickers.isEmpty &&
                    widget.source != PackDetailSource.builtin) ...[
                  _sectionLabel(
                    '贴纸',
                    null,
                    addTooltip: '导入贴纸',
                    onAdd: canAdd
                        ? () => importStickersFromGallery(
                            context,
                            packId: importPackId,
                          )
                        : null,
                  ),
                  SliverToBoxAdapter(child: _noStickerHint()),
                ],
                _sectionLabel(
                  widget.source == PackDetailSource.builtin ? '内置模板' : '模板',
                  templates.isEmpty ? null : '共 ${templates.length} 套',
                  addTooltip: '新建模板',
                  onAdd: canAdd ? _addTemplate : null,
                ),
                if (templates.isNotEmpty)
                  _templateGrid(
                    templates: templates,
                    draggable: draggable,
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
    );
  }

  /// 包信息区（REQ-26.3 / REQ-27.2）：封面 + 名称 + 署名 + 计数；
  /// 点封面直接换封面（上传 / 更换入口），其余操作在右上角菜单。
  Widget _packHeader(StickerPack pack) {
    final scheme = Theme.of(context).colorScheme;
    final stickerProvider = context.read<CustomStickerProvider>();
    final templateProvider = context.read<TemplateProvider>();
    final stickerCount = stickerProvider.stickersOfPack(pack.id).length;
    final templateCount = templateProvider.templatesOfPack(pack.id).length;
    final author = pack.author.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding, 12, _gridPadding, 2),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _changeCover(pack),
              child: Stack(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: PackCoverImage(pack: pack),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 12,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '来自 $author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    '$stickerCount 张贴纸 · $templateCount 套模板',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding + 4, 12, _gridPadding, 2),
      child: Text(
        _selecting
            ? '点内容勾选（贴纸与模板可混选），选好后点右上角导出'
            : switch (widget.source) {
                PackDetailSource.builtin => '点模板可预览；复制为我的模板后可自由修改',
                PackDetailSource.ungrouped => '点贴纸可重命名 / 移动到素材包 / 删除，长按进入多选',
                PackDetailSource.pack => '点贴纸可重命名 / 移动 / 删除，长按进入多选',
              },
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  /// 分节标题：名字 + 计数，[onAdd] 非空时右侧挂一个新增入口
  /// （贴纸导入 / 新建模板），对齐到文字行垂直居中。
  Widget _sectionLabel(String text, String? hint, {String? addTooltip, VoidCallback? onAdd}) {
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
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    text,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  if (hint != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hint,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onAdd != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: addTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(Icons.add_rounded, size: 19, color: scheme.primary),
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noStickerHint() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding, 4, _gridPadding, 6),
      child: Text(
        '还没有贴纸，点「贴纸」右侧的 ＋ 加进来',
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _stickerGrid(List<CustomSticker> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _stickerExtent,
          mainAxisSpacing: _cellSpacing,
          crossAxisSpacing: _cellSpacing,
          childAspectRatio: _stickerRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _stickerCell(items[i]),
      ),
    );
  }

  /// 高亮素材做呼吸描边（REQ-21.9），其余格子不订阅动画，避免整页重建。
  Widget _stickerCell(CustomSticker sticker) {
    if (!_highlightStickerIds.contains(sticker.id)) {
      return _stickerCellBody(sticker, glow: 0);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => _stickerCellBody(sticker, glow: _pulse.value),
    );
  }

  Widget _stickerCellBody(CustomSticker sticker, {required double glow}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedStickerIds.contains(sticker.id);
    final highlighted = _highlightStickerIds.contains(sticker.id);
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
      // 波纹画在上层 Material 上，Container 的 clip 管不到，
      // 需用 customBorder 让水波纹贴合格子圆角。
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        onTap: () {
          if (_selecting) {
            setState(() {
              if (!_selectedStickerIds.remove(sticker.id)) {
                _selectedStickerIds.add(sticker.id);
              }
            });
          } else {
            _stickerMenu(sticker);
          }
        },
        onLongPress: _selecting
            ? null
            : () => setState(() {
              _selecting = true;
              _selectedStickerIds.add(sticker.id);
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

  /// 懒渲染模板网格（REQ-18.6）：只构建可视范围内的缩略图；
  /// 手动排序模式下包一层拖拽单元。
  Widget _templateGrid({
    required List<JournalTemplate> templates,
    required bool draggable,
  }) {
    final cell = _cellSize(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _templateExtent,
          mainAxisSpacing: _cellSpacing,
          crossAxisSpacing: _cellSpacing,
          childAspectRatio: _templateRatio,
        ),
        itemCount: templates.length,
        itemBuilder: (context, i) => draggable
            ? _draggableCell(templates, i, cell)
            : _templateCard(templates[i]),
      ),
    );
  }

  Widget _templateCard(JournalTemplate template) => _TemplateCard(
    template: template,
    selecting: _selecting,
    selected: _selectedTemplateIds.contains(template.id),
    highlighted: widget.highlightTemplateIds.contains(template.id),
    onTap: () {
      if (_selecting) {
        setState(() {
          if (!_selectedTemplateIds.remove(template.id)) {
            _selectedTemplateIds.add(template.id);
          }
        });
      } else {
        _previewTemplate(template);
      }
    },
    onAction: (action) => _onTemplateAction(action, template),
  );

  /// 手动模式的可拖拽单元（REQ-18.4）。
  Widget _draggableCell(List<JournalTemplate> templates, int index, Size cell) {
    final scheme = Theme.of(context).colorScheme;
    final card = _templateCard(templates[index]);
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) =>
          _reorder(templates, details.data, index),
      builder: (context, candidate, _) => LongPressDraggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: cell.width,
            height: cell.height,
            child: Opacity(opacity: 0.92, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: card),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: candidate.isEmpty ? Colors.transparent : scheme.primary,
              width: 2,
            ),
          ),
          child: card,
        ),
      ),
    );
  }

  /// 多选态顶栏（REQ-21.1 / 21.2 / 26.7）：已选计数（模板与贴纸分计）
  /// + 全选 + 明确的退出入口；导出走混选素材包。
  PreferredSizeWidget _selectionBar({
    required List<JournalTemplate> templates,
    required List<CustomSticker> stickers,
    required StickerPack? pack,
  }) {
    final total = templates.length + stickers.length;
    final allSelected =
        total > 0 &&
        _selectedTemplateIds.length + _selectedStickerIds.length == total;
    final parts = [
      if (_selectedTemplateIds.isNotEmpty) '${_selectedTemplateIds.length} 套模板',
      if (_selectedStickerIds.isNotEmpty) '${_selectedStickerIds.length} 张贴纸',
    ];
    return AppBar(
      leading: IconButton(
        tooltip: '退出多选',
        icon: const Icon(Icons.close_rounded),
        onPressed: _exitSelection,
      ),
      title: Text(parts.isEmpty ? '未选择内容' : '已选 ${parts.join(' · ')}'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _selectedTemplateIds.clear();
            _selectedStickerIds.clear();
            if (!allSelected) {
              _selectedTemplateIds.addAll(templates.map((t) => t.id));
              _selectedStickerIds.addAll(stickers.map((s) => s.id));
            }
          }),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        IconButton(
          tooltip: '导出为素材包',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: _selectedTemplateIds.isEmpty && _selectedStickerIds.isEmpty
              ? null
              : () => _exportSelection(
                  templates: [
                    for (final t in templates)
                      if (_selectedTemplateIds.contains(t.id)) t,
                  ],
                  stickers: [
                    for (final s in stickers)
                      if (_selectedStickerIds.contains(s.id)) s,
                  ],
                  pack: pack,
                ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// 空态引导：按数据源说明这里能放什么、怎么放。
  Widget _emptyGuide() {
    final scheme = Theme.of(context).colorScheme;
    final (title, body) = switch (widget.source) {
      PackDetailSource.builtin => ('内置模板', '内置模板每台设备都有，复制为我的模板后可自由修改。'),
      PackDetailSource.ungrouped => (
        '散装素材都住这里',
        '从相册导入的贴纸与自建模板默认放在未分组，\n整理进素材包后可在首页按包浏览。',
      ),
      PackDetailSource.pack => (
        '这个包还是空的',
        '点「导入图片」加贴纸，「新建模板」搭一个版式，\n或把现有素材「移动到素材包」挪进来。',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (widget.source) {
                PackDetailSource.builtin => Icons.description_outlined,
                PackDetailSource.ungrouped => Icons.photo_library_outlined,
                PackDetailSource.pack => Icons.inventory_2_outlined,
              },
              size: 38,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            // 整页空态没有分节标题可挂 ＋，两个新增入口都放这里。
            if (widget.source != PackDetailSource.builtin)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => importStickersFromGallery(
                      context,
                      packId: widget.source == PackDetailSource.pack
                          ? widget.packId
                          : null,
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('导入图片'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: _addTemplate,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建模板'),
                  ),
                ],
              )
            else
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EditorPage(isNew: true),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('去写一篇'),
              ),
          ],
        ),
      ),
    );
  }

  /// 拖拽悬浮卡的尺寸：与网格实际算法保持一致。
  Size _cellSize(BuildContext context) {
    final avail = MediaQuery.sizeOf(context).width - _gridPadding * 2;
    final columns = (avail / _templateExtent).ceil().clamp(1, 8);
    final width = (avail - _cellSpacing * (columns - 1)) / columns;
    return Size(width, width / _templateRatio);
  }
}

/// 模板卡片（REQ-18.1）：版式缩略图 + 名字 + 更多菜单；
/// 多选态下改为勾选（REQ-21.1），新导入的模板带高亮标记（REQ-21.9）。
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selecting,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    required this.onAction,
  });

  final JournalTemplate template;
  final bool selecting;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected
        ? scheme.primary
        : (highlighted ? scheme.tertiary : null);
    // 描边走 foregroundDecoration 画在内容之上：缩略图 cover 铺满后
    // 仍能完整露出顶部圆角线，不会被预览图盖住。
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent ?? scheme.outlineVariant.withValues(alpha: 0.5),
          width: accent == null ? 1 : 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // 波纹画在上层 Material 上，Container 的 clip 管不到，
      // 需用 customBorder 让水波纹贴合卡片圆角。
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _thumbnail(context)),
                  if (template.builtin)
                    Positioned(left: 6, top: 6, child: _badge(context, '内置'))
                  else if (highlighted)
                    Positioned(left: 6, top: 6, child: _badge(context, '新导入')),
                  if (selecting)
                    Positioned(right: 6, top: 6, child: _checkMark(context)),
                ],
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  /// 整页版式缩略图，与模板选择弹层同一套渲染（所见即所得）；
  /// 单独隔离重绘，长列表滚动不拖累其他卡片（REQ-18.6）。
  Widget _thumbnail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canvas = template.canvas;
    if (canvas == null) {
      return Container(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 26,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              '纯文本模板',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    // cover 铺满缩略图区，顶部对齐：纸面顶到卡边后由卡片圆角统一裁型。
    return RepaintBoundary(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 240,
          child: AspectRatio(
            aspectRatio: 1 / canvas.effectiveHeight,
            child: CanvasView(canvas: canvas, entry: _previewEntry),
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }

  /// 多选态的勾选标记（REQ-21.1）。
  Widget _checkMark(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary
            : scheme.surface.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
          : null,
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          // 内置模板的显式复制入口（REQ-18.3）；多选态下让位给勾选。
          if (selecting)
            const SizedBox(width: 8)
          else ...[
            if (template.builtin)
              IconButton(
                tooltip: '复制为我的模板',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  Icons.copy_all_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                onPressed: () => onAction('duplicate'),
              ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: Icon(
                Icons.more_vert_rounded,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              iconSize: 19,
              constraints: const BoxConstraints(minWidth: 168),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (context) => [
                // 内置模板只读（REQ-26），编辑只对我的模板开放。
                if (!template.builtin)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 19),
                        SizedBox(width: 10),
                        Text('编辑'),
                      ],
                    ),
                  ),
                if (!template.builtin)
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline_rounded, size: 19),
                        SizedBox(width: 10),
                        Text('重命名'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Row(
                    children: [
                      const Icon(Icons.copy_all_outlined, size: 19),
                      const SizedBox(width: 10),
                      Text(template.builtin ? '复制为我的模板' : '复制一份'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.ios_share_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('导出分享'),
                    ],
                  ),
                ),
                // 内置模板不可删（REQ-09.3），菜单里直接不出现。
                if (!template.builtin)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: Color(0xFFE57373),
                        ),
                        SizedBox(width: 10),
                        Text('删除', style: TextStyle(color: Color(0xFFE57373))),
                      ],
                    ),
                  ),
              ],
              onSelected: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// 新导入素材的角标（REQ-21.9）。
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
