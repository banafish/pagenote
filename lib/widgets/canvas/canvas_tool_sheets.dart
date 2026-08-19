import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_fonts.dart';
import '../../models/canvas_page.dart';
import '../../models/decoration.dart';
import '../../models/sticker_assets.dart';
import '../../providers/custom_sticker_provider.dart';
import '../../providers/journal_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/template_provider.dart';
import '../../utils/sticker_store.dart';

/// 画布工具面板（调研一/二阶段）：素材与属性编辑的底部弹层集合。

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
Future<void> showStickerPalette(
  BuildContext context, {
  required void Function(CanvasElement element) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // 连续插入期间画布需保持可见,故不压重遮罩（REQ-17.3）。
    barrierColor: Colors.black.withValues(alpha: 0.06),
    builder: (sheetContext) => _StickerPaletteSheet(onPick: onPick),
  );
}

class _StickerPaletteSheet extends StatefulWidget {
  const _StickerPaletteSheet({required this.onPick});

  final void Function(CanvasElement element) onPick;

  @override
  State<_StickerPaletteSheet> createState() => _StickerPaletteSheetState();
}

class _StickerPaletteSheetState extends State<_StickerPaletteSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final TextEditingController _search = TextEditingController();

  /// 跨页签搜索词（REQ-17.6）,非空时页签区替换为统一结果列表。
  String _query = '';

  /// 折叠态只留搜索与最近使用,画布露出更多（REQ-17.3）。
  bool _collapsed = false;

  /// 待插入矢量贴纸的色调（REQ-19.1）,null 为素材原配色。
  int? _tint;

  /// 表情页签当前类目（REQ-17.7）。
  String _emojiCategory = emojiCategories.keys.first;

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
      return TapeElement(style: tape.style, color: tape.color, x: 0.35, y: 0.46);
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
    // 页签区高度：小屏也留得下头部与两条横滑区。
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
                if (_query.isEmpty && favorites.isNotEmpty)
                  _keyStrip('收藏', favorites, reorderable: true),
                if (_query.isEmpty && recent.isNotEmpty)
                  _keyStrip('最近使用', recent),
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
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '可连续点选，长按可收藏',
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onChanged: (value) => setState(() => _query = value.trim()),
      ),
    );
  }

  // ---------------- 最近使用与收藏（REQ-17.1 / 17.2） ----------------

  /// 一条横滑素材带；[reorderable] 为收藏区,长按可拖拽排序并持久化。
  Widget _keyStrip(String title, List<String> keys, {bool reorderable = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: Text(
            reorderable ? '$title · 长按可拖动排序' : title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 54,
          child: reorderable
              ? ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: keys.length,
                  itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                    key: ValueKey(keys[i]),
                    index: i,
                    // 收藏区的长按已被拖拽排序占用,取消收藏回各页签长按。
                    child: _stripCell(keys[i], canFavorite: false),
                  ),
                  onReorderItem: (from, to) {
                    final next = [...keys];
                    next.insert(to, next.removeAt(from));
                    context.read<SettingsProvider>().reorderFavoriteStickers(
                      next,
                    );
                  },
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [for (final key in keys) _stripCell(key)],
                ),
        ),
      ],
    );
  }

  Widget _stripCell(String key, {bool canFavorite = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: SizedBox(
        width: 48,
        child: _pickable(
          favoriteKey: key,
          canFavorite: canFavorite,
          tooltip: _keyLabel(key),
          onTap: () {
            final element = _elementForKey(key);
            if (element != null) _pick(element, key);
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

  /// 素材格子的统一交互：点选插入,长按收藏 / 取消收藏（REQ-17.2）。
  /// [canFavorite] 为 false 时只保留点选,把长按让给外层的拖拽排序。
  Widget _pickable({
    required String favoriteKey,
    required VoidCallback onTap,
    required Widget child,
    bool canFavorite = true,
    String? tooltip,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final favorite = context.watch<SettingsProvider>().isFavoriteSticker(
      favoriteKey,
    );
    final cell = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: canFavorite
          ? () => context.read<SettingsProvider>().toggleFavoriteSticker(
              favoriteKey,
            )
          : null,
      child: Stack(
        children: [
          Positioned.fill(child: Center(child: child)),
          if (favorite)
            Positioned(
              right: 1,
              top: 1,
              child: Icon(
                Icons.star_rounded,
                size: 12,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    );
    return tooltip == null ? cell : Tooltip(message: tooltip, child: cell);
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
      children: [
        for (final sticker in stickers)
          _pickable(
            favoriteKey: '$stickerKeyVector${sticker.id}',
            tooltip: sticker.name,
            onTap: () => _pick(
              StickerElement(
                key: '$stickerKeyVector${sticker.id}',
                x: 0.42,
                y: 0.46,
                tint: _tint,
              ),
              '$stickerKeyVector${sticker.id}',
            ),
            child: CustomPaint(
              size: const Size(44, 44),
              painter: StickerPainter(sticker.id, tint: _tint),
            ),
          ),
      ],
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
              color: value == null ? scheme.surfaceContainerHighest : Color(value),
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
                return SizedBox(
                  width: 96,
                  child: _pickable(
                    favoriteKey: key,
                    onTap: () => _pick(
                      TapeElement(
                        style: style.id,
                        color: color,
                        x: 0.35,
                        y: 0.46,
                      ),
                      key,
                    ),
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
      children: [
        for (final emoji in items)
          _pickable(
            favoriteKey: '$stickerKeyEmoji${emoji.char}',
            onTap: () => _pick(
              StickerElement(
                key: '$stickerKeyEmoji${emoji.char}',
                x: 0.42,
                y: 0.46,
              ),
              '$stickerKeyEmoji${emoji.char}',
            ),
            child: Text(emoji.char, style: const TextStyle(fontSize: 26)),
          ),
      ],
    );
  }

  // ---------------- 我的页签（REQ-20） ----------------

  Widget _mineTab() {
    final scheme = Theme.of(context).colorScheme;
    final stickers = context.watch<CustomStickerProvider>().stickers;
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
                  '长按素材可重命名 / 分组 / 删除',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: stickers.isEmpty
              ? _mineEmpty(scheme)
              : _customGrid(stickers),
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
      children: [
        for (final sticker in stickers)
          Tooltip(
            message: sticker.name,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _pick(
                StickerElement(key: sticker.stickerKey, x: 0.42, y: 0.46),
                sticker.stickerKey,
              ),
              onLongPress: () => _customStickerMenu(sticker),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.file(
                  File(StickerStore.pathOf(sticker.id, sticker.ext)),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 从相册导入图片作为贴纸（REQ-20.1）；解码失败的图片跳过并提示。
  Future<void> _importCustomStickers() async {
    final provider = context.read<CustomStickerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final files = await StickerStore.pickImages();
    if (files.isEmpty) return;
    var failed = 0;
    for (final file in files) {
      if (await provider.importFromFile(file) == null) failed++;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已导入 ${files.length} 张素材'
              : '$failed 张图片无法识别，已跳过',
        ),
      ),
    );
  }

  /// 自定义素材长按菜单：重命名 / 分组 / 删除（REQ-20.4）。
  Future<void> _customStickerMenu(CustomSticker sticker) async {
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
          itemCount: paperStyles.where((p) => p.kind == kind).length +
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
              Text('花样字体', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
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
                          fontFamily:
                              font.family.isEmpty ? null : font.family,
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
                      onChanged: (v) =>
                          setState(() => e.fontScale = v / 400),
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
              Text('墨色', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
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
                  ButtonSegment(value: 1, icon: Icon(Icons.format_align_center)),
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
Future<bool> showImageElementEditor(BuildContext context, ImageElement element) {
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
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
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
                        onChanged: (v) =>
                            setSheetState(() => e.radius = v),
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
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
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
      painter: StickerPainter(key.substring(stickerKeyVector.length), tint: tint),
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
