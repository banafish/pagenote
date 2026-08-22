import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../widgets/pack_cover.dart';
import 'pack_detail_page.dart';

/// 包卡片网格的目标宽度与比例（封面 + 包名 + 计数 + 署名）。
const _cardExtent = 170.0;
const _cardRatio = 0.92;
const _cardSpacing = 12.0;
const _gridPadding = 16.0;

/// 素材首页（REQ-26）：从「模板 / 贴纸」两个子页签重构为包列表——
/// 置顶「内置模板」「未分组」两个固定内容入口，下方为「我的素材包」。
///
/// 包优先 ≠ 只有包（判断三）：固定入口背后永远有实际内容——内置模板恒非空，
/// 未分组对没导过包的用户就是全部家当，首屏永不为空（延续 REQ-23.2）。
/// 点固定入口或包卡片进入 [PackDetailPage]（三处同一个详情页组件）。
/// 列表页不做跨包多选——跨包分发用「逐包整包导出」替代（REQ-26.7）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  // ---------------- 新建素材包（REQ-26.6） ----------------

  /// 命名后直接进入空包详情页——空包不再只能靠「移动贴纸到包」间接创建。
  Future<void> _createPack() async {
    final provider = context.read<CustomStickerProvider>();
    final name = await _promptPackName();
    if (name == null || !mounted) return;
    final pack = await provider.createPack(name);
    if (pack == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PackDetailPage.pack(pack.id)),
    );
  }

  Future<String?> _promptPackName() async {
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

  // ---------------- 包手动排序（REQ-26.5） ----------------

  /// 长按拖拽落位：按新顺序重编 sortIndex 并落库；
  /// 存量包的初始顺序由 v9 迁移定为 createdAt 倒序。
  Future<void> _reorderPacks(List<StickerPack> packs, int from, int to) async {
    final ids = packs.map((p) => p.id).toList();
    final moved = ids.removeAt(from);
    ids.insert(to.clamp(0, ids.length), moved);
    await context.read<CustomStickerProvider>().reorderPacks(ids);
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    final stickerProvider = context.watch<CustomStickerProvider>();
    final templateProvider = context.watch<TemplateProvider>();
    final packs = stickerProvider.packs;
    final builtinCount = templateProvider.builtinTemplates.length;
    final ungroupedStickers = stickerProvider.ungroupedStickers.length;
    final ungroupedTemplates = [
      for (final t in templateProvider.templates)
        if (!t.builtin && t.packId == null) t,
    ].length;
    // 只有一个包时拖拽没有意义，直接渲染普通卡片。
    final draggable = packs.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('素材'),
        actions: [
          IconButton(
            tooltip: '新建素材包',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createPack,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _fixedEntries(
            builtinCount: builtinCount,
            ungroupedStickers: ungroupedStickers,
            ungroupedTemplates: ungroupedTemplates,
          )),
          SliverToBoxAdapter(child: _packsHeader(packs.length)),
          if (packs.isEmpty)
            SliverToBoxAdapter(child: _emptyPacksGuide())
          else
            _packGrid(packs, stickerProvider, templateProvider, draggable),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  /// 置顶固定内容入口（REQ-26.1）：内置模板永远存在，首屏永不为空。
  Widget _fixedEntries({
    required int builtinCount,
    required int ungroupedStickers,
    required int ungroupedTemplates,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding, 10, _gridPadding, 4),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _fixedEntry(
              icon: Icons.description_outlined,
              title: '内置模板',
              subtitle: '$builtinCount 套 · 复制后可自由修改',
              onTap: () => _openDetail(const PackDetailPage.builtin()),
            ),
            Divider(height: 1, indent: 62, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _fixedEntry(
              icon: Icons.photo_library_outlined,
              title: '未分组',
              subtitle: '$ungroupedStickers 张贴纸 · $ungroupedTemplates 套模板',
              onTap: () => _openDetail(const PackDetailPage.ungrouped()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixedEntry({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  void _openDetail(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _packsHeader(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _gridPadding + 4,
        16,
        _gridPadding,
        10,
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_rounded,
            size: 15,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          const Text(
            '我的素材包',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '长按可拖动排序 · 共 $count 个',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 空态引导（REQ-26.8）：导入素材包指路设置页（延续 REQ-25.2
  /// 「文件动作属于设置」的划分），并引导把散装贴纸挪进包。
  Widget _emptyPacksGuide() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 34,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有素材包',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '朋友分享的素材包 zip 在「设置 → 导入素材包」装进来；\n'
              '也可以新建一个包，把「未分组」里的散装贴纸挪进去整理。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _createPack,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('新建素材包'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _packGrid(
    List<StickerPack> packs,
    CustomStickerProvider stickerProvider,
    TemplateProvider templateProvider,
    bool draggable,
  ) {
    final cell = _cellSize(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _cardExtent,
          mainAxisSpacing: _cardSpacing,
          crossAxisSpacing: _cardSpacing,
          childAspectRatio: _cardRatio,
        ),
        itemCount: packs.length,
        itemBuilder: (context, i) {
          final pack = packs[i];
          final card = _packCard(
            pack,
            stickers: stickerProvider.stickersOfPack(pack.id).length,
            templates: templateProvider.templatesOfPack(pack.id).length,
          );
          if (!draggable) return card;
          return _draggableCard(packs, i, cell, card);
        },
      ),
    );
  }

  /// 包卡片（REQ-26.1）：封面或占位、包名、n 贴纸 · n 模板、作者署名。
  Widget _packCard(StickerPack pack, {required int stickers, required int templates}) {
    final scheme = Theme.of(context).colorScheme;
    final author = pack.author.trim();
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => _openDetail(PackDetailPage.pack(pack.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: PackCoverImage(pack: pack)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$stickers 贴 · $templates 模',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
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

  /// 手动排序的可拖拽单元（REQ-26.5，与未分组模板拖排同一套手势）。
  Widget _draggableCard(
    List<StickerPack> packs,
    int index,
    Size cell,
    Widget card,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) =>
          _reorderPacks(packs, details.data, index),
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
            borderRadius: BorderRadius.circular(16),
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

  /// 拖拽悬浮卡的尺寸：与网格实际算法保持一致。
  Size _cellSize(BuildContext context) {
    final avail = MediaQuery.sizeOf(context).width - _gridPadding * 2;
    final columns = (avail / _cardExtent).ceil().clamp(1, 8);
    final width = (avail - _cardSpacing * (columns - 1)) / columns;
    return Size(width, width / _cardRatio);
  }
}
