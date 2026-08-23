import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_page.dart';
import '../../models/journal_entry.dart';
import '../../models/sticker_assets.dart';
import 'canvas_tool_sheets.dart';
import 'canvas_view.dart';
import 'canvas_zoom.dart';

/// 画布编辑层（调研二/三阶段）：静态渲染之上叠加手势与选择态。
///
/// 交互（手势替代滑杆）：
/// - 单指点按未选中元素 → 选中；点空白 → 取消选中
/// - 选中后单指拖动 → 移动；双指捏合 → 缩放 + 旋转
/// - 角点手柄拖动 → 单指调整大小（文本/胶带调宽,其余等比缩放）
/// - 再次点按已选中的文本/图片/贴纸/组件 → 打开对应编辑面板
/// - 空白处双指捏合 / Ctrl+滚轮 → 缩放整个画布,双击空白复位
///   （选中元素时双指手势优先作用于元素本身）
/// - 选中素材本机缺失的贴纸 → 提示缺失并可替换/删除（FIX-03.3）
/// - 从素材面板长按拖入的元素落在指针位置（REQ-17.5）
///
/// 撤销/重做与历史快照由宿主（编辑页）管理：[onCommit] 在每次
/// 「一次完整操作结束」时回调（手势结束、增删、图层、面板保存）。
class CanvasEditor extends StatefulWidget {
  const CanvasEditor({
    super.key,
    required this.canvas,
    required this.entry,
    required this.onCommit,
    required this.onEditText,
    required this.onEditImage,
    required this.onEditSticker,
    required this.onEditComponent,
  });

  final JournalCanvas canvas;
  final JournalEntry entry;

  /// 一次操作完成（数据已被就地修改）：宿主推送撤销历史并刷新。
  final VoidCallback onCommit;

  /// 编辑文本 / 图片遮罩 / 贴纸属性 / 结构化组件（心情、天气等）。
  final ValueChanged<TextElement> onEditText;
  final ValueChanged<ImageElement> onEditImage;
  final ValueChanged<StickerElement> onEditSticker;
  final ValueChanged<StructuredElement> onEditComponent;

  @override
  State<CanvasEditor> createState() => CanvasEditorState();
}

class CanvasEditorState extends State<CanvasEditor> {
  String? _selectedId;

  /// 页面矩形：拖拽落点由全局坐标换算成页宽归一化坐标时用（REQ-17.5）。
  final _pageKey = GlobalKey();

  /// 画布缩放层：空白处双指缩放/平移（元素手势优先,见 CanvasZoom 注释）。
  final _zoomKey = GlobalKey<CanvasZoomState>();

  /// 空白处双击复位缩放：手工计时判定,不给点按手势引入双击延迟。
  DateTime? _lastBackgroundTap;

  CanvasElement? get _selected =>
      widget.canvas.elements.where((e) => e.id == _selectedId).firstOrNull;

  /// 当前画布缩放倍率：屏幕位移换算成页宽归一化坐标时要除以它。
  double get _zoom => _zoomKey.currentState?.scale ?? 1.0;

  void select(String? id) => setState(() => _selectedId = id);

  void clearSelection() => setState(() => _selectedId = null);

  /// 空白点按：320ms 内第二次 → 复位缩放,否则取消选中。
  void _tapBackground() {
    final now = DateTime.now();
    final last = _lastBackgroundTap;
    _lastBackgroundTap = now;
    if (last != null && now.difference(last) < const Duration(milliseconds: 320)) {
      _lastBackgroundTap = null;
      _zoomKey.currentState?.reset();
      return;
    }
    clearSelection();
  }

  // 手势起始基线（onScaleUpdate 的 scale/rotation 是相对起点的累计值）。
  double _baseW = 0,
      _baseH = 0,
      _baseRot = 0,
      _baseFont = 0;

  void _scaleStart(CanvasElement e) {
    _baseW = e.w;
    _baseH = e.h;
    _baseRot = e.rotation;
    _baseFont = e is TextElement ? e.fontScale : 0;
  }

  void _scaleUpdate(CanvasElement e, Size pageSize, ScaleUpdateDetails d) {
    // focalPointDelta 是「本帧」屏幕增量,先除以画布缩放,再按页宽归一化。
    final dx = d.focalPointDelta.dx / _zoom / pageSize.width;
    final dy = d.focalPointDelta.dy / _zoom / pageSize.width;
    // clamp 上限不得低于下限（超宽元素拉满时 1.05 - w 可为负）。
    final maxX = math.max(-0.1, 1.05 - e.w);
    final maxY = math.max(-0.05, widget.canvas.effectiveHeight - e.h + 0.1);
    e.x = (e.x + dx).clamp(-0.1, maxX);
    e.y = (e.y + dy).clamp(-0.05, maxY);

    if (d.pointerCount >= 2) {
      final s = d.scale.clamp(0.2, 5.0);
      if (e is TextElement) {
        // 文本：双指改字号,框宽不变。
        e.fontScale = (_baseFont * s).clamp(0.022, 0.09);
        e.h = math.max(e.h, measureTextHeight(e));
      } else {
        e.w = (_baseW * s).clamp(0.05, 1.2);
        e.h = (_baseH * s).clamp(0.03, 1.2);
      }
      e.rotation = (_baseRot + d.rotation * 180 / math.pi) % 360;
    }
    if (e is TextElement) {
      e.h = math.max(e.h, measureTextHeight(e));
    }
    setState(() {});
  }

  // ---------------- 图层操作 ----------------

  void bringToFront() {
    final e = _selected;
    if (e == null) return;
    widget.canvas.elements
      ..remove(e)
      ..add(e);
    _afterOp();
  }

  void sendToBack() {
    final e = _selected;
    if (e == null) return;
    widget.canvas.elements
      ..remove(e)
      ..insert(0, e);
    _afterOp();
  }

  void duplicate() {
    final e = _selected;
    if (e == null || e is StructuredElement) return;
    final copy = _cloneElement(e);
    copy
      ..x = (e.x + 0.05).clamp(0.0, 1 - copy.w)
      ..y = e.y + 0.05;
    widget.canvas.elements.add(copy);
    _selectedId = copy.id;
    _afterOp();
  }

  /// 复制一个元素：走一遍序列化省得逐类型手抄字段,去掉 id 以取得新 id
  /// （否则副本与原件同 id,选中态会落回原件）。
  CanvasElement _cloneElement(CanvasElement e) {
    final map = Map<String, Object?>.from(e.encode())..remove('id');
    return JournalCanvas.fromMap({
      'elements': [map],
      'paper': '',
    }).elements.first;
  }

  void deleteSelected() {
    final e = _selected;
    if (e == null) return;
    widget.canvas.elements.remove(e);
    _selectedId = null;
    _afterOp();
  }

  void _afterOp() {
    setState(() {});
    widget.onCommit();
  }

  // ---------------- 缺失素材（FIX-03.3） ----------------

  /// 贴纸引用的素材本机不存在时返回该元素（画布上渲染为虚线占位）。
  StickerElement? _missingSticker(CanvasElement e) =>
      e is StickerElement && !isKnownStickerKey(e.key) ? e : null;

  /// 缺失占位的说明弹窗：说清缺的是什么,并给出替换/删除两个出口。
  Future<void> _showMissingAsset(StickerElement e) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showDialog<_MissingAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('素材缺失'),
        content: Text(
          '缺少「${stickerKeyLabel(e.key)}」（${e.key}）\n'
          '本机没有这个素材，画布上以虚线占位框显示。可以换成本机已有的素材，或删掉这个元素。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () =>
                Navigator.pop(dialogContext, _MissingAction.delete),
            child: const Text('删除该元素'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _MissingAction.replace),
            child: const Text('替换为本机素材'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MissingAction.replace:
        await _replaceSticker(e);
      case _MissingAction.delete:
        deleteSelected();
    }
  }

  /// 换成本机素材：复用素材面板,只取其贴纸 key（胶带无法顶替贴纸）。
  Future<void> _replaceSticker(StickerElement e) async {
    var replaced = false;
    await showStickerPalette(
      context,
      onPick: (picked) {
        if (picked is! StickerElement) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请选一个贴纸或表情来替换')));
          return;
        }
        e.key = picked.key;
        e.tint = picked.tint;
        replaced = true;
        // 替换是一次性动作,选中即收面板（与连续插入的常驻语义区分）。
        Navigator.of(context).pop();
      },
    );
    if (!mounted || !replaced) return;
    _afterOp();
  }

  // ---------------- 拖拽放置（REQ-17.5） ----------------

  /// 素材面板拖入：[DragTargetDetails.offset] 约定为「元素中心」的全局坐标,
  /// 经页面 RenderBox 换算成页宽归一化坐标（globalToLocal 已含滚动偏移）,
  /// 落点越界时贴边收回。触摸与鼠标同一条路径,双端一致（NFR-04）。
  void _dropElement(DragTargetDetails<CanvasElement> details, double pageWidth) {
    final box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || pageWidth <= 0) return;
    final local = box.globalToLocal(details.offset);
    // 面板里的 Draggable 长期持有同一个实例,直接入列会与下次拖拽共用对象。
    final element = _cloneElement(details.data);
    element.moveTo(Offset(local.dx / pageWidth, local.dy / pageWidth));
    element
      ..x = element.x.clamp(0.0, math.max(0.0, 1 - element.w))
      ..y = element.y.clamp(
        0.0,
        math.max(0.0, widget.canvas.effectiveHeight - element.h),
      );
    widget.canvas.elements.add(element);
    _selectedId = element.id;
    _afterOp();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;
        final pageSize = Size(pageWidth, pageWidth);
        // 页面（可滚动）。
        final page = SizedBox(
          key: _pageKey,
          width: pageWidth,
          height: widget.canvas.effectiveHeight * pageWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 静态渲染层。
              Positioned.fill(
                child: CanvasView(
                  canvas: widget.canvas,
                  entry: widget.entry,
                  placeholderImages: true,
                ),
              ),
              // 点按空白处取消选中、双击复位缩放（位于元素层之下,不抢元素手势）。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _tapBackground,
                ),
              ),
              // 空白提示（标题/正文占位）。
              for (final e in widget.canvas.elements)
                if (e is TextElement && e.text.isEmpty && e.role.isNotEmpty)
                  Positioned(
                    left: e.x * pageSize.width,
                    top: e.y * pageSize.width,
                    width: e.w * pageSize.width,
                    child: IgnorePointer(
                      child: Text(
                        e.role == 'title' ? '点击输入标题…' : '点击输入正文…',
                        style: TextStyle(
                          fontSize: e.fontScale * pageSize.width,
                          height: e.lineHeight,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.45,
                          ),
                          fontFamily: e.fontFamily.isEmpty
                              ? null
                              : e.fontFamily,
                          fontWeight: e.bold
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              // 手势层：按 z 序堆叠,顶层元素优先命中。
              for (final e in widget.canvas.elements)
                _elementGesture(e, pageSize, scheme),
              // 选中框 + 角点手柄。
              if (_selected != null) _selectionBox(_selected!, pageSize),
            ],
          ),
        );

        // 操作条固定在编辑区视口底部,不随画布缩放/平移,
        // 也不会被页面级底部工具栏遮挡（EditorPage 中本组件位于其上方）。
        // 整块同时是素材面板的拖拽落区（REQ-17.5）。
        return DragTarget<CanvasElement>(
          onAcceptWithDetails: (details) => _dropElement(details, pageWidth),
          builder: (context, candidate, _) => Stack(
            children: [
              // 缩放/平移层：单指拖空白平移、双指捏合缩放、滚轮滚动、
              // Ctrl+滚轮缩放;元素手势是子级,竞技场中优先于本层。
              CanvasZoom(
                key: _zoomKey,
                childSize: Size(
                  pageWidth,
                  widget.canvas.effectiveHeight * pageWidth + 120,
                ),
                child: Padding(
                  // 底部留白给悬浮工具栏（缩放后也保证页面底部可滚出）。
                  padding: const EdgeInsets.only(bottom: 120),
                  child: page,
                ),
              ),
              // 拖拽悬停时描边,提示「松手就落在这」。
              if (candidate.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              if (_selected != null)
                _selectionToolbar(context, scheme, _selected!),
            ],
          ),
        );
      },
    );
  }

  Widget _elementGesture(CanvasElement e, Size pageSize, ColorScheme scheme) {
    final selected = e.id == _selectedId;
    final height =
        (e is TextElement ? math.max(e.h, measureTextHeight(e)) : e.h) *
        pageSize.width;

    return Positioned(
      left: e.x * pageSize.width,
      top: e.y * pageSize.width,
      width: e.w * pageSize.width,
      height: height,
      child: Transform.rotate(
        angle: e.rotation * math.pi / 180,
        child: selected
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _scaleStart(e),
                onScaleUpdate: (d) => _scaleUpdate(e, pageSize, d),
                onScaleEnd: (_) => widget.onCommit(),
                onTap: () => _tapSelected(e),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 1.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => select(e.id),
                child: ColoredBox(color: Colors.transparent),
              ),
      ),
    );
  }

  void _tapSelected(CanvasElement e) {
    // 缺失占位可点击：不进编辑面板,直接给替换/删除出口（FIX-03.3）。
    final missing = _missingSticker(e);
    if (missing != null) {
      _showMissingAsset(missing);
      return;
    }
    switch (e) {
      case TextElement():
        widget.onEditText(e);
      case ImageElement():
        widget.onEditImage(e);
      // 插入后仍可换色 / 调不透明度（REQ-19.2）。
      case StickerElement():
        widget.onEditSticker(e);
      case StructuredElement():
        widget.onEditComponent(e);
      default:
        clearSelection();
    }
  }

  /// 选中框：虚线边框（不挡点击）+ 右下角缩放手柄（随元素旋转）。
  Widget _selectionBox(CanvasElement e, Size pageSize) {
    final height =
        (e is TextElement ? math.max(e.h, measureTextHeight(e)) : e.h) *
        pageSize.width;
    return Positioned(
      left: e.x * pageSize.width,
      top: e.y * pageSize.width,
      width: e.w * pageSize.width,
      height: height,
      child: Transform.rotate(
        angle: e.rotation * math.pi / 180,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 边框仅视觉,不参与命中。
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: _ResizeHandle(
                size: 22,
                onScale: (delta) {
                  setState(() {
                    // 屏幕位移先除以画布缩放再按页宽归一化。
                    final dw = delta.dx / _zoom / pageSize.width;
                    if (e is TextElement || e is TapeElement) {
                      // 文本与胶带：手柄只调宽度。
                      e.w = (e.w + dw).clamp(0.15, 1.0);
                      if (e is TextElement) {
                        e.h = math.max(e.h, measureTextHeight(e));
                      }
                    } else {
                      final aspect = e.h / e.w;
                      e.w = (e.w + dw).clamp(0.05, 1.2);
                      e.h = (e.w * aspect).clamp(0.03, 1.2);
                    }
                  });
                },
                onDone: widget.onCommit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 选中元素的操作条：编辑 / 置顶 / 置底 / 复制 / 删除 / 完成。
  /// 固定于编辑区视口底部（见 build 注释）。
  Widget _selectionToolbar(
    BuildContext context,
    ColorScheme scheme,
    CanvasElement e,
  ) {
    final isComponent = e is StructuredElement;
    final missing = _missingSticker(e);
    return Positioned(
      left: 8,
      right: 8,
      bottom: 92,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 素材缺失时首位换成缺失入口,编辑对缺失贴纸无意义（FIX-03.3）。
              if (missing != null)
                _toolButton(
                  scheme,
                  icon: Icons.error_outline_rounded,
                  label: '素材缺失',
                  color: scheme.error,
                  onTap: () => _showMissingAsset(missing),
                )
              else
                _toolButton(
                  scheme,
                  icon: switch (e) {
                    TextElement() => Icons.edit_outlined,
                    ImageElement() => Icons.photo_filter_outlined,
                    StructuredElement() => Icons.tune_rounded,
                    _ => Icons.palette_outlined,
                  },
                  label: '编辑',
                  onTap: () => _tapSelected(e),
                ),
              _toolButton(
                scheme,
                icon: Icons.flip_to_front_rounded,
                label: '置顶',
                onTap: bringToFront,
              ),
              _toolButton(
                scheme,
                icon: Icons.flip_to_back_rounded,
                label: '置底',
                onTap: sendToBack,
              ),
              if (!isComponent)
                _toolButton(
                  scheme,
                  icon: Icons.copy_rounded,
                  label: '复制',
                  onTap: duplicate,
                ),
              _toolButton(
                scheme,
                icon: Icons.delete_outline_rounded,
                label: '删除',
                color: scheme.error,
                onTap: deleteSelected,
              ),
              const SizedBox(width: 2),
              TextButton(onPressed: clearSelection, child: const Text('完成')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color ?? scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: color ?? scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缺失素材弹窗的两个出口（FIX-03.3）。
enum _MissingAction { replace, delete }

/// 右下角缩放手柄：拖动改变元素尺寸（旋转近似处理,小角度误差可接受）。
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.size,
    required this.onScale,
    required this.onDone,
  });

  final double size;
  final void Function(Offset delta) onScale;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => onScale(d.delta),
      onPanEnd: (_) => onDone(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          Icons.zoom_out_map_rounded,
          size: size * 0.55,
          color: Colors.white,
        ),
      ),
    );
  }
}
