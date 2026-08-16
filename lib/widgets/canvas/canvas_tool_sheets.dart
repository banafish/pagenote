import 'package:flutter/material.dart';

import '../../models/app_fonts.dart';
import '../../models/canvas_page.dart';
import '../../models/decoration.dart';
import '../../models/sticker_assets.dart';

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

/// 贴纸素材面板：贴纸（矢量）/ 胶带 / 表情 三个页签。
/// 返回新元素；用户关闭返回 null。
Future<CanvasElement?> showStickerPalette(BuildContext context) {
  return showModalBottomSheet<CanvasElement>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _StickerPaletteSheet(),
  );
}

class _StickerPaletteSheet extends StatefulWidget {
  const _StickerPaletteSheet();

  @override
  State<_StickerPaletteSheet> createState() => _StickerPaletteSheetState();
}

class _StickerPaletteSheetState extends State<_StickerPaletteSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              labelColor: scheme.primary,
              tabs: const [
                Tab(text: '贴纸'),
                Tab(text: '胶带'),
                Tab(text: '表情'),
              ],
            ),
            Flexible(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _vectorGrid(context),
                  _tapeGrid(context),
                  _emojiGrid(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vectorGrid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
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
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
            children: [
              for (final sticker in vectorStickers
                  .where((s) => s.category == category))
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(
                    context,
                    StickerElement(key: 'vec:${sticker.id}', x: 0.42, y: 0.46),
                  ),
                  child: Tooltip(
                    message: sticker.name,
                    child: Center(
                      child: CustomPaint(
                        size: const Size(44, 44),
                        painter: StickerPainter(sticker.id),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tapeGrid(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        for (final style in tapeStyles)
          Padding(
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
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.pop(
                          context,
                          TapeElement(style: style.id, color: color, x: 0.35, y: 0.46),
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
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _emojiGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 6,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        for (final e in stickerPalette)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(
              context,
              StickerElement(key: 'emoji:$e', x: 0.42, y: 0.46),
            ),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
          ),
      ],
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
