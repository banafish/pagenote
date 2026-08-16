import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 内置矢量贴纸素材库（调研一阶段「素材升级」）。
/// 全部为程序绘制的矢量图形：免抠、无版权成本、任意缩放不糊，
/// 延续本项目「零图片资产」的离线免费定位。
/// 坐标系：每个贴纸在 100×100 逻辑画布内绘制，渲染时缩放至元素框。

class StickerAsset {
  const StickerAsset(this.id, this.category, this.name);

  /// 唯一 id（存入 StickerElement.key 的 `vec:<id>` 部分）。
  final String id;

  /// 分类：自然 / 美食 / 生活 / 可爱。
  final String category;

  /// 素材面板中的名称。
  final String name;
}

/// 贴纸分类顺序（面板 tab 顺序）。
const stickerCategories = ['自然', '美食', '生活', '可爱'];

const List<StickerAsset> vectorStickers = [
  // ---- 自然 ----
  StickerAsset('flower', '自然', '小花'),
  StickerAsset('sun', '自然', '太阳'),
  StickerAsset('moon', '自然', '月亮'),
  StickerAsset('cloud', '自然', '云朵'),
  StickerAsset('rainbow', '自然', '彩虹'),
  StickerAsset('star', '自然', '星星'),
  StickerAsset('leaf', '自然', '叶子'),
  StickerAsset('clover', '自然', '四叶草'),
  // ---- 美食 ----
  StickerAsset('coffee', '美食', '咖啡'),
  StickerAsset('cake', '美食', '蛋糕'),
  StickerAsset('icecream', '美食', '冰淇淋'),
  StickerAsset('cherry', '美食', '樱桃'),
  StickerAsset('strawberry', '美食', '草莓'),
  StickerAsset('watermelon', '美食', '西瓜'),
  StickerAsset('candy', '美食', '糖果'),
  StickerAsset('donut', '美食', '甜甜圈'),
  // ---- 生活 ----
  StickerAsset('book', '生活', '书本'),
  StickerAsset('camera', '生活', '相机'),
  StickerAsset('mail', '生活', '信件'),
  StickerAsset('gift', '生活', '礼物'),
  StickerAsset('bow', '生活', '蝴蝶结'),
  StickerAsset('candle', '生活', '蜡烛'),
  StickerAsset('music', '生活', '音乐'),
  StickerAsset('mug', '生活', '热茶'),
  // ---- 可爱 ----
  StickerAsset('cat', '可爱', '猫咪'),
  StickerAsset('butterfly', '可爱', '蝴蝶'),
  StickerAsset('bird', '可爱', '小鸟'),
  StickerAsset('bear', '可爱', '小熊'),
  StickerAsset('heart', '可爱', '爱心'),
  StickerAsset('smiley', '可爱', '笑脸'),
  StickerAsset('balloon', '可爱', '气球'),
  StickerAsset('flag', '可爱', '小旗'),
];

StickerAsset? stickerById(String id) =>
    vectorStickers.where((s) => s.id == id).firstOrNull;

/// 素材面板主色调（贴纸面板底色）。
const stickerPaletteColors = [
  Color(0xFFF4A9A0), // 粉
  Color(0xFFF6C94A), // 黄
  Color(0xFF9CCB8B), // 绿
  Color(0xFF8FC1E3), // 蓝
  Color(0xFFB8A4DB), // 紫
  Color(0xFFE8837A), // 红橙
];

/// 胶带纹样。
class TapeStyle {
  const TapeStyle(this.id, this.name);
  final String id;
  final String name;
}

const List<TapeStyle> tapeStyles = [
  TapeStyle('stripes', '条纹'),
  TapeStyle('dots', '波点'),
  TapeStyle('grid', '格纹'),
  TapeStyle('hearts', '爱心'),
  TapeStyle('waves', '波浪'),
  TapeStyle('cross', '十字'),
];

TapeStyle? tapeStyleById(String id) =>
    tapeStyles.where((t) => t.id == id).firstOrNull;

/// 胶带可选底色（半透明质感由绘制端统一处理）。
const tapePalette = [
  0xFFF4A9A0, // 樱粉
  0xFFF6C94A, // 奶油黄
  0xFF9CCB8B, // 抹茶
  0xFF8FC1E3, // 雾蓝
  0xFFB8A4DB, // 香芋紫
  0xFFE8CBB0, // 原木
];

/// 矢量贴纸画笔：按 id 分发到具体绘制函数。
class StickerPainter extends CustomPainter {
  const StickerPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = switch (id) {
      'flower' => _flower,
      'sun' => _sun,
      'moon' => _moon,
      'cloud' => _cloud,
      'rainbow' => _rainbow,
      'star' => _star,
      'leaf' => _leaf,
      'clover' => _clover,
      'coffee' => _coffee,
      'cake' => _cake,
      'icecream' => _icecream,
      'cherry' => _cherry,
      'strawberry' => _strawberry,
      'watermelon' => _watermelon,
      'candy' => _candy,
      'donut' => _donut,
      'book' => _book,
      'camera' => _camera,
      'mail' => _mail,
      'gift' => _gift,
      'bow' => _bow,
      'candle' => _candle,
      'music' => _music,
      'mug' => _mug,
      'cat' => _cat,
      'butterfly' => _butterfly,
      'bird' => _bird,
      'bear' => _bear,
      'heart' => _heart,
      'smiley' => _smiley,
      'balloon' => _balloon,
      'flag' => _flag,
      _ => _star,
    };
    // 统一缩放：素材绘制在 100×100 逻辑画布。
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    painter(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StickerPainter oldDelegate) =>
      oldDelegate.id != id;
}

// ---------------------------------------------------------------------------
// 素材配色
// ---------------------------------------------------------------------------
const _ink = Color(0xFF6B5A48);
const _pink = Color(0xFFF4A9A0);
const _rose = Color(0xFFE8837A);
const _yellow = Color(0xFFF6C94A);
const _orange = Color(0xFFF2A65A);
const _green = Color(0xFF9CCB8B);
const _deepGreen = Color(0xFF6FA85F);
const _blue = Color(0xFF8FC1E3);
const _deepBlue = Color(0xFF5E97D3);
const _purple = Color(0xFFB8A4DB);
const _brown = Color(0xFFA98467);
const _cream = Color(0xFFFFF6E9);
const _red = Color(0xFFE57373);
const _white = Color(0xFFFFFFFF);

Paint _p(Color color, {bool stroke = false, double width = 3}) => Paint()
  ..color = color
  ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..isAntiAlias = true;

void _circle(Canvas c, Offset center, double r, Paint p) =>
    c.drawCircle(center, r, p);

Path _heartPath(Offset center, double r) => Path()
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

Path _starPath(Offset center, double r, {int points = 5}) {
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final radius = i.isEven ? r : r * 0.45;
    final angle = -math.pi / 2 + i * math.pi / points;
    final p = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// 自然
// ---------------------------------------------------------------------------

void _flower(Canvas c) {
  const center = Offset(50, 52);
  for (var i = 0; i < 6; i++) {
    final angle = -math.pi / 2 + i * math.pi / 3;
    _circle(
      c,
      center + Offset(17 * math.cos(angle), 17 * math.sin(angle)),
      13,
      _p(_pink),
    );
  }
  _circle(c, center, 10, _p(_yellow));
  _circle(c, center, 10, _p(_ink, stroke: true, width: 2));
}

void _sun(Canvas c) {
  _circle(c, const Offset(50, 50), 20, _p(_yellow));
  _circle(c, const Offset(50, 50), 20, _p(_orange, stroke: true, width: 2.5));
  final ray = _p(_orange, stroke: true, width: 3.5);
  for (var i = 0; i < 8; i++) {
    final angle = i * math.pi / 4;
    c.drawLine(
      const Offset(50, 50) + Offset(27 * math.cos(angle), 27 * math.sin(angle)),
      const Offset(50, 50) + Offset(36 * math.cos(angle), 36 * math.sin(angle)),
      ray,
    );
  }
}

void _moon(Canvas c) {
  final path = Path()
    ..moveTo(58, 22)
    ..arcToPoint(const Offset(58, 78), radius: const Radius.circular(32))
    ..arcToPoint(const Offset(58, 22), radius: const Radius.circular(13), clockwise: false)
    ..close();
  c.drawPath(path, _p(_yellow));
  c.drawPath(path, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(38, 42), 3, _p(_ink));
  _circle(c, const Offset(35, 58), 2.2, _p(_ink));
}

void _cloud(Canvas c) {
  final path = Path()
    ..moveTo(24, 66)
    ..cubicTo(10, 66, 12, 48, 26, 50)
    ..cubicTo(28, 36, 50, 34, 55, 46)
    ..cubicTo(70, 40, 80, 54, 70, 62)
    ..cubicTo(74, 70, 64, 76, 58, 70)
    ..close();
  c.drawPath(path, _p(_blue));
  c.drawPath(path, _p(_ink, stroke: true, width: 2));
}

void _rainbow(Canvas c) {
  final colors = [_rose, _yellow, _green, _blue];
  for (var i = 0; i < colors.length; i++) {
    c.drawArc(
      Rect.fromCircle(center: const Offset(50, 72), radius: 38 - i * 9),
      math.pi,
      math.pi,
      false,
      _p(colors[i], stroke: true, width: 7),
    );
  }
  _circle(c, const Offset(16, 72), 5, _p(_white));
  _circle(c, const Offset(84, 72), 5, _p(_white));
}

void _star(Canvas c) {
  c.drawPath(_starPath(const Offset(50, 50), 36), _p(_yellow));
  c.drawPath(_starPath(const Offset(50, 50), 36), _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(44, 45), 2.5, _p(_ink));
  _circle(c, const Offset(56, 45), 2.5, _p(_ink));
}

void _leaf(Canvas c) {
  final path = Path()
    ..moveTo(50, 12)
    ..quadraticBezierTo(84, 40, 50, 88)
    ..quadraticBezierTo(16, 40, 50, 12)
    ..close();
  c.drawPath(path, _p(_green));
  c.drawPath(path, _p(_deepGreen, stroke: true, width: 2));
  final vein = _p(_deepGreen, stroke: true, width: 2.5);
  c.drawLine(const Offset(50, 20), const Offset(50, 82), vein);
  for (var i = 1; i <= 3; i++) {
    c.drawLine(Offset(50, 24 + i * 16), Offset(50 - 16 + i * 2, 14 + i * 18), vein);
    c.drawLine(Offset(50, 24 + i * 16), Offset(50 + 16 - i * 2, 14 + i * 18), vein);
  }
}

void _clover(Canvas c) {
  const center = Offset(50, 44);
  for (var i = 0; i < 4; i++) {
    final angle = math.pi / 4 + i * math.pi / 2;
    _circle(
      c,
      center + Offset(15 * math.cos(angle), 15 * math.sin(angle)),
      15,
      _p(_green),
    );
  }
  c.drawLine(const Offset(50, 62), const Offset(50, 90), _p(_deepGreen, stroke: true, width: 4));
  c.drawLine(const Offset(50, 74), const Offset(64, 64), _p(_deepGreen, stroke: true, width: 3));
}

// ---------------------------------------------------------------------------
// 美食
// ---------------------------------------------------------------------------

void _coffee(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 34, 74, 82), const Radius.circular(8)),
    _p(_cream),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 34, 74, 82), const Radius.circular(8)),
    _p(_brown, stroke: true, width: 2.5),
  );
  c.drawArc(
    const Rect.fromLTRB(70, 44, 88, 64),
    -math.pi / 2,
    math.pi,
    false,
    _p(_brown, stroke: true, width: 3.5),
  );
  c.drawLine(const Offset(22, 44), const Offset(74, 44), _p(_brown, stroke: true, width: 2));
  final steam = _p(_ink, stroke: true, width: 2.5);
  for (final dx in [38, 50, 62]) {
    c.drawLine(Offset(dx + 0.0, 26), Offset(dx + 4.0, 12), steam);
  }
}

void _cake(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 48, 78, 84), const Radius.circular(7)),
    _p(_pink),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 48, 78, 84), const Radius.circular(7)),
    _p(_ink, stroke: true, width: 2.2),
  );
  c.drawLine(const Offset(22, 62), const Offset(78, 62), _p(_white, stroke: true, width: 6));
  _circle(c, const Offset(50, 36), 6, _p(_red));
  c.drawRect(const Rect.fromLTRB(48, 20, 52, 34), _p(_orange));
  final flame = Path()
    ..moveTo(50, 10)
    ..quadraticBezierTo(58, 18, 50, 24)
    ..quadraticBezierTo(42, 18, 50, 10);
  c.drawPath(flame, _p(_yellow));
}

void _icecream(Canvas c) {
  final cone = Path()
    ..moveTo(30, 52)
    ..lineTo(70, 52)
    ..lineTo(50, 92)
    ..close();
  c.drawPath(cone, _p(_orange));
  c.drawPath(cone, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(50, 44), 20, _p(_cream));
  _circle(c, const Offset(38, 34), 13, _p(_pink));
  _circle(c, const Offset(62, 34), 13, _p(_green));
  _circle(c, const Offset(50, 22), 12, _p(_purple));
  c.drawArc(
    const Rect.fromLTRB(28, 46, 72, 62),
    0,
    math.pi,
    false,
    _p(_red, stroke: true, width: 3),
  );
}

void _cherry(Canvas c) {
  _circle(c, const Offset(36, 66), 15, _p(_red));
  _circle(c, const Offset(64, 70), 13, _p(_red));
  final stem = _p(_deepGreen, stroke: true, width: 3);
  c.drawLine(const Offset(38, 54), const Offset(54, 22), stem);
  c.drawLine(const Offset(63, 58), const Offset(54, 22), stem);
  _circle(c, const Offset(31, 61), 4, _p(_white));
}

void _strawberry(Canvas c) {
  final body = Path()
    ..moveTo(50, 88)
    ..cubicTo(18, 68, 22, 34, 50, 34)
    ..cubicTo(78, 34, 82, 68, 50, 88)
    ..close();
  c.drawPath(body, _p(_red));
  c.drawPath(body, _p(_ink, stroke: true, width: 2));
  for (final p in [
    const Offset(38, 54),
    const Offset(62, 54),
    const Offset(50, 68),
    const Offset(42, 72),
    const Offset(58, 72),
  ]) {
    c.drawLine(p - const Offset(2.5, 2.5), p + const Offset(2.5, 2.5), _p(_yellow, stroke: true, width: 2.5));
  }
  for (var i = 0; i < 3; i++) {
    c.drawArc(
      Rect.fromCircle(center: Offset(50, 30), radius: 22),
      math.pi + i * 0.5,
      0.45,
      false,
      _p(_green, stroke: true, width: 5),
    );
  }
}

void _watermelon(Canvas c) {
  c.drawArc(const Rect.fromLTRB(12, 20, 88, 96), math.pi, math.pi, true, _p(_green));
  c.drawArc(const Rect.fromLTRB(20, 28, 80, 88), math.pi, math.pi, true, _p(_white));
  c.drawArc(const Rect.fromLTRB(24, 32, 76, 84), math.pi, math.pi, true, _p(_red));
  for (final p in [
    const Offset(34, 64),
    const Offset(50, 74),
    const Offset(66, 64),
    const Offset(42, 82),
    const Offset(58, 82),
  ]) {
    _circle(c, p, 1.8, _p(_ink));
  }
}

void _candy(Canvas c) {
  c.drawOval(const Rect.fromLTRB(28, 36, 72, 64), _p(_pink));
  c.drawOval(const Rect.fromLTRB(28, 36, 72, 64), _p(_ink, stroke: true, width: 2));
  final wrap = _p(_rose, stroke: true, width: 3);
  c.drawLine(const Offset(28, 42), const Offset(10, 30), wrap);
  c.drawLine(const Offset(28, 58), const Offset(10, 70), wrap);
  c.drawLine(const Offset(72, 42), const Offset(90, 30), wrap);
  c.drawLine(const Offset(72, 58), const Offset(90, 70), wrap);
  c.drawArc(const Rect.fromLTRB(38, 42, 50, 52), 0, math.pi * 2, false, _p(_white, stroke: true, width: 3));
}

void _donut(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_orange));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2));
  c.drawArc(const Rect.fromLTRB(16, 16, 84, 84), math.pi, math.pi, true, _p(_pink));
  _circle(c, const Offset(50, 50), 12, _p(_cream));
  _circle(c, const Offset(50, 50), 12, _p(_ink, stroke: true, width: 2));
  for (final p in [
    const Offset(36, 36),
    const Offset(64, 40),
    const Offset(50, 66),
    const Offset(30, 56),
  ]) {
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 8, height: 3), const Radius.circular(1.5)),
      _p(_blue),
    );
  }
}

// ---------------------------------------------------------------------------
// 生活
// ---------------------------------------------------------------------------

void _book(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(18, 28, 82, 80), const Radius.circular(5)),
    _p(_blue),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(18, 28, 82, 80), const Radius.circular(5)),
    _p(_ink, stroke: true, width: 2),
  );
  c.drawRect(const Rect.fromLTRB(50, 28, 53, 80), _p(_ink));
  final line = _p(_white, stroke: true, width: 2.5);
  c.drawLine(const Offset(26, 42), const Offset(44, 42), line);
  c.drawLine(const Offset(26, 52), const Offset(44, 52), line);
  c.drawLine(const Offset(58, 42), const Offset(76, 42), line);
  c.drawLine(const Offset(58, 52), const Offset(76, 52), line);
}

void _camera(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(16, 34, 84, 82), const Radius.circular(9)),
    _p(_deepBlue),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(16, 34, 84, 82), const Radius.circular(9)),
    _p(_ink, stroke: true, width: 2),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(38, 26, 56, 36), const Radius.circular(3)),
    _p(_ink),
  );
  _circle(c, const Offset(50, 58), 14, _p(_blue));
  _circle(c, const Offset(50, 58), 14, _p(_ink, stroke: true, width: 2.5));
  _circle(c, const Offset(50, 58), 6, _p(_white));
  _circle(c, const Offset(74, 46), 3.5, _p(_yellow));
}

void _mail(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(16, 30, 84, 76), const Radius.circular(5)),
    _p(_cream),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(16, 30, 84, 76), const Radius.circular(5)),
    _p(_ink, stroke: true, width: 2.2),
  );
  final flap = Path()
    ..moveTo(18, 33)
    ..lineTo(50, 58)
    ..lineTo(82, 33);
  c.drawPath(flap, _p(_rose, stroke: true, width: 2.5));
  c.drawPath(_heartPath(const Offset(50, 50), 7), _p(_pink));
}

void _gift(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 42, 78, 86), const Radius.circular(5)),
    _p(_purple),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(22, 42, 78, 86), const Radius.circular(5)),
    _p(_ink, stroke: true, width: 2),
  );
  c.drawRect(const Rect.fromLTRB(46, 42, 54, 86), _p(_yellow));
  c.drawRect(const Rect.fromLTRB(18, 32, 82, 44), _p(_yellow));
  c.drawRect(const Rect.fromLTRB(18, 32, 82, 44), _p(_ink, stroke: true, width: 2));
  c.drawPath(_heartPath(const Offset(42, 26), 8), _p(_pink));
  c.drawPath(_heartPath(const Offset(58, 26), 8), _p(_pink));
}

void _bow(Canvas c) {
  void lobe(Offset to, Offset ctrl) {
    final path = Path()
      ..moveTo(50, 50)
      ..lineTo(50, 32)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy + 26, 50, 68)
      ..close();
    c.drawPath(path, _p(_pink));
    c.drawPath(path, _p(_rose, stroke: true, width: 2));
  }

  lobe(const Offset(14, 40), const Offset(16, 26));
  lobe(const Offset(86, 40), const Offset(84, 26));
  _circle(c, const Offset(50, 50), 8, _p(_rose));
}

void _candle(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(38, 38, 62, 88), const Radius.circular(6)),
    _p(_cream),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(38, 38, 62, 88), const Radius.circular(6)),
    _p(_ink, stroke: true, width: 2),
  );
  c.drawLine(const Offset(38, 54), const Offset(62, 54), _p(_pink, stroke: true, width: 5));
  c.drawRect(const Rect.fromLTRB(48, 26, 52, 40), _p(_ink));
  final flame = Path()
    ..moveTo(50, 8)
    ..quadraticBezierTo(60, 18, 50, 26)
    ..quadraticBezierTo(40, 18, 50, 8);
  c.drawPath(flame, _p(_yellow));
}

void _music(Canvas c) {
  _circle(c, const Offset(32, 72), 13, _p(_deepBlue));
  _circle(c, const Offset(68, 62), 11, _p(_deepBlue));
  c.drawRect(const Rect.fromLTRB(43, 26, 46, 72), _p(_ink));
  c.drawRect(const Rect.fromLTRB(77, 18, 80, 62), _p(_ink));
  c.drawLine(const Offset(46, 28), const Offset(80, 20), _p(_ink, stroke: true, width: 3));
  c.drawPath(_starPath(const Offset(84, 14), 8), _p(_yellow));
}

void _mug(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(24, 36, 70, 84), const Radius.circular(8)),
    _p(_green),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(24, 36, 70, 84), const Radius.circular(8)),
    _p(_ink, stroke: true, width: 2.2),
  );
  c.drawArc(
    const Rect.fromLTRB(66, 46, 86, 66),
    -math.pi / 2,
    math.pi,
    false,
    _p(_ink, stroke: true, width: 3.5),
  );
  c.drawPath(_heartPath(const Offset(47, 58), 8), _p(_white));
  final steam = _p(_ink, stroke: true, width: 2.2);
  c.drawLine(const Offset(38, 28), const Offset(38, 16), steam);
  c.drawLine(const Offset(52, 28), const Offset(52, 14), steam);
}

// ---------------------------------------------------------------------------
// 可爱
// ---------------------------------------------------------------------------

void _cat(Canvas c) {
  final earL = Path()
    ..moveTo(24, 34)
    ..lineTo(30, 10)
    ..lineTo(46, 26)
    ..close();
  final earR = Path()
    ..moveTo(76, 34)
    ..lineTo(70, 10)
    ..lineTo(54, 26)
    ..close();
  c.drawPath(earL, _p(_yellow));
  c.drawPath(earR, _p(_yellow));
  c.drawPath(earL, _p(_ink, stroke: true, width: 2));
  c.drawPath(earR, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(50, 52), 30, _p(_yellow));
  _circle(c, const Offset(50, 52), 30, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(39, 48), 3.2, _p(_ink));
  _circle(c, const Offset(61, 48), 3.2, _p(_ink));
  final nose = Path()
    ..moveTo(50, 58)
    ..lineTo(46, 62)
    ..lineTo(54, 62)
    ..close();
  c.drawPath(nose, _p(_rose));
  final whisker = _p(_ink, stroke: true, width: 1.8);
  c.drawLine(const Offset(28, 56), const Offset(16, 52), whisker);
  c.drawLine(const Offset(28, 62), const Offset(16, 64), whisker);
  c.drawLine(const Offset(72, 56), const Offset(84, 52), whisker);
  c.drawLine(const Offset(72, 62), const Offset(84, 64), whisker);
}

void _butterfly(Canvas c) {
  double wing(double dir) {
    final path = Path()
      ..moveTo(50, 50)
      ..cubicTo(50 - 38 * dir, 14, 14 * dir + 50 - 24 * dir, 34, 50, 56)
      ..close();
    final lower = Path()
      ..moveTo(50, 54)
      ..cubicTo(50 - 30 * dir, 60, 50 - 26 * dir, 88, 50, 66)
      ..close();
    c.drawPath(path, _p(_purple));
    c.drawPath(lower, _p(_blue));
    c.drawPath(path, _p(_ink, stroke: true, width: 1.8));
    c.drawPath(lower, _p(_ink, stroke: true, width: 1.8));
    return 0;
  }

  wing(1);
  wing(-1);
  c.drawOval(const Rect.fromLTRB(46, 30, 54, 76), _p(_ink));
  c.drawLine(const Offset(48, 32), const Offset(40, 18), _p(_ink, stroke: true, width: 2));
  c.drawLine(const Offset(52, 32), const Offset(60, 18), _p(_ink, stroke: true, width: 2));
}

void _bird(Canvas c) {
  final body = Path()
    ..moveTo(26, 58)
    ..quadraticBezierTo(30, 30, 58, 34)
    ..quadraticBezierTo(84, 38, 78, 58)
    ..quadraticBezierTo(70, 80, 44, 76)
    ..quadraticBezierTo(26, 74, 26, 58)
    ..close();
  c.drawPath(body, _p(_blue));
  c.drawPath(body, _p(_ink, stroke: true, width: 2));
  final wing = Path()
    ..moveTo(40, 56)
    ..quadraticBezierTo(56, 44, 68, 58)
    ..quadraticBezierTo(54, 64, 40, 56)
    ..close();
  c.drawPath(wing, _p(_deepBlue));
  _circle(c, const Offset(66, 44), 2.6, _p(_ink));
  c.drawPath(Path()
    ..moveTo(78, 46)
    ..lineTo(90, 50)
    ..lineTo(78, 54)
    ..close(), _p(_orange));
}

void _bear(Canvas c) {
  _circle(c, const Offset(30, 28), 12, _p(_orange));
  _circle(c, const Offset(70, 28), 12, _p(_orange));
  _circle(c, const Offset(30, 28), 12, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(70, 28), 12, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(50, 54), 30, _p(_orange));
  _circle(c, const Offset(50, 54), 30, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(50, 62), 12, _p(_cream));
  _circle(c, const Offset(40, 48), 3.2, _p(_ink));
  _circle(c, const Offset(60, 48), 3.2, _p(_ink));
  _circle(c, const Offset(47, 60), 2.4, _p(_ink));
  _circle(c, const Offset(53, 60), 2.4, _p(_ink));
}

void _heart(Canvas c) {
  c.drawPath(_heartPath(const Offset(50, 48), 34), _p(_rose));
  c.drawPath(_heartPath(const Offset(50, 48), 34), _p(_ink, stroke: true, width: 2));
  c.drawPath(_heartPath(const Offset(40, 38), 8), _p(_white));
}

void _smiley(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_yellow));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(38, 44), 3.4, _p(_ink));
  _circle(c, const Offset(62, 44), 3.4, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(32, 48, 68, 76),
    0.15 * math.pi,
    0.7 * math.pi,
    false,
    _p(_ink, stroke: true, width: 3),
  );
  c.drawArc(const Rect.fromLTRB(28, 26, 44, 38), 0, math.pi, false, _p(_rose, stroke: true, width: 3));
  c.drawArc(const Rect.fromLTRB(56, 26, 72, 38), 0, math.pi, false, _p(_rose, stroke: true, width: 3));
}

void _balloon(Canvas c) {
  c.drawOval(const Rect.fromLTRB(28, 14, 76, 72), _p(_rose));
  c.drawOval(const Rect.fromLTRB(28, 14, 76, 72), _p(_ink, stroke: true, width: 2));
  c.drawArc(const Rect.fromLTRB(40, 24, 64, 52), math.pi * 0.75, math.pi * 0.8, false, _p(_white, stroke: true, width: 3));
  c.drawPath(
    Path()
      ..moveTo(46, 72)
      ..lineTo(58, 72)
      ..lineTo(54, 80)
      ..lineTo(50, 72)
      ..close(),
    _p(_rose),
  );
  c.drawLine(const Offset(52, 80), const Offset(44, 96), _p(_ink, stroke: true, width: 2));
  c.drawPath(_starPath(const Offset(30, 82), 7), _p(_yellow));
}

void _flag(Canvas c) {
  c.drawLine(const Offset(30, 14), const Offset(30, 90), _p(_brown, stroke: true, width: 4));
  final banner = Path()
    ..moveTo(30, 16)
    ..lineTo(86, 26)
    ..lineTo(78, 44)
    ..lineTo(30, 38)
    ..close();
  c.drawPath(banner, _p(_green));
  c.drawPath(banner, _p(_ink, stroke: true, width: 2));
  c.drawPath(_heartPath(const Offset(54, 28), 6), _p(_red));
}

// ---------------------------------------------------------------------------
// 胶带
// ---------------------------------------------------------------------------

/// 和纸胶带画笔：半透明底 + 纹样，两端锯齿毛边。
class TapePainter extends CustomPainter {
  const TapePainter({required this.style, required this.color});

  final String style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = color.withValues(alpha: 0.72);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    // 两端锯齿毛边（和纸胶带质感）。
    final zig = Paint()
      ..color = base
      ..isAntiAlias = true;
    const teeth = 5;
    final toothW = size.height / teeth;
    for (var i = 0; i < teeth; i++) {
      if (i.isEven) continue;
      canvas.drawPath(
        Path()
          ..moveTo(0, i * toothW)
          ..lineTo(-toothW * 0.9, i * toothW + toothW / 2)
          ..lineTo(0, (i + 1) * toothW)
          ..close(),
        zig,
      );
      canvas.drawPath(
        Path()
          ..moveTo(size.width, i * toothW)
          ..lineTo(size.width + toothW * 0.9, i * toothW + toothW / 2)
          ..lineTo(size.width, (i + 1) * toothW)
          ..close(),
        zig,
      );
    }

    final ink = Color.lerp(color, const Color(0xFF5A4A3A), 0.45)!
        .withValues(alpha: 0.9);
    final unit = size.height / 3;
    switch (style) {
      case 'dots':
        final p = Paint()..color = ink;
        for (var x = unit; x < size.width + unit; x += unit * 2) {
          for (var y = unit; y < size.height; y += unit * 2) {
            canvas.drawCircle(Offset(x, y), unit * 0.38, p);
          }
        }
      case 'stripes':
        final p = Paint()
          ..color = ink
          ..strokeWidth = unit * 0.5
          ..strokeCap = StrokeCap.round;
        for (var x = 0.0; x < size.width + size.height; x += unit * 2) {
          canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), p);
        }
      case 'grid':
        final p = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        for (var x = 0.0; x <= size.width; x += unit * 2) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = 0.0; y <= size.height; y += unit) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case 'hearts':
        final p = Paint()..color = ink;
        for (var x = unit; x < size.width + unit; x += unit * 2) {
          final path = _heartPath(Offset(x, size.height / 2), unit * 0.62);
          canvas.drawPath(path, p);
        }
      case 'waves':
        final p = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.4
          ..strokeCap = StrokeCap.round;
        final path = Path()..moveTo(0, size.height / 2);
        var x = 0.0;
        while (x < size.width) {
          path.quadraticBezierTo(
            x + unit,
            -unit * 0.4,
            x + unit * 2,
            size.height / 2,
          );
          x += unit * 2;
        }
        canvas.drawPath(path, p);
      case 'cross':
        final p = Paint()
          ..color = ink
          ..strokeWidth = unit * 0.35
          ..strokeCap = StrokeCap.round;
        for (var x = unit; x < size.width + unit; x += unit * 2) {
          final cx = Offset(x, size.height / 2);
          final r = unit * 0.6;
          canvas.drawLine(cx + Offset(-r, -r), cx + Offset(r, r), p);
          canvas.drawLine(cx + Offset(-r, r), cx + Offset(r, -r), p);
        }
    }
  }

  @override
  bool shouldRepaint(covariant TapePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}
