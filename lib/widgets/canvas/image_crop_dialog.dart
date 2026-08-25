import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../storage/stored_files.dart';
import '../../storage/sync_read.dart';
import '../../utils/attachments.dart';
import '../../utils/env.dart';
import '../stored_image.dart';

/// 后台执行重活：正常走 isolate（compute）,测试环境（FakeAsync 不推进
/// 真实 isolate）改为当前执行器同步跑,便于 widget 测试覆盖。
Future<R> _runTask<M, R>(R Function(M) task, M arg) {
  if (isFlutterTest) {
    return Future.sync(() => task(arg));
  }
  return compute(task, arg);
}

/// 取原图字节：测试环境走同步读（FakeAsync 推不动真实异步 IO），
/// 生产环境经存储层异步读取（Web 端为 IndexedDB 键）。
Future<Uint8List?> _readBytes(String path) {
  if (isFlutterTest) return Future.value(readStoredBytesSync(path));
  return storedFiles.read(path);
}

/// 照片导入的裁剪结果：最终附件路径与像素尺寸（宽高比据此归一化到画布）。
class CroppedImage {
  const CroppedImage({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;

  /// 高宽比（页宽倍数坐标里 h = w * aspect）。
  double get aspect => height / width;
}

/// 打开「裁剪照片」对话框：默认裁剪框即整张原图（保持原比例）,
/// 可自由拖动四角调整区域。返回 null 表示放弃这张照片。
///
/// 「裁剪并添加」后台 isolate 裁剪（顺带烘掉 EXIF 方向、压长边）,
/// 结果另存为新附件文件,原中间文件由调用方决定去留。
///
/// [persist] 仅供测试注入落盘行为,默认走附件目录。
Future<CroppedImage?> showImageCropDialog(
  BuildContext context,
  String imagePath, {
  Future<String> Function(Uint8List bytes, String ext)? persist,
}) {
  return showDialog<CroppedImage>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _ImageCropDialog(path: imagePath, persist: persist),
  );
}

class _ImageCropDialog extends StatefulWidget {
  const _ImageCropDialog({required this.path, this.persist});

  final String path;
  final Future<String> Function(Uint8List bytes, String ext)? persist;

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  /// 探测（含 EXIF 方向烘平）后的原图尺寸;null 表示解码失败。
  ({int width, int height})? _natural;
  bool _failed = false;

  /// 裁剪框,原图像素坐标。初始为整图 —— 「默认保持原比例」。
  Rect _rect = Rect.zero;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final raw = await _readBytes(widget.path);
    if (raw == null) {
      if (!mounted) return;
      setState(() => _failed = true);
      return;
    }
    final result = await _runTask(_probeWorker, raw);
    if (!mounted) return;
    setState(() {
      if (result == null) {
        _failed = true;
      } else {
        _natural = result;
        _rect = Rect.fromLTWH(0, 0, result.width.toDouble(),
            result.height.toDouble());
      }
    });
  }

  Future<void> _confirm() async {
    final natural = _natural;
    if (natural == null || _busy) return;
    setState(() => _busy = true);
    final crop = Rect.fromLTRB(
      _rect.left.roundToDouble(),
      _rect.top.roundToDouble(),
      _rect.right.roundToDouble(),
      _rect.bottom.roundToDouble(),
    );
    CroppedImage? result;
    try {
      final raw = await _readBytes(widget.path);
      final cropped = raw == null ? null : await _runTask(_cropWorker, (raw, crop));
      if (cropped != null) {
        final path = widget.persist == null
            ? await Attachments.persistBytes(cropped.bytes, '.jpg')
            : await widget.persist!(cropped.bytes, '.jpg');
        result = CroppedImage(path: path, width: cropped.width,
            height: cropped.height);
      }
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    if (result == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('照片处理失败，请重试')),
      );
      return;
    }
    Navigator.of(context).pop(result);
  }

  // ---------------- 裁剪框编辑 ----------------

  /// 裁剪框最小边长（原图像素）,防止拖成一条线。
  double get _minExtent {
    final natural = _natural!;
    return math.max(48.0, math.min(natural.width, natural.height) * 0.08);
  }

  void _moveRect(Offset dPx) {
    final n = _natural!;
    setState(() {
      _rect = Rect.fromLTWH(
        (_rect.left + dPx.dx).clamp(0.0, n.width - _rect.width),
        (_rect.top + dPx.dy).clamp(0.0, n.height - _rect.height),
        _rect.width,
        _rect.height,
      );
    });
  }

  /// 四角手柄：corner 0 左上 / 1 右上 / 2 左下 / 3 右下,拉动相邻两边。
  void _resizeCorner(int corner, Offset dPx) {
    final n = _natural!;
    final min = _minExtent;
    setState(() {
      var l = _rect.left;
      var t = _rect.top;
      var r = _rect.right;
      var b = _rect.bottom;
      switch (corner) {
        case 0:
          l += dPx.dx;
          t += dPx.dy;
        case 1:
          r += dPx.dx;
          t += dPx.dy;
        case 2:
          l += dPx.dx;
          b += dPx.dy;
        case 3:
          r += dPx.dx;
          b += dPx.dy;
      }
      l = l.clamp(0.0, r - min);
      r = r.clamp(l + min, n.width.toDouble());
      t = t.clamp(0.0, b - min);
      b = b.clamp(t + min, n.height.toDouble());
      _rect = Rect.fromLTRB(l, t, r, b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: math.min(40, MediaQuery.sizeOf(context).width * 0.06),
        vertical: 24,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '裁剪照片',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    _natural == null
                        ? ''
                        : '${_rect.width.round()} × ${_rect.height.round()}'
                          ' / ${_natural!.width} × ${_natural!.height}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(child: _buildArea(scheme)),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy || _failed ? null : _confirm,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('裁剪并添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArea(ColorScheme scheme) {
    if (_failed) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        child: Text(
          '这张图片无法读取，请换一张试试',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final natural = _natural;
    if (natural == null) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 手柄 28×28、以角点为中心,默认整图框时恰有一半悬在图片区外;
    // Stack 只命中自身边界内,故四周预留半柄宽,保证整块手柄可命中。
    const handlePad = 14.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        // 图片在区域内完整显示（contain）,显示坐标与像素坐标按此换算。
        final disp = math.min(
          (area.width - handlePad * 2) / natural.width,
          (area.height - handlePad * 2) / natural.height,
        );
        final imgW = natural.width * disp;
        final imgH = natural.height * disp;
        return SizedBox(
          width: imgW + handlePad * 2,
          height: imgH + handlePad * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: handlePad,
                top: handlePad,
                width: imgW,
                height: imgH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: storedImageProvider(widget.path),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => Container(
                        color: scheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Text(
                          '预览不可用',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                          rect: _rect,
                          scale: disp,
                          color: scheme,
                        ),
                      ),
                    ),
                    // 整框拖动（手柄在更外层、先进入竞技场,不会被覆盖）。
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) => _moveRect(d.delta / disp),
                      child: const SizedBox.expand(),
                    ),
                  ],
                ),
              ),
              for (final (i, corner) in _corners(_rect, disp).indexed)
                Positioned(
                  key: ValueKey('crop_handle_$i'),
                  left: handlePad + corner.dx - 14,
                  top: handlePad + corner.dy - 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => _resizeCorner(i, d.delta / disp),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: scheme.primary,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 四角手柄的显示坐标。
  List<Offset> _corners(Rect r, double disp) => [
        r.topLeft * disp,
        r.topRight * disp,
        r.bottomLeft * disp,
        r.bottomRight * disp,
  ];
}

/// 裁剪框遮罩：框外压暗,框内九宫格参考线。
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.rect,
    required this.scale,
    required this.color,
  });

  final Rect rect;
  final double scale;
  final ColorScheme color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.left * scale,
      rect.top * scale,
      rect.width * scale,
      rect.height * scale,
    );
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.45);
    // 框外压暗：整块区域与裁剪框做奇偶填充差集。
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final i in [1, 2]) {
      canvas.drawLine(
        Offset(r.left + r.width * i / 3, r.top),
        Offset(r.left + r.width * i / 3, r.bottom),
        line,
      );
      canvas.drawLine(
        Offset(r.left, r.top + r.height * i / 3),
        Offset(r.right, r.top + r.height * i / 3),
        line,
      );
    }
    final border = Paint()
      ..color = color.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(r, border);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.rect != rect || old.scale != scale;
}

// ---------------- 后台 isolate ----------------

/// 读取图片显示尺寸：解码后烘平 EXIF 方向（与引擎显示一致）,只取宽高。
({int width, int height})? _probeWorker(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    return (width: oriented.width, height: oriented.height);
  } catch (_) {
    return null;
  }
}

/// 裁剪并重编码为 JPEG：烘平 EXIF 方向后按像素矩形裁剪,长边压到
/// 2560 以内控制内存与体积。任何一步失败返回 null（调用方回退原图）。
({Uint8List bytes, int width, int height})? _cropWorker(
  (Uint8List, Rect) job,
) {
  try {
    final decoded = img.decodeImage(job.$1);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final rect = job.$2;
    var cropped = img.copyCrop(
      oriented,
      x: rect.left.round().clamp(0, oriented.width - 1),
      y: rect.top.round().clamp(0, oriented.height - 1),
      width: rect.width.round().clamp(1, oriented.width),
      height: rect.height.round().clamp(1, oriented.height),
    );
    const maxSide = 2560;
    final longSide = math.max(cropped.width, cropped.height);
    if (longSide > maxSide) {
      final k = maxSide / longSide;
      cropped = img.copyResize(
        cropped,
        width: math.max(1, (cropped.width * k).round()),
        height: math.max(1, (cropped.height * k).round()),
      );
    }
    return (
      bytes: img.encodeJpg(cropped, quality: 88),
      width: cropped.width,
      height: cropped.height,
    );
  } catch (_) {
    return null;
  }
}
