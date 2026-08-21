import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/sticker_assets.dart' show stickerKeyImage;
import '../models/template.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/share_pack_service.dart';
import '../utils/date_utils.dart';
import '../widgets/canvas/canvas_view.dart';
import 'editor_page.dart';

/// 缩略图用的预览条目：组件元素（日期/心情等）从它读取展示数据。
final _previewEntry = JournalEntry(
  id: 'preview',
  date: DateUtils2.dateKey(DateTime.now()),
  title: '',
  content: '',
  mood: Mood.calm,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// 网格单元的目标宽度：手机两列,桌面端自动加列（NFR 双端一致）。
const _cellExtent = 200.0;
const _cellSpacing = 12.0;
const _gridPadding = 16.0;

/// 缩略图宽高比（含底部名字栏）。
const _cellRatio = 0.62;

// ---------------- 分享包导出的公共件（REQ-21.1/21.2，设置页复用） ----------------

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

/// 模板管理的纯 body（REQ-09.3 + REQ-18，REQ-23 拆分）：网格缩略图、
/// 排序、单卡片操作与空态引导。顶栏（含多选态）由宿主 [LibraryPage]
/// 统一渲染，「素材」一级入口的子页签与独立整页形态共用这一份实现。
class TemplateManagerBody extends StatefulWidget {
  const TemplateManagerBody({
    super.key,
    required this.selecting,
    required this.selectedIds,
    this.highlightIds = const [],
    required this.onToggleSelect,
    required this.onExport,
  });

  /// 多选态（REQ-21.1）由宿主持有：卡片勾选只是其中一个触发点。
  final bool selecting;

  /// 已勾选的模板 id，与宿主共享同一份集合。
  final Set<String> selectedIds;

  /// 刚从分享包装进来的模板 id，卡片上做高亮标记（REQ-21.9）。
  final List<String> highlightIds;

  /// 多选态下点卡片：勾选 / 取消勾选。
  final ValueChanged<JournalTemplate> onToggleSelect;

  /// 导出为素材包（REQ-21.1）：卡片菜单的单个导出也走这里。
  final void Function(List<JournalTemplate> targets) onExport;

  @override
  State<TemplateManagerBody> createState() => _TemplateManagerBodyState();
}

class _TemplateManagerBodyState extends State<TemplateManagerBody> {
  @override
  void initState() {
    super.initState();
    // 进页面时读回持久化的排序方式（REQ-18.4）;
    // 放到首帧之后,避免在 build 期间通知监听者。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final name = context.read<SettingsProvider>().templateSortName;
      context.read<TemplateProvider>().setSort(
        TemplateSort.values.where((s) => s.name == name).firstOrNull ??
            TemplateSort.manual,
      );
    });
  }

  Future<void> _setSort(TemplateSort sort) async {
    context.read<TemplateProvider>().setSort(sort);
    await context.read<SettingsProvider>().setTemplateSortName(sort.name);
  }

  // ---------------- 单个模板的操作 ----------------

  Future<void> _onAction(String action, JournalTemplate template) async {
    switch (action) {
      case 'rename':
        await _rename(template);
      case 'duplicate':
        await _duplicate(template);
      case 'export':
        widget.onExport([template]);
      case 'delete':
        await _delete(template);
    }
  }

  Future<void> _rename(JournalTemplate template) async {
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

  /// 复制一份（REQ-18.2）;内置模板走同一入口,副本可自由改名编辑（REQ-18.3）。
  Future<void> _duplicate(JournalTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = await context.read<TemplateProvider>().duplicateTemplate(
      template,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已复制为「${copy.name}」,可自由改名编辑 ✨')));
  }

  Future<void> _delete(JournalTemplate template) async {
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

  /// 点卡片看大图：网格缩略图偏小,放大后能确认版式细节。
  void _preview(JournalTemplate template) {
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
                              ? '这是一份纯文本模板,套用后直接开写。'
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

  /// 手动模式下拖拽落位：整体重排用户模板并持久化（REQ-18.4）。
  Future<void> _reorder(List<JournalTemplate> users, int from, int to) async {
    final ids = users.map((t) => t.id).toList();
    final moved = ids.removeAt(from);
    ids.insert(to.clamp(0, ids.length), moved);
    await context.read<TemplateProvider>().reorderUserTemplates(ids);
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemplateProvider>();
    final builtin = provider.builtinTemplates;
    final users = provider.userTemplates;
    // 多选态下让出长按手势，拖拽排序不受影响（两者不同时生效）。
    final draggable =
        !widget.selecting && provider.sort == TemplateSort.manual && users.length > 1;
    final cell = _cellSize(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _sortBar(provider.sort, draggable)),
        if (builtin.isNotEmpty) ...[
          _sectionLabel('内置模板', '可复制为我的模板后自由修改'),
          _grid(
            itemCount: builtin.length,
            builder: (context, i) => _card(builtin[i]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
        _sectionLabel('我的模板', users.isEmpty ? null : '共 ${users.length} 套'),
        if (users.isEmpty)
          SliverToBoxAdapter(child: _emptyGuide())
        else
          _grid(
            itemCount: users.length,
            builder: (context, i) =>
                draggable ? _draggableCell(users, i, cell) : _card(users[i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  /// 排序切换（REQ-18.4）：窄屏可横向滚动,不挤压文案。
  Widget _sortBar(TemplateSort sort, bool draggable) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gridPadding, 10, _gridPadding, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TemplateSort>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
              ),
              segments: const [
                ButtonSegment(value: TemplateSort.recent, label: Text('最近使用')),
                ButtonSegment(value: TemplateSort.created, label: Text('创建时间')),
                ButtonSegment(value: TemplateSort.manual, label: Text('手动排序')),
              ],
              selected: {sort},
              onSelectionChanged: (values) => _setSort(values.first),
            ),
          ),
          if (widget.selecting) ...[
            const SizedBox(height: 8),
            Text(
              '点卡片勾选，内置模板也能打包；选好后点右上角导出',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ] else if (draggable) ...[
            const SizedBox(height: 8),
            Text(
              '长按卡片拖动可调整「我的模板」顺序',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, String? hint) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _gridPadding + 4,
          0,
          _gridPadding,
          10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
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
    );
  }

  /// 懒渲染网格（REQ-18.6）：只构建可视范围内的缩略图。
  Widget _grid({
    required int itemCount,
    required NullableIndexedWidgetBuilder builder,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _cellExtent,
          mainAxisSpacing: _cellSpacing,
          crossAxisSpacing: _cellSpacing,
          childAspectRatio: _cellRatio,
        ),
        itemCount: itemCount,
        itemBuilder: builder,
      ),
    );
  }

  Widget _card(JournalTemplate template) => _TemplateCard(
    template: template,
    selecting: widget.selecting,
    selected: widget.selectedIds.contains(template.id),
    highlighted: widget.highlightIds.contains(template.id),
    onTap: () {
      if (widget.selecting) {
        widget.onToggleSelect(template);
      } else {
        _preview(template);
      }
    },
    onAction: (action) => _onAction(action, template),
  );

  /// 手动模式的可拖拽单元（REQ-18.4）：内置模板恒在前且不参与拖拽。
  Widget _draggableCell(List<JournalTemplate> users, int index, Size cell) {
    final scheme = Theme.of(context).colorScheme;
    final card = _card(users[index]);
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => _reorder(users, details.data, index),
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

  /// 空态引导（REQ-18.5）：说清「另存为模板」在哪,并给去写一篇的入口。
  Widget _emptyGuide() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _gridPadding),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.bookmark_add_outlined,
            size: 34,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text(
            '把喜欢的一页另存为模板',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '排好版式的手账,在编辑页右上角「更多」里选「另存为模板」,\n下次新建时一键套用。也可以先复制一套内置模板改着用。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
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
    );
  }

  /// 拖拽悬浮卡的尺寸：与网格实际算法保持一致。
  Size _cellSize(BuildContext context) {
    final avail = MediaQuery.sizeOf(context).width - _gridPadding * 2;
    final columns = (avail / _cellExtent).ceil().clamp(1, 8);
    final width = (avail - _cellSpacing * (columns - 1)) / columns;
    return Size(width, width / _cellRatio);
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
    // 描边走 foregroundDecoration 画在内容之上:缩略图 cover 铺满后
    // 仍能完整露出顶部圆角线,不会被预览图盖住。
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
      child: InkWell(
        onTap: onTap,
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

  /// 整页版式缩略图,与模板选择弹层同一套渲染（所见即所得）;
  /// 单独隔离重绘,长列表滚动不拖累其他卡片（REQ-18.6）。
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
    // cover 铺满缩略图区,顶部对齐:纸面顶到卡边后由卡片圆角统一裁型,
    // 避免 contain 留缝时直角纸面顶进卡片圆角;整页细节由大图预览负责。
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
          // 内置模板的显式复制入口（REQ-18.3）;多选态下让位给勾选。
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
                // 内置模板不可删（REQ-09.3）,菜单里直接不出现。
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
