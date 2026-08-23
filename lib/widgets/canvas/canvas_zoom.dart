import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

/// 画布滚轮语义：滚动（编辑态,纵向平移）或缩放（查看态,像片查看器）。
/// 两种模式下 Ctrl+滚轮 都固定为缩放。
enum CanvasWheelMode { scroll, zoom }

/// 画布缩放/平移层：给编辑器与查看态提供同一套「双指缩放 + 拖动平移 +
/// 滚轮」交互（REQ：平板/电脑查看免上下滑动,编辑态空白处可双指缩放）。
///
/// - 内容按 [childSize] 的原始尺寸布局,层内做等比变换;
///   小于视口时居中,大于视口时平移被钳制在内容边界内。
/// - [fitToViewport] 为 true 时初始缩放为「整页恰好装进视口」（查看态）,
///   且不允许缩到比整页更小;为 false 时初始 1:1（编辑态）。
/// - 手势竞技场：本层是父级,子树里更深的手势（元素点选/拖拽、缩放手柄）
///   总是优先获胜 —— 因此编辑态选中元素时双指缩放作用于元素,
///   空白处（未选中）才缩放画布本身,与需求语义一致。
class CanvasZoom extends StatefulWidget {
  const CanvasZoom({
    super.key,
    required this.child,
    required this.childSize,
    this.fitToViewport = false,
    this.wheelMode = CanvasWheelMode.scroll,
    this.minScale = 0.4,
    this.maxScale = 4,
    this.doubleTapReset = false,
  });

  /// 按原始尺寸布局的内容（调用方保证其占满 [childSize]）。
  final Widget child;

  /// 内容原始尺寸（查看态为整页,编辑态为页面 + 底部工具栏留白）。
  final Size childSize;

  /// true：初始（及复位）缩放 = 整页适配视口,且为缩放下限。
  final bool fitToViewport;

  final CanvasWheelMode wheelMode;

  /// 缩放下限（仅 [fitToViewport] 为 false 时生效;适配模式以适配值为下限）。
  final double minScale;

  final double maxScale;

  /// 双击复位到初始状态。查看态无子级点按手势,可安全开启;
  /// 编辑态由宿主在空白点按时自行判定双击,不在这里开（避免点按延迟）。
  final bool doubleTapReset;

  @override
  State<CanvasZoom> createState() => CanvasZoomState();

  /// 查找最近的缩放层状态（元素手势换算屏幕位移时除以当前缩放）。
  static CanvasZoomState? of(BuildContext context) =>
      context.findAncestorStateOfType<CanvasZoomState>();
}

class CanvasZoomState extends State<CanvasZoom>
    with SingleTickerProviderStateMixin {
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;

  /// 用户是否主动缩放/平移过（视口尺寸变化时未交互过才自动复位适配）。
  bool _interacted = false;

  // 手势基线（onScaleUpdate 的 scale 是相对手势起点的累计值）。
  double _gestureScale = 1;
  Offset _gestureOffset = Offset.zero;
  Offset _gestureFocal = Offset.zero;
  bool _gestureZooming = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  ({double s, Offset t})? _animFrom;
  ({double s, Offset t})? _animTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_tick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前缩放倍率（相对内容原始尺寸）。
  double get scale => _scale;

  /// 当前平移偏移（视口坐标,已按内容边界钳制）。
  Offset get offset => _offset;

  /// 整页适配视口的基准缩放;非适配模式恒为 1。
  double get _baseScale {
    if (!widget.fitToViewport || _viewport == Size.zero) return 1;
    final s = math.min(
      _viewport.width / math.max(widget.childSize.width, 1),
      _viewport.height / math.max(widget.childSize.height, 1),
    );
    // 超大屏（小页面）也放大适配,但封顶避免极端;缩放上限随之抬高。
    return s.clamp(0.05, widget.maxScale);
  }

  double get _minScaleAllowed =>
      widget.fitToViewport ? _baseScale : widget.minScale;

  double get _maxScaleAllowed => math.max(widget.maxScale, _minScaleAllowed * 2);

  /// 平移钳制：内容某边小于视口时该轴居中,否则不出界。
  Offset _clampOffset(double s, Offset t) {
    if (_viewport == Size.zero) return t;
    final w = widget.childSize.width * s;
    final h = widget.childSize.height * s;
    final tx = w <= _viewport.width
        ? (_viewport.width - w) / 2
        : t.dx.clamp(_viewport.width - w, 0.0);
    final ty = h <= _viewport.height
        ? (_viewport.height - h) / 2
        : t.dy.clamp(_viewport.height - h, 0.0);
    return Offset(tx, ty);
  }

  void _apply(double s, Offset t) {
    _controller.stop();
    _animFrom = _animTo = null;
    setState(() {
      _scale = s.clamp(_minScaleAllowed, _maxScaleAllowed);
      _offset = _clampOffset(_scale, t);
    });
  }

  /// 动画复位到初始状态（适配模式的整页适配 / 编辑模式的 1:1）。
  void reset() {
    final s = _baseScale;
    _animateTo(s, _clampOffset(s, Offset.zero));
  }

  void _animateTo(double s, Offset t) {
    _animFrom = (s: _scale, t: _offset);
    _animTo = (
      s: s.clamp(_minScaleAllowed, _maxScaleAllowed),
      t: _clampOffset(s.clamp(_minScaleAllowed, _maxScaleAllowed), t),
    );
    _controller.forward(from: 0);
  }

  void _tick() {
    final from = _animFrom;
    final to = _animTo;
    if (from == null || to == null) return;
    final k = Curves.easeOutCubic.transform(_controller.value);
    setState(() {
      _scale = lerpDouble(from.s, to.s, k)!;
      _offset = Offset.lerp(from.t, to.t, k)!;
    });
  }

  // ---------------- 手势 ----------------

  void _onScaleStart(ScaleStartDetails d) {
    _interacted = true;
    _controller.stop();
    _animFrom = _animTo = null;
    _gestureScale = _scale;
    _gestureOffset = _offset;
    _gestureFocal = d.localFocalPoint;
    _gestureZooming = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final s = (_gestureScale * d.scale).clamp(
      _minScaleAllowed,
      _maxScaleAllowed,
    );
    if ((s - _gestureScale).abs() > 0.001) _gestureZooming = true;
    // 手势焦点下的内容点在缩放前后保持不动。
    final scene = (_gestureFocal - _gestureOffset) / _gestureScale;
    final t = d.localFocalPoint - scene * s;
    setState(() {
      _scale = s;
      _offset = _clampOffset(s, t);
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gestureZooming) return;
    // 纯平移的惯性滑动：按松手速度外推一段,再由钳制收边。
    final v = d.velocity.pixelsPerSecond;
    if (v.distance > 120) {
      _animateTo(_scale, _offset + v * 0.18);
    }
  }

  // ---------------- 滚轮 / 触控板 ----------------

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.scrollDelta == Offset.zero) return;
    _interacted = true;
    if (widget.wheelMode == CanvasWheelMode.zoom ||
        HardwareKeyboard.instance.isControlPressed) {
      _zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 200));
    } else {
      _apply(_scale, _offset - e.scrollDelta);
    }
  }

  /// 触控板双指手势：捏合（scale≠1）恒为缩放,纯平移按当前滚轮语义处理。
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    _interacted = true;
    if ((e.scale - 1).abs() > 0.001) {
      _zoomAt(e.localPosition, e.scale);
    } else if (widget.wheelMode == CanvasWheelMode.zoom ||
        HardwareKeyboard.instance.isControlPressed) {
      _zoomAt(e.localPosition, math.exp(-e.panDelta.dy / 200));
    } else {
      _apply(_scale, _offset - e.panDelta);
    }
  }

  void _zoomAt(Offset focal, double factor) {
    final s = (_scale * factor).clamp(_minScaleAllowed, _maxScaleAllowed);
    final scene = (focal - _offset) / _scale;
    _apply(s, focal - scene * s);
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vp = constraints.biggest;
        if (vp != _viewport) {
          _viewport = vp;
          // 视口变化（转屏/改窗口）后：没交互过就重新适配,交互过则收边即可。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_interacted) {
              reset();
            } else {
              _apply(_scale, _offset);
            }
          });
        }
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          child: GestureDetector(
            // opaque：保证本层始终进入命中路径（translucent 对空子级只会把
            // 自己加进结果、不会向上传导,空白区域收不到滚轮与捏合手势）;
            // 元素手势层在更深处、先进入竞技场,依然优先于本层获胜。
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTap: widget.doubleTapReset ? reset : null,
            child: ClipRect(
              child: Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                  ..scaleByDouble(_scale, _scale, _scale, 1),
                // RepaintBoundary：缩放/平移时内容层整块复用,不逐帧重画。
                child: RepaintBoundary(child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}
