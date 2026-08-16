import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_page.dart';
import '../../models/journal_entry.dart';
import 'canvas_view.dart';

/// 画布编辑层（调研二/三阶段）：静态渲染之上叠加手势与选择态。
///
/// 交互（手势替代滑杆）：
/// - 单指点按未选中元素 → 选中；点空白 → 取消选中
/// - 选中后单指拖动 → 移动；双指捏合 → 缩放 + 旋转
/// - 角点手柄拖动 → 单指调整大小（文本/胶带调宽,其余等比缩放）
/// - 再次点按已选中的文本/图片/组件 → 打开对应编辑面板
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
    required this.onEditComponent,
  });

  final JournalCanvas canvas;
  final JournalEntry entry;

  /// 一次操作完成（数据已被就地修改）：宿主推送撤销历史并刷新。
  final VoidCallback onCommit;

  /// 编辑文本 / 图片遮罩 / 结构化组件（心情、天气等）。
  final ValueChanged<TextElement> onEditText;
  final ValueChanged<ImageElement> onEditImage;
  final ValueChanged<StructuredElement> onEditComponent;

  @override
  State<CanvasEditor> createState() => CanvasEditorState();
}

class CanvasEditorState extends State<CanvasEditor> {
  String? _selectedId;

  CanvasElement? get _selected =>
      widget.canvas.elements.where((e) => e.id == _selectedId).firstOrNull;

  void select(String? id) => setState(() => _selectedId = id);

  void clearSelection() => setState(() => _selectedId = null);

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
    // focalPointDelta 是「本帧」增量,须累加到当前位置（基线仅用于
    // 双指缩放的 scale/rotation 等相对起点的累计值）。
    final dx = d.focalPointDelta.dx / pageSize.width;
    final dy = d.focalPointDelta.dy / pageSize.width;
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
    final copy = JournalCanvas.fromMap({
      'elements': [e.encode()],
      'paper': '',
    }).elements.first;
    copy
      ..x = (e.x + 0.05).clamp(0.0, 1 - copy.w)
      ..y = e.y + 0.05;
    widget.canvas.elements.add(copy);
    _selectedId = copy.id;
    _afterOp();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;
        final pageSize = Size(pageWidth, pageWidth);
        // 页面（可滚动）。
        final page = SizedBox(
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
              // 点按空白处取消选中（位于元素层之下,不抢元素手势）。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: clearSelection,
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

        // 操作条固定在编辑区视口底部,不随页面滚动,
        // 也不会被页面级底部工具栏遮挡（EditorPage 中本组件位于其上方）。
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: page,
            ),
            if (_selected != null)
              _selectionToolbar(context, scheme, _selected!),
          ],
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
    switch (e) {
      case TextElement():
        widget.onEditText(e);
      case ImageElement():
        widget.onEditImage(e);
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
                    if (e is TextElement || e is TapeElement) {
                      // 文本与胶带：手柄只调宽度。
                      e.w = (e.w + delta.dx / pageSize.width).clamp(0.15, 1.0);
                      if (e is TextElement) {
                        e.h = math.max(e.h, measureTextHeight(e));
                      }
                    } else {
                      final dw = delta.dx / pageSize.width;
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
