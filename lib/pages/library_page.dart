import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../widgets/pack_cover.dart';
import 'pack_actions.dart';
import 'pack_detail_page.dart';
import 'share_pack_export_page.dart';
import 'share_pack_import_page.dart';

/// 包卡片网格的目标宽度与比例（封面 + 包名 + 计数 + 署名）。
const _cardExtent = 170.0;
const _cardRatio = 0.92;
const _cardSpacing = 12.0;
const _gridPadding = 16.0;

/// 素材首页（REQ-26）：从「模板 / 贴纸」两个子页签重构为包列表——
/// 置顶「内置模板」「我的素材」两个固定内容入口，下方为「我的素材包」。
///
/// 包优先 ≠ 只有包（判断三）：固定入口背后永远有实际内容——内置模板恒非空，
/// 我的素材（不在任何包里的贴纸与自建模板）对没导过包的用户就是全部家当，
/// 首屏永不为空（延续 REQ-23.2）。
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
    final name = await promptText(context, '新建素材包', '包名称', '');
    if (name == null || !mounted) return;
    final pack = await provider.createPack(name);
    if (pack == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PackDetailPage.pack(pack.id)),
    );
  }

  // ---------------- 素材包导入 / 导出（REQ-21.12，入口自设置页上移） ----------------

  /// Windows 双击关联之外的兜底入口，Android 也可用。
  /// 只负责取字节，勾选与校验都交给导入预览页（REQ-21.6），
  /// 不沿用备份那种「一个确认框全量导入」的交互。
  Future<void> _importSharePack() async {
    const zipGroup = XTypeGroup(label: '素材包', extensions: ['zip']);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final Uint8List bytes;
    final String source;
    try {
      final file = await openFile(acceptedTypeGroups: const [zipGroup]);
      if (file == null) return;
      bytes = await file.readAsBytes();
      source = file.name;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('读取素材包文件失败')));
      return;
    }
    final result = await navigator.push<SharePackImportResult>(
      MaterialPageRoute<SharePackImportResult>(
        builder: (_) => SharePackImportPage(bytes: bytes, sourceName: source),
      ),
    );
    if (result == null || result.isEmpty) return;

    final parts = [
      if (result.templateIds.isNotEmpty) '${result.templateIds.length} 套模板',
      if (result.stickerIds.isNotEmpty) '${result.stickerIds.length} 张贴纸',
    ];
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已导入 ${parts.join('、')}')));
    // 导入完成直达对应包详情页并高亮新增（REQ-26.4）：
    // 包有了自己的页面,回跳有了天然落点,不再连续 push 两个管理页。
    if (result.packId != null) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PackDetailPage.pack(
            result.packId!,
            highlightTemplateIds: result.templateIds,
            highlightStickerIds: result.stickerIds,
          ),
        ),
      );
    }
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
          // 导入 / 导出入口从设置页上移到素材首页，贴近内容更好找。
          // 图标取「进 / 出」一对：导入为箭头入框，与导出的箭头出框镜像。
          IconButton(
            tooltip: '导入素材包',
            icon: const Icon(Icons.input_outlined),
            onPressed: _importSharePack,
          ),
          IconButton(
            tooltip: '导出素材包',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _openDetail(const SharePackExportPage()),
          ),
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
          SliverToBoxAdapter(
            child: _fixedEntries(
              builtinCount: builtinCount,
              ungroupedStickers: ungroupedStickers,
              ungroupedTemplates: ungroupedTemplates,
            ),
          ),
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
            Divider(
              height: 1,
              indent: 62,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _fixedEntry(
              icon: Icons.photo_library_outlined,
              title: '我的素材',
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
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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

  /// 空态引导（REQ-26.8，入口上移后改版）：直接给「导入素材包」按钮
  /// （原指路设置页的文案随 REQ-25.2 划分调整一并作废），
  /// 并引导把散装贴纸挪进包。
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
              '朋友分享的素材包 zip 点下方按钮装进来；\n'
              '也可以新建一个包，把「我的素材」里的散装贴纸挪进去整理。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _importSharePack,
                  icon: const Icon(Icons.input_outlined, size: 18),
                  label: const Text('导入素材包'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _createPack,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('新建素材包'),
                ),
              ],
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
  Widget _packCard(
    StickerPack pack, {
    required int stickers,
    required int templates,
  }) {
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
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onTap: () => _openDetail(PackDetailPage.pack(pack.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: PackCoverImage(pack: pack)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
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
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 包级操作直达（与详情页右上角菜单同一份逻辑）：
                  // 不进详情页也能改名 / 换封面 / 导出 / 解散 / 删除。
                  IconButton(
                    tooltip: '素材包操作',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => showPackMenu(context, pack),
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
