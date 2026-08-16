import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 手账贴纸（REQ-13 轻量版）：emoji + 归一化位置（0–1）+ 缩放 + 旋转角。
/// 位置相对所在页面（编辑区 / 分享卡）记录，导出与编辑保持同构。
class Sticker {
  Sticker({
    required this.emoji,
    this.dx = 0.5,
    this.dy = 0.5,
    this.scale = 1,
    this.rotation = 0,
  });

  final String emoji;

  /// 相对页面宽度的水平位置（0–1）。
  double dx;

  /// 相对页面高度的垂直位置（0–1）。
  double dy;

  /// 缩放倍数（0.5–2.5）。
  double scale;

  /// 旋转角度（度，-180–180）。
  double rotation;

  Map<String, Object?> toMap() => {
    'e': emoji,
    'x': dx,
    'y': dy,
    's': scale,
    'r': rotation,
  };

  static Sticker fromMap(Map<Object?, Object?> map) => Sticker(
    emoji: (map['e'] ?? '') as String,
    dx: _toDouble(map['x'], 0.5),
    dy: _toDouble(map['y'], 0.5),
    scale: _toDouble(map['s'], 1).clamp(0.5, 3),
    rotation: _toDouble(map['r'], 0).clamp(-180, 180),
  );

  static double _toDouble(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}

/// 贴纸列表序列化（entries.stickers 列,JSON 数组;空列表存空串）。
String encodeStickers(List<Sticker> stickers) =>
    stickers.isEmpty ? '' : jsonEncode([for (final s in stickers) s.toMap()]);

/// 反序列化：损坏数据静默退化为空列表，不影响条目打开。
List<Sticker> decodeStickers(String raw) {
  if (raw.trim().isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return [
      for (final item in list)
        if (item is Map && item['e'] is String && (item['e'] as String).isNotEmpty)
          Sticker.fromMap(item.cast<String, Object?>()),
    ];
  } catch (_) {
    return [];
  }
}

/// 纸张底色种类（调研一阶段：纹理之外新增纯色与柔和渐变）。
enum PaperKind { texture, solid, gradient }

/// 纸张样式（REQ-13：≥8 款程序绘制的纹理,不引入图片资源）。
class PaperStyle {
  const PaperStyle(
    this.id,
    this.name,
    this.base,
    this.ink, {
    this.density = 1,
    this.kind = PaperKind.texture,
    this.end,
  });

  final String id;
  final String name;

  /// 纸张底色（渐变纸为起始色）。
  final Color base;

  /// 纹理墨色。
  final Color ink;

  /// 纹理疏密系数（1 为标准）。
  final double density;

  final PaperKind kind;

  /// 渐变终止色（仅 [PaperKind.gradient]）。
  final Color? end;

  bool get isPlain => id == 'plain';
}

/// 内置纸张库：9 款纹理 + 8 款纯色 + 5 款柔和渐变。
const List<PaperStyle> paperStyles = [
  // ---- 纹理 ----
  PaperStyle('plain', '素笺', Color(0xFFFDFBF5), Color(0x00000000)),
  PaperStyle('dots', '云点', Color(0xFFFDF8EF), Color(0x1A8A7B6C), density: 1),
  PaperStyle('grid', '方格', Color(0xFFF9FAF6), Color(0x142F6C5A), density: 1),
  PaperStyle('lines', '横线', Color(0xFFFDFBF4), Color(0x16805C3E)),
  PaperStyle('waves', '波纹', Color(0xFFF3F8FA), Color(0x164C7FA6)),
  PaperStyle('cross', '十字', Color(0xFFFBF7F2), Color(0x16907850)),
  PaperStyle('stars', '星屑', Color(0xFFF9F6FD), Color(0x246B5EA7)),
  PaperStyle('petals', '花笺', Color(0xFFFEF6F3), Color(0x26C46A6B)),
  PaperStyle('hearts', '心语', Color(0xFFFEF5F2), Color(0x26C46A6B)),
  // ---- 纯色 ----
  PaperStyle('cream', '奶白', Color(0xFFFFFDF6), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('sakura', '樱粉', Color(0xFFFDEFF2), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('mint', '薄荷', Color(0xFFEDF7F0), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('sky', '天青', Color(0xFFEAF3F8), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('butter', '奶油黄', Color(0xFFFFF6DF), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('lilac', '香芋紫', Color(0xFFF4EFFA), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('clay', '陶土', Color(0xFFF6EDE6), Color(0x00000000), kind: PaperKind.solid),
  PaperStyle('inkstone', '夜墨', Color(0xFF2E2B27), Color(0x00000000), kind: PaperKind.solid),
  // ---- 柔和渐变 ----
  PaperStyle('mist', '晨雾', Color(0xFFFDFBF5), Color(0x00000000), kind: PaperKind.gradient, end: Color(0xFFEFE8FA)),
  PaperStyle('sunset', '落日', Color(0xFFFFF3E9), Color(0x00000000), kind: PaperKind.gradient, end: Color(0xFFFFDDD2)),
  PaperStyle('ocean', '海空', Color(0xFFEAF6F8), Color(0x00000000), kind: PaperKind.gradient, end: Color(0xFFDCE9F4)),
  PaperStyle('spring', '春野', Color(0xFFF0F7EC), Color(0x00000000), kind: PaperKind.gradient, end: Color(0xFFFBF4E4)),
  PaperStyle('blossom', '樱雪', Color(0xFFFFF0F3), Color(0x00000000), kind: PaperKind.gradient, end: Color(0xFFFDF9F3)),
];

/// 按 id 查纸张;未设置（空串）或未知 id 返回 null（不装饰）。
PaperStyle? paperById(String id) {
  if (id.isEmpty) return null;
  for (final p in paperStyles) {
    if (p.id == id) return p;
  }
  return null;
}

/// 解析纸张底色（深色主题下加深,保证浅色正文文字可读）。
/// 「夜墨」本为深色纸,深色主题下保持原样。
Color resolvePaperBase(PaperStyle paper, {bool dark = false}) {
  if (paper.id == 'inkstone') return paper.base;
  return dark ? Color.lerp(paper.base, const Color(0xFF221D18), 0.82)! : paper.base;
}

/// 解析纸张渐变终止色（无渐变返回 null;深色下同步加深）。
Color? resolvePaperEnd(PaperStyle paper, {bool dark = false}) {
  final end = paper.end;
  if (end == null) return null;
  if (paper.id == 'inkstone') return end;
  return dark ? Color.lerp(end, const Color(0xFF221D18), 0.82)! : end;
}

/// 纸张纹理画笔：底色 + 按 id 程序绘制的图案。
/// 纹理位置由固定种子的伪随机序列决定,同一样式每次绘制结果一致。
/// 分享长图导出恒用浅色([dark] 为 false);深色主题下将纸张调暗保证正文可读。
class PaperPainter extends CustomPainter {
  PaperPainter(this.paper, {this.dark = false});

  final PaperStyle paper;
  final bool dark;

  late final Color _base = resolvePaperBase(paper, dark: dark);

  /// 深色下纹理向浅色偏移,保持可见。
  late final Color _ink = dark
      ? Color.lerp(paper.ink, const Color(0x80FFFFFF), 0.75)!
      : paper.ink;

  @override
  void paint(Canvas canvas, Size size) {
    // 渐变纸：左上到右下的柔和渐变底。
    if (paper.kind == PaperKind.gradient) {
      final end = resolvePaperEnd(paper, dark: dark) ?? _base;
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_base, end],
          ).createShader(rect),
      );
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = _base);
    if (paper.isPlain || paper.kind != PaperKind.texture || size.isEmpty) return;
    final paint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    switch (paper.id) {
      case 'dots':
        _dots(canvas, size, paint);
      case 'grid':
        _grid(canvas, size, paint);
      case 'lines':
        _lines(canvas, size, paint);
      case 'waves':
        _waves(canvas, size, paint);
      case 'cross':
        _cross(canvas, size, paint);
      case 'stars':
        _scatter(canvas, size, paint, _drawStar);
      case 'petals':
        _scatter(canvas, size, paint, _drawFlower);
      case 'hearts':
        _scatter(canvas, size, paint, _drawHeart);
    }
  }

  // 规则点阵：步长 26 的圆点。
  void _dots(Canvas canvas, Size size, Paint paint) {
    const step = 26.0;
    final fill = Paint()..color = _ink;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.6, fill);
      }
    }
  }

  // 方格纸：22px 网格。
  void _grid(Canvas canvas, Size size, Paint paint) {
    const step = 22.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  // 横线信纸：每 26px 一条,顶部留白。
  void _lines(Canvas canvas, Size size, Paint paint) {
    const step = 26.0;
    for (var y = step; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  // 波纹：间隔 34px 的正弦线。
  void _waves(Canvas canvas, Size size, Paint paint) {
    const rowStep = 34.0;
    const waveLength = 56.0;
    const amplitude = 4.0;
    final path = Path();
    for (var y = rowStep / 2; y < size.height + rowStep; y += rowStep) {
      path.moveTo(0, y);
      var x = 0.0;
      while (x < size.width) {
        path.quadraticBezierTo(
          x + waveLength / 4,
          y - amplitude,
          x + waveLength / 2,
          y,
        );
        path.quadraticBezierTo(
          x + waveLength * 3 / 4,
          y + amplitude,
          x + waveLength,
          y,
        );
        x += waveLength;
      }
    }
    canvas.drawPath(path, paint..strokeWidth = 1.1);
  }

  // 十字点阵：小「+」。
  void _cross(Canvas canvas, Size size, Paint paint) {
    const step = 30.0;
    const arm = 3.0;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), paint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), paint);
      }
    }
  }

  // 散布图案：固定种子 LCG,保证纹理稳定不闪烁。
  void _scatter(
    Canvas canvas,
    Size size,
    Paint paint,
    void Function(Canvas, Offset, double, Paint) draw,
  ) {
    final rand = _SeededRandom(paper.id.hashCode);
    const step = 64.0;
    for (var gx = 0.0; gx < size.width + step; gx += step) {
      for (var gy = 0.0; gy < size.height + step; gy += step) {
        final x = gx + rand.nextDouble() * step;
        final y = gy + rand.nextDouble() * step;
        if (x > size.width || y > size.height) continue;
        draw(canvas, Offset(x, y), 3 + rand.nextDouble() * 4, paint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // 五瓣小花：五个圆弧花瓣 + 花心。
  void _drawFlower(Canvas canvas, Offset center, double r, Paint paint) {
    final petal = Paint()..color = _ink;
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      canvas.drawCircle(
        center + Offset(r * 0.7 * math.cos(angle), r * 0.7 * math.sin(angle)),
        r * 0.5,
        petal,
      );
    }
    canvas.drawCircle(center, r * 0.35, petal);
  }

  // 心形：两段二次贝塞尔。
  void _drawHeart(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy + r)
      ..cubicTo(
        center.dx - r * 1.6,
        center.dy - r * 0.4,
        center.dx - r * 0.7,
        center.dy - r * 1.4,
        center.dx,
        center.dy - r * 0.5,
      )
      ..cubicTo(
        center.dx + r * 0.7,
        center.dy - r * 1.4,
        center.dx + r * 1.6,
        center.dy - r * 0.4,
        center.dx,
        center.dy + r,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) =>
      oldDelegate.paper.id != paper.id || oldDelegate.dark != dark;
}

/// 固定种子伪随机（LCG）:纸张散布纹理所用。
class _SeededRandom {
  _SeededRandom(int seed) : _state = (seed & 0x7fffffff) + 1;

  int _state;

  double nextDouble() {
    // Numerical Recipes 常数,保证周期与分布稳定。
    _state = (0x41C64E6D * _state + 0x3039) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}

/// 贴纸可用 emoji 面板（REQ-13 轻量版,内置一组手账常用贴纸）。
const List<String> stickerPalette = [
  '🌸',
  '🌷',
  '🌻',
  '🍀',
  '🪴',
  '🍂',
  '🌈',
  '☁️',
  '🌙',
  '⭐️',
  '✨',
  '❤️',
  '💛',
  '🎀',
  '🧸',
  '☕️',
  '🍰',
  '🍒',
  '🍉',
  '🍬',
  '🐱',
  '🦋',
  '🕊️',
  '📖',
  '📚',
  '🎧',
  '🕯️',
  '📎',
  '✏️',
  '💡',
];

/// 贴纸基础字号(编辑与导出共用,保持视觉一致)。
const stickerBaseFontSize = 34.0;
