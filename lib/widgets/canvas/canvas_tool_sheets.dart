import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_fonts.dart';
import '../../models/canvas_page.dart';
import '../../models/decoration.dart';
import '../../models/sticker_assets.dart';
import '../../pages/library_page.dart';
import '../../providers/custom_sticker_provider.dart';
import '../../providers/journal_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/template_provider.dart';
import '../../utils/sticker_store.dart';
import '../sticker_pack_sheet.dart';

/// 画布工具面板（调研一/二阶段）：素材与属性编辑的底部弹层集合。

/// 「我的」页签的未分组过滤值（packId 为 null 的贴纸）。
/// 包 id 由 makeId 生成，不会与该哨兵值撞车。
const _mineUngroupedFilter = '__ungrouped__';

/// 文字可选墨色。
const textInkColors = <int>[
  0xFF4A3F35, // 深棕（默认）
  0xFF3B3B3B, // 墨黑
  0xFFB04A4A, // 胭脂
  0xFFC77B42, // 赭橙
  0xFF4A7BA6, // 黛蓝
  0xFF5B8A5E, // 苔绿
  0xFF7B5EA7, // 青紫
  0xFFC2708B, // 豆沙粉
];

/// 素材面板中胶带的最近使用 / 收藏 key：`tape:<纹样 id>:<色值>`。
/// 仅用于面板本地的 SharedPreferences 记录（贴纸 key 体系不含胶带）。
const _tapeKeyPrefix = 'tape:';

String _tapeKey(String style, int color) => '$_tapeKeyPrefix$style:$color';

({String style, int color})? _decodeTapeKey(String key) {
  final parts = key.substring(_tapeKeyPrefix.length).split(':');
  if (parts.length != 2) return null;
  final color = int.tryParse(parts[1]);
  if (color == null || tapeStyleById(parts[0]) == null) return null;
  return (style: parts[0], color: color);
}

/// 贴纸素材面板：贴纸（矢量）/ 胶带 / 表情 / 我的 四个页签。
///
/// REQ-17.3：改为可连续插入的常驻抽屉 —— 选中素材后面板不关闭,
/// 每选中一次回调一次 [onPick]。元素用默认落点构造,
/// 递增偏移由画布端负责,面板不参与坐标计算。
/// REQ-17.5：长按素材可直接拖到画布指定位置,落点由画布端的 DragTarget 结算。
Future<void> showStickerPalette(
  BuildContext context, {
  required void Function(CanvasElement element) onPick,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  late final _StickerPaletteRoute route;
  route = _StickerPaletteRoute(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    builder: (sheetContext) =>
        _StickerPaletteSheet(onPick: onPick, dragging: route.dragging),
  );
  return navigator.push(route);
}

/// 面板专用的模态路由：拖拽期间放行遮罩的命中测试（REQ-17.5）。
/// 底部弹层的遮罩对命中测试不透明,画布上的落区（DragTarget）被它整块挡住,
/// 拖出面板就再也收不到落点；这里在拖拽开始后临时让遮罩不接收指针,
/// 松手判定即可穿到画布。返回键 / Navigator.pop 等模态语义保持不变。
class _StickerPaletteRoute extends ModalBottomSheetRoute<void> {
  _StickerPaletteRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
  }) : super(
         isScrollControlled: true,
         showDragHandle: true,
         // 连续插入期间画布需保持可见,故不压重遮罩（REQ-17.3）。
         modalBarrierColor: Colors.black.withValues(alpha: 0.06),
       );

  /// 面板内是否正有素材在拖拽中。
  final ValueNotifier<bool> dragging = ValueNotifier(false);

  @override
  Widget buildModalBarrier() => ValueListenableBuilder<bool>(
    valueListenable: dragging,
    child: super.buildModalBarrier(),
    builder: (context, value, child) =>
        IgnorePointer(ignoring: value, child: child),
  );

  @override
  void dispose() {
    dragging.dispose();
    super.dispose();
  }
}

class _StickerPaletteSheet extends StatefulWidget {
  const _StickerPaletteSheet({required this.onPick, required this.dragging});

  final void Function(CanvasElement element) onPick;

  /// 拖拽状态回传给路由,用于放行遮罩（见 [_StickerPaletteRoute]）。
  final ValueNotifier<bool> dragging;

  @override
  State<_StickerPaletteSheet> createState() => _StickerPaletteSheetState();
}

class _StickerPaletteSheetState extends State<_StickerPaletteSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final TextEditingController _search = TextEditingController();

  /// 跨页签搜索词（REQ-17.6）,非空时页签区替换为统一结果列表。
  String _query = '';

  /// 折叠态只留搜索与素材带（收藏 / 最近使用）,画布露出更多（REQ-17.3）。
  bool _collapsed = false;

  /// 素材带当前显示收藏还是最近使用（两条合并成一条后靠它切换）。
  bool _showFavorites = true;

  /// 待插入矢量贴纸的色调（REQ-19.1）,null 为素材原配色。
  int? _tint;

  /// 表情页签当前类目（REQ-17.7）。
  String _emojiCategory = emojiCategories.keys.first;

  /// 「我的」页签的包过滤（v7）：null = 全部，
  /// [_mineUngroupedFilter] = 未分组，其余为包 id。
  String? _minePackFilter;

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  // ---------------- 插入与收藏 ----------------

  /// 选中素材：交给画布并记一笔最近使用,面板保持打开。
  void _pick(CanvasElement element, String recentKey) {
    widget.onPick(element);
    context.read<SettingsProvider>().pushRecentSticker(recentKey);
  }

  /// 由最近使用 / 收藏的 key 还原元素；素材已缺失返回 null。
  CanvasElement? _elementForKey(String key) {
    if (key.startsWith(_tapeKeyPrefix)) {
      final tape = _decodeTapeKey(key);
      if (tape == null) return null;
      return TapeElement(
        style: tape.style,
        color: tape.color,
        x: 0.35,
        y: 0.46,
      );
    }
    if (!isKnownStickerKey(key)) return null;
    return StickerElement(
      key: key,
      x: 0.42,
      y: 0.46,
      tint: key.startsWith(stickerKeyVector) ? _tint : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    // 搜索时软键盘弹出,面板整体上抬,页签区随之收缩。
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    // 页签区高度：小屏也留得下头部与横滑素材带。
    final bodyHeight = (screenHeight * 0.36).clamp(180.0, 320.0);
    // 素材已被删除的收藏项直接不展示,排序时一并落库自净。
    final favorites = [
      for (final key in settings.favoriteStickerKeys)
        if (_elementForKey(key) != null) key,
    ];
    final recent = [
      for (final key in settings.recentStickerKeys)
        if (_elementForKey(key) != null) key,
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (screenHeight * 0.8 - insets).clamp(220.0, screenHeight),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(scheme),
                _searchField(scheme),
                if (_query.isEmpty && (favorites.isNotEmpty || recent.isNotEmpty))
                  _quickStrip(favorites, recent),
                if (!_collapsed) ...[
                  if (_query.isEmpty)
                    TabBar(
                      controller: _tabs,
                      labelColor: scheme.primary,
                      tabs: const [
                        Tab(text: '贴纸'),
                        Tab(text: '胶带'),
                        Tab(text: '表情'),
                        Tab(text: '我的'),
                      ],
                    ),
                  Flexible(
                    child: SizedBox(
                      height: bodyHeight,
                      child: _query.isEmpty
                          ? TabBarView(
                              controller: _tabs,
                              children: [
                                _vectorTab(),
                                _tapeTab(),
                                _emojiTab(),
                                _mineTab(),
                              ],
                            )
                          : _searchResults(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 6, 0),
      child: Row(
        children: [
          Text(
            '素材',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '可连续点选，长按拖到画布指定位置',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: _collapsed ? '展开面板' : '收起面板',
            icon: Icon(
              _collapsed
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            onPressed: () => setState(() => _collapsed = !_collapsed),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _searchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索素材，如「花」「咖啡」「爱心」',
          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (value) => setState(() => _query = value.trim()),
      ),
    );
  }

  // ---------------- 最近使用与收藏（REQ-17.1 / 17.2） ----------------

  /// 收藏与最近使用合并为一条素材带：标题行放切换,选中哪侧显示哪侧。
  /// 当前侧为空时自动落到另一侧（空侧的切换不可点）,
  /// 两侧都空则整条不出场（build 里已挡）。
  Widget _quickStrip(List<String> favorites, List<String> recent) {
    final scheme = Theme.of(context).colorScheme;
    final showFavorites = favorites.isNotEmpty &&
        (recent.isEmpty || _showFavorites);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: Row(
            children: [
              _quickTab(
                '收藏',
                selected: showFavorites,
                enabled: favorites.isNotEmpty,
                onTap: () => setState(() => _showFavorites = true),
              ),
              const SizedBox(width: 6),
              _quickTab(
                '最近使用',
                selected: !showFavorites,
                enabled: recent.isNotEmpty,
                onTap: () => setState(() => _showFavorites = false),
              ),
              if (showFavorites)
                Expanded(
                  child: Text(
                    '长按可拖动排序',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 54,
          child: showFavorites
              ? ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: favorites.length,
                  itemBuilder: (context, i) =>
                      ReorderableDelayedDragStartListener(
                        key: ValueKey(favorites[i]),
                        index: i,
                        // 收藏区的长按归拖拽排序,取消收藏点右上角星标；
                        // 拖到画布从下方页签发起（REQ-17.5）。
                        child: _stripCell(favorites[i], draggable: false),
                      ),
                  onReorderItem: (from, to) {
                    final next = [...favorites];
                    next.insert(to, next.removeAt(from));
                    context.read<SettingsProvider>().reorderFavoriteStickers(
                      next,
                    );
                  },
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [for (final key in recent) _stripCell(key)],
                ),
        ),
      ],
    );
  }

  /// 素材带标题行的切换药丸：选中侧以主题色淡底高亮,空侧淡化且不可点。
  Widget _quickTab(
    String label, {
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
      ),
    );
  }

  Widget _stripCell(String key, {bool draggable = true}) {
    final element = _elementForKey(key);
    if (element == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: SizedBox(
        width: 48,
        child: _pickable(
          favoriteKey: key,
          // 画布端落点时会克隆一份,这里复用同一实例即可。
          dragElement: draggable ? () => element : null,
          tooltip: _keyLabel(key),
          onTap: () {
            final fresh = _elementForKey(key);
            if (fresh != null) _pick(fresh, key);
          },
          child: _keyThumb(key, size: 34),
        ),
      ),
    );
  }

  /// 素材缩略图：按 key 前缀分发（矢量 / emoji / 自定义图片 / 胶带）。
  Widget _keyThumb(String key, {double size = 40}) {
    if (key.startsWith(_tapeKeyPrefix)) {
      final tape = _decodeTapeKey(key);
      if (tape == null) return const SizedBox.shrink();
      return ClipRect(
        child: SizedBox(
          width: size,
          height: size * 0.5,
          child: CustomPaint(
            painter: TapePainter(style: tape.style, color: Color(tape.color)),
          ),
        ),
      );
    }
    if (key.startsWith(stickerKeyVector)) {
      return CustomPaint(
        size: Size(size, size),
        painter: StickerPainter(
          key.substring(stickerKeyVector.length),
          tint: _tint,
        ),
      );
    }
    if (key.startsWith(stickerKeyImage)) {
      final path = CustomStickerIndex.instance.pathOf(
        key.substring(stickerKeyImage.length),
      );
      if (path == null) return const SizedBox.shrink();
      return SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    final emoji = key.startsWith(stickerKeyEmoji)
        ? key.substring(stickerKeyEmoji.length)
        : key;
    return Text(emoji, style: TextStyle(fontSize: size * 0.76));
  }

  String _keyLabel(String key) {
    if (key.startsWith(_tapeKeyPrefix)) {
      final tape = _decodeTapeKey(key);
      return '${tapeStyleById(tape?.style ?? '')?.name ?? '胶带'}胶带';
    }
    return stickerKeyLabel(key);
  }

  /// 素材格子的统一交互：点选插入,长按拖到画布指定位置（REQ-17.5）,
  /// 右上角角标默认为收藏星标（REQ-17.2,点按切换 —— 长按已让给拖拽）。
  /// [dragElement] 为空时不发起拖拽（收藏条的长按归排序）；
  /// [badge] 可替换角标（「我的」页签放素材管理菜单）。
  Widget _pickable({
    required String favoriteKey,
    required VoidCallback onTap,
    required Widget child,
    CanvasElement Function()? dragElement,
    bool canFavorite = true,
    Widget? badge,
    String? tooltip,
  }) {
    final body = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Center(child: child),
    );
    final corner = badge ?? (canFavorite ? _favoriteStar(favoriteKey) : null);
    final cell = Stack(
      children: [
        Positioned.fill(
          child: dragElement == null
              ? body
              : LongPressDraggable<CanvasElement>(
                  data: dragElement(),
                  // 画布端把落点 offset 当作元素中心,故锚点取指针本身;
                  // 触摸与鼠标长按走同一条路径,双端一致（NFR-04）。
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: _dragFeedback(favoriteKey),
                  childWhenDragging: Opacity(opacity: 0.25, child: body),
                  onDragStarted: () => widget.dragging.value = true,
                  onDragEnd: (_) => widget.dragging.value = false,
                  onDragCompleted: () => context
                      .read<SettingsProvider>()
                      .pushRecentSticker(favoriteKey),
                  child: body,
                ),
        ),
        if (corner != null) Positioned(right: 0, top: 0, child: corner),
      ],
    );
    return tooltip == null ? cell : Tooltip(message: tooltip, child: cell);
  }

  /// 收藏角标（REQ-17.2）：点按切换收藏,未收藏时留一颗淡描边星做入口提示。
  Widget _favoriteStar(String key) {
    final scheme = Theme.of(context).colorScheme;
    final favorite = context.watch<SettingsProvider>().isFavoriteSticker(key);
    return Tooltip(
      message: favorite ? '取消收藏' : '收藏',
      child: InkResponse(
        radius: 16,
        onTap: () =>
            context.read<SettingsProvider>().toggleFavoriteSticker(key),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            favorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 15,
            color: favorite
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  /// 拖拽跟手预览（REQ-17.5）：半透明缩略图,并以指针为中心对齐,
  /// 与画布端「落点 offset 即元素中心」的约定吻合。
  Widget _dragFeedback(String key) {
    final tape = key.startsWith(_tapeKeyPrefix);
    return FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: 0.75,
          child: _keyThumb(key, size: tape ? 100 : 56),
        ),
      ),
    );
  }

  // ---------------- 贴纸页签（含 REQ-19 换色） ----------------

  Widget _vectorTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        _tintRow(),
        for (final category in stickerCategories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              category,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          _vectorGrid(
            vectorStickers.where((s) => s.category == category).toList(),
          ),
        ],
      ],
    );
  }

  Widget _vectorGrid(List<StickerAsset> stickers) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.9,
      children: [for (final sticker in stickers) _vectorCell(sticker)],
    );
  }

  Widget _vectorCell(StickerAsset sticker) {
    final key = '$stickerKeyVector${sticker.id}';
    StickerElement make() =>
        StickerElement(key: key, x: 0.42, y: 0.46, tint: _tint);
    return _pickable(
      favoriteKey: key,
      tooltip: sticker.name,
      dragElement: make,
      onTap: () => _pick(make(), key),
      child: CustomPaint(
        size: const Size(44, 44),
        painter: StickerPainter(sticker.id, tint: _tint),
      ),
    );
  }

  /// 插入前先选色（REQ-19.1）：「原色」对应 tint 为 null。
  Widget _tintRow() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '配色',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _tintDot(null),
                for (final color in stickerPaletteColors)
                  _tintDot(color.toARGB32()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tintDot(int? value) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tint == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: GestureDetector(
        onTap: () => setState(() => _tint = value),
        child: Tooltip(
          message: value == null ? '原色' : '换色',
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value == null
                  ? scheme.surfaceContainerHighest
                  : Color(value),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.6,
              ),
            ),
            child: value == null
                ? Text(
                    '原',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ---------------- 胶带页签 ----------------

  Widget _tapeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [for (final style in tapeStyles) _tapeRow(style)],
    );
  }

  Widget _tapeRow(TapeStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            style.name,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tapePalette.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final color = tapePalette[i];
                final key = _tapeKey(style.id, color);
                TapeElement make() => TapeElement(
                  style: style.id,
                  color: color,
                  x: 0.35,
                  y: 0.46,
                );
                return SizedBox(
                  width: 96,
                  child: _pickable(
                    favoriteKey: key,
                    dragElement: make,
                    onTap: () => _pick(make(), key),
                    child: ClipRect(
                      child: SizedBox(
                        width: 96,
                        height: 34,
                        child: CustomPaint(
                          painter: TapePainter(
                            style: style.id,
                            color: Color(color),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 表情页签（REQ-17.7） ----------------

  Widget _emojiTab() {
    final items = emojiCategories[_emojiCategory] ?? const <EmojiAsset>[];
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            itemCount: emojiCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final name = emojiCategories.keys.elementAt(i);
              return ChoiceChip(
                label: Text(name, style: const TextStyle(fontSize: 12.5)),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selected: name == _emojiCategory,
                onSelected: (_) => setState(() => _emojiCategory = name),
              );
            },
          ),
        ),
        Expanded(child: _emojiGrid(items)),
      ],
    );
  }

  Widget _emojiGrid(List<EmojiAsset> items, {bool shrinkWrap = false}) {
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [for (final emoji in items) _emojiCell(emoji)],
    );
  }

  Widget _emojiCell(EmojiAsset emoji) {
    final key = '$stickerKeyEmoji${emoji.char}';
    StickerElement make() => StickerElement(key: key, x: 0.42, y: 0.46);
    return _pickable(
      favoriteKey: key,
      dragElement: make,
      onTap: () => _pick(make(), key),
      child: Text(emoji.char, style: const TextStyle(fontSize: 26)),
    );
  }

  // ---------------- 我的页签（REQ-20 + v7 素材包） ----------------

  Widget _mineTab() {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<CustomStickerProvider>();
    final stickers = provider.stickers;
    final ungrouped = provider.ungroupedStickers;
    // 空包不进切换条：面板是挑素材的地方，没有素材的分组没有意义。
    final packs = [
      for (final pack in provider.packs)
        if (provider.stickersOfPack(pack.id).isNotEmpty) pack,
    ];
    // 过滤目标已被解散 / 删除时回落到全部（不改 state，下次选择自然修正）。
    final filter =
        _minePackFilter != null &&
            _minePackFilter != _mineUngroupedFilter &&
            provider.packById(_minePackFilter!) == null
        ? null
        : _minePackFilter;
    final visible = filter == null
        ? stickers
        : filter == _mineUngroupedFilter
        ? ungrouped
        : provider.stickersOfPack(filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _importCustomStickers,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('导入图片'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '点右上角管理素材，长按可拖到画布',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              // 打包导出等批量操作在素材管理页（REQ-21.2）：
              // 面板本身是编辑器的常驻抽屉,不适合塞多选与导出流程。
              // REQ-26.9：整页打开素材首页（固定入口 + 包列表）。
              IconButton(
                tooltip: '管理我的素材',
                icon: const Icon(Icons.tune_rounded, size: 20),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LibraryPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 素材包切换条（v7）：与表情页签的类目条同一套交互；
        // 没有任何含素材的包时保持原来的整页网格。
        if (packs.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              itemCount: 1 + (ungrouped.isNotEmpty ? 1 : 0) + packs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ChoiceChip(
                    label: const Text('全部', style: TextStyle(fontSize: 12.5)),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selected: filter == null,
                    onSelected: (_) => setState(() => _minePackFilter = null),
                  );
                }
                if (i == 1 && ungrouped.isNotEmpty) {
                  return ChoiceChip(
                    label: const Text('未分组', style: TextStyle(fontSize: 12.5)),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selected: filter == _mineUngroupedFilter,
                    onSelected: (_) =>
                        setState(() => _minePackFilter = _mineUngroupedFilter),
                  );
                }
                final pack = packs[i - 1 - (ungrouped.isNotEmpty ? 1 : 0)];
                return ChoiceChip(
                  label: Text(pack.name, style: const TextStyle(fontSize: 12.5)),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: filter == pack.id,
                  onSelected: (_) => setState(() => _minePackFilter = pack.id),
                );
              },
            ),
          ),
        Expanded(
          child: stickers.isEmpty
              ? _mineEmpty(scheme)
              : _customGrid(visible),
        ),
      ],
    );
  }

  Widget _mineEmpty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 34,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              '还没有自己的素材',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '从相册导入喜欢的图片，就能像内置贴纸一样贴到手账上',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customGrid(List<CustomSticker> stickers, {bool shrinkWrap = false}) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [for (final sticker in stickers) _customCell(sticker)],
    );
  }

  Widget _customCell(CustomSticker sticker) {
    final key = sticker.stickerKey;
    StickerElement make() => StickerElement(key: key, x: 0.42, y: 0.46);
    return _pickable(
      favoriteKey: key,
      tooltip: sticker.name,
      dragElement: make,
      // 长按让给拖拽（REQ-17.5）,重命名 / 分组 / 删除移到角标菜单。
      badge: _customMenuBadge(sticker),
      onTap: () => _pick(make(), key),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.file(
          File(StickerStore.pathOf(sticker.id, sticker.ext)),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, size: 20),
        ),
      ),
    );
  }

  Widget _customMenuBadge(CustomSticker sticker) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '管理素材',
      child: InkResponse(
        radius: 16,
        onTap: () => _customStickerMenu(sticker),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 15,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 从相册导入图片作为贴纸（REQ-20.1）：先问一句要不要去白底（REQ-20.3）,
  /// 超限的图片由仓库自动压缩,提示里如实报出压缩张数与压缩后尺寸（REQ-20.5）。
  Future<void> _importCustomStickers() async {
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
    messenger.showSnackBar(SnackBar(content: Text(parts.join('；'))));
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

  /// 导入单张：按需先去白底,再交给仓库统一压缩落盘。
  /// [ok] 为 false 表示图片无法识别；[shrunk] 非空表示触发了压缩,值为压缩后尺寸。
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
      // 去白底后的字节没有落盘路径,包一层内存 XFile 交给同一条导入链路。
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

  /// 只读图片头拿像素尺寸（不整张解码）,用于如实提示压缩结果（REQ-20.5）；
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

  /// 自定义素材角标菜单：重命名 / 移动到素材包 / 分组 / 删除（REQ-20.4 + v7）。
  Future<void> _customStickerMenu(CustomSticker sticker) async {
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
        await moveStickerToPackFlow(context, sticker);
      case 'category':
        final group = await _promptText('素材分组', '分组名称', sticker.category);
        if (!mounted || group == null) return;
        await context.read<CustomStickerProvider>().setCategory(
          sticker.id,
          group,
        );
      case 'delete':
        await _deleteCustomSticker(sticker);
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

  /// 删除自定义素材；被手账或模板引用时先说明后果再确认（REQ-20.4）。
  Future<void> _deleteCustomSticker(CustomSticker sticker) async {
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
    if (ok == true && mounted) {
      await provider.delete(sticker.id);
    }
  }

  // ---------------- 跨页签搜索（REQ-17.6） ----------------

  Widget _searchResults() {
    final scheme = Theme.of(context).colorScheme;
    final query = _query;
    final vectors = vectorStickers.where((s) => s.matches(query)).toList();
    final emojis = [
      for (final entry in emojiCategories.entries)
        for (final emoji in entry.value)
          if (emoji.matches(query) || entry.key.contains(query)) emoji,
    ];
    final tapes = tapeStyles
        .where((t) => t.name.contains(query) || '胶带'.contains(query))
        .toList();
    final mine = context
        .watch<CustomStickerProvider>()
        .stickers
        .where((s) => s.matches(query))
        .toList();
    if (vectors.isEmpty && emojis.isEmpty && tapes.isEmpty && mine.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '没有找到「$query」相关的素材，换个词试试',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (vectors.isNotEmpty) ...[
          _searchSectionTitle('贴纸', scheme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _vectorGrid(vectors),
          ),
        ],
        if (emojis.isNotEmpty) ...[
          _searchSectionTitle('表情', scheme),
          _emojiGrid(emojis, shrinkWrap: true),
        ],
        if (mine.isNotEmpty) ...[
          _searchSectionTitle('我的', scheme),
          _customGrid(mine, shrinkWrap: true),
        ],
        if (tapes.isNotEmpty) ...[
          _searchSectionTitle('胶带', scheme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final style in tapes) _tapeRow(style)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _searchSectionTitle(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 纸张选择面板：纹理 / 纯色 / 渐变,含「无」。
Future<String?> showPaperPicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            for (final (title, kind) in [
              ('纹理', PaperKind.texture),
              ('纯色', PaperKind.solid),
              ('渐变', PaperKind.gradient),
            ])
              _paperSection(sheetContext, title, kind, current),
          ],
        ),
      ),
    ),
  );
}

Widget _paperSection(
  BuildContext context,
  String title,
  PaperKind kind,
  String current,
) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      SizedBox(
        height: 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount:
              paperStyles.where((p) => p.kind == kind).length +
              (kind == PaperKind.texture ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            // 纹理组首位为「无」（恢复默认背景）,其余组直接铺纸样。
            final offset = kind == PaperKind.texture ? 1 : 0;
            if (i == 0 && offset == 1) {
              return _paperSwatch(context, null, current);
            }
            final papers = paperStyles.where((p) => p.kind == kind).toList();
            return _paperSwatch(context, papers[i - offset], current);
          },
        ),
      ),
    ],
  );
}

Widget _paperSwatch(BuildContext context, PaperStyle? paper, String current) {
  final scheme = Theme.of(context).colorScheme;
  final selected = paper == null ? current.isEmpty : current == paper.id;
  return GestureDetector(
    onTap: () => Navigator.pop(context, paper?.id ?? ''),
    child: Tooltip(
      message: paper?.name ?? '无',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2.4 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: paper == null
              ? Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  alignment: Alignment.center,
                  child: Text(
                    '无',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : CustomPaint(
                  size: const Size(62, 62),
                  painter: PaperPainter(paper),
                ),
        ),
      ),
    ),
  );
}

/// 文本元素编辑面板：内容 / 花样字体 / 字号 / 墨色 / 对齐 / 加粗。
Future<bool> showTextElementEditor(BuildContext context, TextElement element) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _TextElementDialog(element: element),
  ).then((changed) => changed ?? false);
}

class _TextElementDialog extends StatefulWidget {
  const _TextElementDialog({required this.element});

  final TextElement element;

  @override
  State<_TextElementDialog> createState() => _TextElementDialogState();
}

class _TextElementDialogState extends State<_TextElementDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.element.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.element;
    return AlertDialog(
      title: const Text('编辑文字'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(hintText: '写点什么…'),
                style: TextStyle(
                  fontFamily: e.fontFamily.isEmpty ? null : e.fontFamily,
                  fontFamilyFallback: canvasFontFallback,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '花样字体',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final font in appFonts)
                    ChoiceChip(
                      label: Text(
                        font.name,
                        style: TextStyle(
                          fontFamily: font.family.isEmpty ? null : font.family,
                          fontFamilyFallback: canvasFontFallback,
                        ),
                      ),
                      selected: e.fontFamily == font.family,
                      onSelected: (_) =>
                          setState(() => e.fontFamily = font.family),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      value: (e.fontScale * 400).clamp(10, 34),
                      min: 10,
                      max: 34,
                      divisions: 24,
                      label: '${(e.fontScale * 400).round()}',
                      onChanged: (v) => setState(() => e.fontScale = v / 400),
                    ),
                  ),
                  IconButton(
                    tooltip: e.bold ? '取消加粗' : '加粗',
                    isSelected: e.bold,
                    icon: const Icon(Icons.format_bold_rounded),
                    onPressed: () => setState(() => e.bold = !e.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '墨色',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in textInkColors)
                    GestureDetector(
                      onTap: () => setState(() => e.color = color),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: e.color == color
                                ? scheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, icon: Icon(Icons.format_align_left)),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.format_align_center),
                  ),
                  ButtonSegment(value: 2, icon: Icon(Icons.format_align_right)),
                ],
                selected: {e.align},
                onSelectionChanged: (s) => setState(() => e.align = s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            e.text = _controller.text;
            e.h = measureTextHeight(e);
            Navigator.pop(context, true);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 图片元素编辑面板：遮罩（原图 / 圆形 / 拍立得）+ 圆角微调。
Future<bool> showImageElementEditor(
  BuildContext context,
  ImageElement element,
) {
  final e = element;
  final result = showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '照片样式',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              SegmentedButton<ImageMask>(
                segments: const [
                  ButtonSegment(value: ImageMask.none, label: Text('原图')),
                  ButtonSegment(value: ImageMask.circle, label: Text('圆形')),
                  ButtonSegment(value: ImageMask.polaroid, label: Text('拍立得')),
                ],
                selected: {e.mask},
                onSelectionChanged: (s) {
                  setSheetState(() => e.mask = s.first);
                  Navigator.pop(sheetContext, true);
                },
              ),
              if (e.mask == ImageMask.none) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('圆角'),
                    Expanded(
                      child: Slider(
                        value: e.radius.clamp(0, 0.1),
                        min: 0,
                        max: 0.1,
                        onChanged: (v) => setSheetState(() => e.radius = v),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  return result.then((changed) => changed ?? false);
}

/// 贴纸元素编辑面板（REQ-19.2）：换色（仅矢量贴纸）+ 不透明度,
/// 素材本机缺失时明确提示而不是静默显示占位（FIX-03）。
/// 返回 true 表示有改动。
Future<bool> showStickerElementEditor(
  BuildContext context,
  StickerElement element,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _StickerElementDialog(element: element),
  ).then((changed) => changed ?? false);
}

class _StickerElementDialog extends StatefulWidget {
  const _StickerElementDialog({required this.element});

  final StickerElement element;

  @override
  State<_StickerElementDialog> createState() => _StickerElementDialogState();
}

class _StickerElementDialogState extends State<_StickerElementDialog> {
  // 先改本地副本,取消即原样退出,不留下半截修改。
  late int? _tint = widget.element.tint;
  late double _opacity = widget.element.opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = widget.element.key;
    final vector = key.startsWith(stickerKeyVector);
    final missing = !isKnownStickerKey(key);
    return AlertDialog(
      title: const Text('编辑贴纸'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (missing)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '素材「${stickerKeyLabel(key)}」在本机缺失，画布上显示为占位框。'
                    '换成本机已有的素材即可恢复。',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Opacity(
                    opacity: _opacity,
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: _stickerPreview(key, _tint),
                    ),
                  ),
                ),
              ),
              // 换色只对矢量贴纸有效,emoji 与图片贴纸不显示该项（REQ-19.2）。
              if (vector && !missing) ...[
                Text(
                  '配色',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _tintSwatch(null, scheme),
                    for (final color in stickerPaletteColors)
                      _tintSwatch(color.toARGB32(), scheme),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Text('不透明度'),
                  Expanded(
                    child: Slider(
                      value: _opacity.clamp(0.2, 1),
                      min: 0.2,
                      max: 1,
                      divisions: 16,
                      label: '${(_opacity * 100).round()}%',
                      onChanged: (v) => setState(() => _opacity = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final changed =
                _tint != widget.element.tint ||
                _opacity != widget.element.opacity;
            widget.element.tint = _tint;
            widget.element.opacity = _opacity;
            Navigator.pop(context, changed);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _tintSwatch(int? value, ColorScheme scheme) {
    final selected = _tint == value;
    return GestureDetector(
      onTap: () => setState(() => _tint = value),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value == null ? scheme.surfaceContainerHighest : Color(value),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: value == null
            ? Text(
                '原',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            : null,
      ),
    );
  }
}

/// 贴纸预览：与画布渲染同构（矢量 / 自定义图片 / emoji）。
Widget _stickerPreview(String key, int? tint) {
  if (key.startsWith(stickerKeyVector)) {
    return CustomPaint(
      size: const Size(60, 60),
      painter: StickerPainter(
        key.substring(stickerKeyVector.length),
        tint: tint,
      ),
    );
  }
  if (key.startsWith(stickerKeyImage)) {
    final path = CustomStickerIndex.instance.pathOf(
      key.substring(stickerKeyImage.length),
    );
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const CustomPaint(painter: StickerPainter('__missing__')),
      );
    }
    return const CustomPaint(
      size: Size(60, 60),
      painter: StickerPainter('__missing__'),
    );
  }
  final emoji = key.startsWith(stickerKeyEmoji)
      ? key.substring(stickerKeyEmoji.length)
      : key;
  return FittedBox(fit: BoxFit.contain, child: Text(emoji));
}
