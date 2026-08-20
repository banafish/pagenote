import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/journal_provider.dart';
import '../providers/template_provider.dart';
import '../utils/sticker_store.dart';

/// 素材格子的目标宽度与比例（图 + 一行名字），窄屏自动减列。
const _cellExtent = 110.0;
const _cellRatio = 0.80;
const _cellSpacing = 12.0;
const _gridPadding = 16.0;

/// 新导入素材的高亮时长（REQ-21.9）：呼吸描边亮一小会儿即回落，
/// 不做成常驻标记，否则下次进页面还带着「新」字反而误导。
const _highlightDuration = Duration(seconds: 4);

/// 我的素材管理的纯 body（REQ-20.4 + REQ-21.2 / 21.9，REQ-23 拆分）。
///
/// 素材面板的「我的」页签在编辑器底部弹层里，空间只够单个素材的角标菜单；
/// 打包导出要多选、导入后要跳转高亮，都得有一个能从根 Navigator push 的
/// 独立页面来承载——这个页面（[StickerManagerPage]）与「素材」一级入口的
/// 子页签共用本 body，顶栏（含多选态与导入按钮）由宿主 [LibraryPage] 统一渲染。
class StickerManagerBody extends StatefulWidget {
  const StickerManagerBody({
    super.key,
    required this.selecting,
    required this.selectedIds,
    this.highlightStickerIds = const [],
    required this.onToggleSelect,
    required this.onLongPressSelect,
    required this.onSelectionChanged,
    required this.onImport,
    required this.onExport,
  });

  /// 多选态（REQ-21.2）由宿主持有：点卡片勾选、长按进入都只是触发点。
  final bool selecting;

  /// 已勾选的素材 id，与宿主共享同一份集合。
  final Set<String> selectedIds;

  /// 刚从分享包装进来的素材 sha1，进页后高亮并滚到第一个（REQ-21.9）。
  final List<String> highlightStickerIds;

  /// 多选态下点素材：勾选 / 取消勾选。
  final ValueChanged<CustomSticker> onToggleSelect;

  /// 非多选态下长按素材：进入多选并带上这一张。
  final ValueChanged<CustomSticker> onLongPressSelect;

  /// 勾选集合被 body 侧改动（如删除了选中素材）时通知宿主刷新顶栏计数。
  final VoidCallback onSelectionChanged;

  /// 从相册导入图片作为贴纸（宿主顶栏与空态引导共用）。
  final Future<void> Function() onImport;

  /// 导出为素材包（REQ-21.2）：素材菜单的单个导出也走这里。
  final void Function(List<CustomSticker> targets) onExport;

  @override
  State<StickerManagerBody> createState() => _StickerManagerBodyState();
}

class _StickerManagerBodyState extends State<StickerManagerBody>
    with SingleTickerProviderStateMixin {
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
        widget.onExport([sticker]);
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
    // 对话框关闭还有 ~150ms 退出动画，TextField 仍在树中依赖 controller，
    // 立刻 dispose 会触发 _dependents.isEmpty 断言，等动画结束再释放。
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
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
    // 勾选集合由宿主持有，这里清掉被删项后请宿主刷新顶栏计数。
    if (widget.selectedIds.remove(sticker.id)) widget.onSelectionChanged();
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
    return stickers.isEmpty
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
          );
  }

  Widget _hintBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding + 4, 12, _gridPadding, 2),
      child: Text(
        widget.selecting
            ? '点素材勾选，选好后点右上角导出为素材包'
            : '点素材可重命名 / 分组 / 删除，长按进入多选',
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
              style: TextStyle(
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
    final selected = widget.selectedIds.contains(sticker.id);
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
          if (widget.selecting) {
            widget.onToggleSelect(sticker);
          } else {
            _stickerMenu(sticker);
          }
        },
        onLongPress: widget.selecting ? null : () => widget.onLongPressSelect(sticker),
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
            if (widget.selecting)
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
              onPressed: widget.onImport,
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
