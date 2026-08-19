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

/// emoji 素材项（REQ-17.7）:字符 + 中文检索词,供素材面板跨页签搜索。
class EmojiAsset {
  const EmojiAsset(this.char, this.keywords);

  final String char;

  /// 空格分隔的中文检索词。
  final String keywords;

  /// 该 emoji 是否命中搜索词（检索词 / 字符本身）。
  bool matches(String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    return keywords.contains(q) || char == q;
  }
}

/// 按类目组织的常用 emoji 全集（REQ-17.7,替换原 30 个硬编码列表）。
/// key 为类目中文名,面板按此分组展示并支持快速跳转。
const Map<String, List<EmojiAsset>> emojiCategories = {
  '表情': [
    EmojiAsset('😀', '笑 开心 微笑'),
    EmojiAsset('😃', '笑 开心 大笑'),
    EmojiAsset('😄', '笑 开心 眯眼'),
    EmojiAsset('😁', '笑 露齿 开心'),
    EmojiAsset('😆', '笑 大笑 眯眼'),
    EmojiAsset('😅', '笑 汗 尴尬'),
    EmojiAsset('🤣', '笑 打滚 爆笑'),
    EmojiAsset('😂', '笑哭 眼泪 爆笑'),
    EmojiAsset('🙂', '微笑 淡定 还好'),
    EmojiAsset('🙃', '倒脸 无奈 调皮'),
    EmojiAsset('😉', '眨眼 调皮 暗示'),
    EmojiAsset('😊', '微笑 害羞 温柔'),
    EmojiAsset('😇', '天使 乖 光环'),
    EmojiAsset('🥰', '喜欢 幸福 爱心'),
    EmojiAsset('😍', '花痴 喜欢 星星眼'),
    EmojiAsset('🤩', '崇拜 惊艳 星星眼'),
    EmojiAsset('😘', '飞吻 亲亲 喜欢'),
    EmojiAsset('😚', '亲 害羞 闭眼'),
    EmojiAsset('😋', '好吃 美味 舔嘴'),
    EmojiAsset('😜', '吐舌 调皮 眨眼'),
    EmojiAsset('🤪', '搞怪 夸张 疯'),
    EmojiAsset('😝', '吐舌 眯眼 调皮'),
    EmojiAsset('🤗', '抱抱 拥抱 温暖'),
    EmojiAsset('🤔', '思考 想 疑问'),
    EmojiAsset('🤭', '捂嘴 偷笑 害羞'),
    EmojiAsset('🤫', '嘘 安静 保密'),
    EmojiAsset('😐', '面无表情 平静 无语'),
    EmojiAsset('😑', '无语 无奈 面瘫'),
    EmojiAsset('😶', '无言 沉默'),
    EmojiAsset('😏', '得意 坏笑 挑眉'),
    EmojiAsset('😒', '无奈 不屑 嫌弃'),
    EmojiAsset('🙄', '白眼 无语 翻白眼'),
    EmojiAsset('😬', '尴尬 龇牙 紧张'),
    EmojiAsset('😔', '失落 难过 低落'),
    EmojiAsset('😪', '困 瞌睡 累'),
    EmojiAsset('😴', '睡觉 晚安 呼呼'),
    EmojiAsset('🥱', '打哈欠 困 累'),
    EmojiAsset('😌', '满足 放松 舒服'),
    EmojiAsset('🤒', '生病 发烧 不舒服'),
    EmojiAsset('🥳', '庆祝 派对 生日'),
    EmojiAsset('🥺', '可怜 撒娇 求'),
    EmojiAsset('😢', '哭 难过 眼泪'),
    EmojiAsset('😭', '大哭 伤心 眼泪'),
    EmojiAsset('😤', '生气 不服 哼'),
    EmojiAsset('😡', '生气 愤怒 火大'),
    EmojiAsset('🤯', '震惊 崩溃 爆炸'),
    EmojiAsset('😱', '惊恐 害怕 尖叫'),
    EmojiAsset('🥶', '冷 寒冷 冻'),
    EmojiAsset('🥵', '热 炎热 出汗'),
    EmojiAsset('😎', '酷 墨镜 得意'),
  ],
  '手势': [
    EmojiAsset('👍', '赞 点赞 好'),
    EmojiAsset('👎', '踩 不好 差'),
    EmojiAsset('👌', '好的 可以 ok'),
    EmojiAsset('✌️', '耶 胜利 剪刀手'),
    EmojiAsset('🤞', '祈祷 好运 交叉'),
    EmojiAsset('🤟', '爱你 手势'),
    EmojiAsset('🤘', '摇滚 手势'),
    EmojiAsset('🤙', '打电话 手势'),
    EmojiAsset('👈', '左 指向'),
    EmojiAsset('👉', '右 指向'),
    EmojiAsset('👆', '上 指向'),
    EmojiAsset('👇', '下 指向'),
    EmojiAsset('☝️', '重点 指向 一'),
    EmojiAsset('✋', '手掌 停 举手'),
    EmojiAsset('🤚', '手背 举手'),
    EmojiAsset('👋', '挥手 你好 再见'),
    EmojiAsset('🤝', '握手 合作 成交'),
    EmojiAsset('🙏', '拜托 祈祷 感谢'),
    EmojiAsset('👏', '鼓掌 表扬 棒'),
    EmojiAsset('🙌', '举双手 欢呼 庆祝'),
    EmojiAsset('💪', '加油 力量 肌肉'),
    EmojiAsset('✍️', '写字 记录 书写'),
    EmojiAsset('🤲', '捧 双手'),
  ],
  '人物': [
    EmojiAsset('👶', '宝宝 婴儿'),
    EmojiAsset('🧒', '小孩 儿童'),
    EmojiAsset('👦', '男孩 少年'),
    EmojiAsset('👧', '女孩 少女'),
    EmojiAsset('🧑', '人 成人'),
    EmojiAsset('👨', '男人 爸爸'),
    EmojiAsset('👩', '女人 妈妈'),
    EmojiAsset('🧓', '老人 长辈'),
    EmojiAsset('👴', '爷爷 老人'),
    EmojiAsset('👵', '奶奶 老人'),
    EmojiAsset('👪', '家庭 家人 全家'),
    EmojiAsset('💑', '情侣 恋爱 约会'),
    EmojiAsset('👫', '朋友 拉手 男女'),
    EmojiAsset('👭', '闺蜜 姐妹'),
    EmojiAsset('👬', '兄弟 好友'),
    EmojiAsset('👰', '新娘 婚礼'),
    EmojiAsset('🤵', '新郎 婚礼'),
    EmojiAsset('🎓', '毕业 学位帽 学习'),
    EmojiAsset('🧘', '冥想 瑜伽 放松'),
    EmojiAsset('🏃', '跑步 运动 锻炼'),
    EmojiAsset('🚶', '走路 散步'),
    EmojiAsset('💃', '跳舞 舞蹈'),
    EmojiAsset('🕺', '跳舞 男'),
    EmojiAsset('👻', '幽灵 万圣节 调皮'),
  ],
  '动物': [
    EmojiAsset('🐶', '狗 小狗 汪'),
    EmojiAsset('🐱', '猫 猫咪 喵'),
    EmojiAsset('🐭', '老鼠 鼠'),
    EmojiAsset('🐹', '仓鼠 小仓鼠'),
    EmojiAsset('🐰', '兔子 兔 小白兔'),
    EmojiAsset('🦊', '狐狸'),
    EmojiAsset('🐻', '熊 小熊'),
    EmojiAsset('🐼', '熊猫 国宝'),
    EmojiAsset('🐨', '考拉'),
    EmojiAsset('🐯', '老虎 虎'),
    EmojiAsset('🦁', '狮子'),
    EmojiAsset('🐮', '牛 奶牛'),
    EmojiAsset('🐷', '猪 小猪'),
    EmojiAsset('🐸', '青蛙 蛙'),
    EmojiAsset('🐵', '猴子 猴'),
    EmojiAsset('🐔', '鸡 母鸡'),
    EmojiAsset('🐧', '企鹅'),
    EmojiAsset('🐦', '小鸟 鸟'),
    EmojiAsset('🐤', '小鸡 雏鸟'),
    EmojiAsset('🦆', '鸭子 鸭'),
    EmojiAsset('🦉', '猫头鹰'),
    EmojiAsset('🦋', '蝴蝶 春天'),
    EmojiAsset('🐝', '蜜蜂 蜂'),
    EmojiAsset('🐞', '瓢虫 虫'),
    EmojiAsset('🐢', '乌龟 龟'),
    EmojiAsset('🐠', '鱼 热带鱼'),
    EmojiAsset('🐳', '鲸鱼 鲸'),
    EmojiAsset('🐬', '海豚'),
    EmojiAsset('🦄', '独角兽'),
    EmojiAsset('🐴', '马'),
    EmojiAsset('🐘', '大象 象'),
    EmojiAsset('🦔', '刺猬'),
    EmojiAsset('🐑', '羊 绵羊'),
    EmojiAsset('🐕', '狗 遛狗'),
    EmojiAsset('🐈', '猫 家猫'),
    EmojiAsset('🦌', '鹿 小鹿'),
    EmojiAsset('🐾', '爪印 脚印 宠物'),
  ],
  '植物': [
    EmojiAsset('🌸', '樱花 花 春天'),
    EmojiAsset('🌷', '郁金香 花'),
    EmojiAsset('🌹', '玫瑰 花 表白'),
    EmojiAsset('🌺', '扶桑 花'),
    EmojiAsset('🌻', '向日葵 太阳花 花'),
    EmojiAsset('🌼', '雏菊 小花'),
    EmojiAsset('💐', '花束 鲜花 礼物'),
    EmojiAsset('🌱', '发芽 种子 新生'),
    EmojiAsset('🌿', '绿叶 香草 清新'),
    EmojiAsset('🍀', '四叶草 幸运'),
    EmojiAsset('🍁', '枫叶 秋天'),
    EmojiAsset('🍂', '落叶 秋天'),
    EmojiAsset('🍃', '树叶 风 清新'),
    EmojiAsset('🌵', '仙人掌 多肉'),
    EmojiAsset('🌴', '棕榈 椰子树 海边'),
    EmojiAsset('🌳', '树 大树'),
    EmojiAsset('🌲', '松树 常青树'),
    EmojiAsset('🪴', '盆栽 绿植 植物'),
    EmojiAsset('🍄', '蘑菇 菌'),
    EmojiAsset('🌾', '稻穗 麦 秋收'),
    EmojiAsset('🎋', '竹 许愿'),
    EmojiAsset('🌰', '栗子 坚果'),
    EmojiAsset('🎍', '松竹 新年'),
  ],
  '天气': [
    EmojiAsset('☀️', '晴天 太阳 阳光'),
    EmojiAsset('🌤️', '多云 晴间多云'),
    EmojiAsset('⛅', '多云 云'),
    EmojiAsset('☁️', '阴天 云朵'),
    EmojiAsset('🌧️', '下雨 雨天'),
    EmojiAsset('⛈️', '雷雨 打雷'),
    EmojiAsset('🌩️', '闪电 雷'),
    EmojiAsset('❄️', '雪花 下雪 冬天'),
    EmojiAsset('☃️', '雪人 冬天'),
    EmojiAsset('⛄', '雪人 堆雪人'),
    EmojiAsset('🌈', '彩虹 雨后'),
    EmojiAsset('🌊', '海浪 大海 波浪'),
    EmojiAsset('💧', '水滴 水'),
    EmojiAsset('🔥', '火 火焰 热'),
    EmojiAsset('🌙', '月亮 夜晚 晚安'),
    EmojiAsset('🌜', '弯月 月亮 睡觉'),
    EmojiAsset('⭐', '星星 星'),
    EmojiAsset('🌟', '闪耀 星光'),
    EmojiAsset('✨', '闪光 亮晶晶 高光'),
    EmojiAsset('💫', '旋转 星星 眩晕'),
    EmojiAsset('🌍', '地球 世界'),
    EmojiAsset('🌡️', '温度 气温'),
  ],
  '食物': [
    EmojiAsset('🍎', '苹果 水果'),
    EmojiAsset('🍊', '橘子 橙子 水果'),
    EmojiAsset('🍋', '柠檬 酸 水果'),
    EmojiAsset('🍌', '香蕉 水果'),
    EmojiAsset('🍉', '西瓜 夏天 水果'),
    EmojiAsset('🍇', '葡萄 水果'),
    EmojiAsset('🍓', '草莓 水果 甜'),
    EmojiAsset('🍒', '樱桃 水果'),
    EmojiAsset('🍑', '桃子 蜜桃 水果'),
    EmojiAsset('🥭', '芒果 水果'),
    EmojiAsset('🍍', '菠萝 水果'),
    EmojiAsset('🥥', '椰子 水果'),
    EmojiAsset('🥝', '猕猴桃 奇异果'),
    EmojiAsset('🍅', '番茄 西红柿'),
    EmojiAsset('🥑', '牛油果 蔬菜'),
    EmojiAsset('🥦', '西兰花 蔬菜'),
    EmojiAsset('🌽', '玉米 蔬菜'),
    EmojiAsset('🥕', '胡萝卜 蔬菜'),
    EmojiAsset('🍞', '面包 早餐'),
    EmojiAsset('🥐', '可颂 牛角包 早餐'),
    EmojiAsset('🥯', '贝果 早餐'),
    EmojiAsset('🥞', '松饼 薄煎饼 早餐'),
    EmojiAsset('🧇', '华夫饼 早餐'),
    EmojiAsset('🧀', '奶酪 芝士'),
    EmojiAsset('🍔', '汉堡 快餐'),
    EmojiAsset('🍟', '薯条 快餐'),
    EmojiAsset('🍕', '披萨 意大利'),
    EmojiAsset('🌭', '热狗 快餐'),
    EmojiAsset('🌮', '塔可 墨西哥'),
    EmojiAsset('🍜', '拉面 面条'),
    EmojiAsset('🍝', '意面 意大利面'),
    EmojiAsset('🍚', '米饭 白饭'),
    EmojiAsset('🍣', '寿司 日料'),
    EmojiAsset('🍤', '虾 天妇罗'),
    EmojiAsset('🥟', '饺子 中餐'),
    EmojiAsset('🍰', '蛋糕 甜点 生日'),
    EmojiAsset('🎂', '生日蛋糕 庆祝'),
    EmojiAsset('🧁', '纸杯蛋糕 甜点'),
    EmojiAsset('🍪', '饼干 甜点'),
    EmojiAsset('🍩', '甜甜圈 甜点'),
    EmojiAsset('🍫', '巧克力 甜'),
    EmojiAsset('🍬', '糖果 甜'),
    EmojiAsset('🍭', '棒棒糖 甜'),
    EmojiAsset('🍦', '冰淇淋 甜筒 夏天'),
    EmojiAsset('🍨', '冰淇淋 甜点'),
    EmojiAsset('🍮', '布丁 甜点'),
    EmojiAsset('🍯', '蜂蜜 甜'),
    EmojiAsset('☕', '咖啡 提神 下午茶'),
    EmojiAsset('🍵', '茶 绿茶 抹茶'),
    EmojiAsset('🧋', '奶茶 珍珠'),
    EmojiAsset('🥤', '饮料 汽水'),
    EmojiAsset('🧃', '果汁 饮料'),
    EmojiAsset('🍺', '啤酒 干杯'),
    EmojiAsset('🍷', '红酒 葡萄酒'),
    EmojiAsset('🥂', '干杯 香槟 庆祝'),
  ],
  '活动': [
    EmojiAsset('🎉', '庆祝 派对 撒花'),
    EmojiAsset('🎊', '彩球 庆祝'),
    EmojiAsset('🎈', '气球 生日'),
    EmojiAsset('🎁', '礼物 惊喜'),
    EmojiAsset('🎀', '蝴蝶结 装饰'),
    EmojiAsset('🎄', '圣诞树 圣诞'),
    EmojiAsset('🎃', '南瓜 万圣节'),
    EmojiAsset('🧨', '鞭炮 新年'),
    EmojiAsset('🎆', '烟花 跨年'),
    EmojiAsset('🎇', '烟花 夜晚'),
    EmojiAsset('🏮', '灯笼 新年 中式'),
    EmojiAsset('🧧', '红包 新年'),
    EmojiAsset('🎯', '目标 靶心 计划'),
    EmojiAsset('🎮', '游戏 打游戏'),
    EmojiAsset('🎲', '骰子 桌游'),
    EmojiAsset('🧩', '拼图 益智'),
    EmojiAsset('🎨', '画画 绘画 艺术'),
    EmojiAsset('🎭', '戏剧 表演'),
    EmojiAsset('🎤', '唱歌 麦克风'),
    EmojiAsset('🎧', '耳机 听歌'),
    EmojiAsset('🎵', '音符 音乐'),
    EmojiAsset('🎶', '音乐 旋律'),
    EmojiAsset('🎸', '吉他 乐器'),
    EmojiAsset('🎹', '钢琴 乐器'),
    EmojiAsset('🏀', '篮球 运动'),
    EmojiAsset('⚽', '足球 运动'),
    EmojiAsset('🏸', '羽毛球 运动'),
    EmojiAsset('🏊', '游泳 运动'),
    EmojiAsset('🚴', '骑行 骑车 运动'),
    EmojiAsset('⛺', '露营 帐篷'),
    EmojiAsset('🎣', '钓鱼'),
    EmojiAsset('🧗', '攀岩 运动'),
  ],
  '旅行': [
    EmojiAsset('✈️', '飞机 旅行 出行'),
    EmojiAsset('🚄', '高铁 火车 出行'),
    EmojiAsset('🚗', '汽车 开车 自驾'),
    EmojiAsset('🚕', '出租车 打车'),
    EmojiAsset('🚌', '公交 巴士'),
    EmojiAsset('🚲', '自行车 骑行'),
    EmojiAsset('🛵', '电动车 摩托'),
    EmojiAsset('🚢', '轮船 邮轮'),
    EmojiAsset('⛵', '帆船 海边'),
    EmojiAsset('🚀', '火箭 出发'),
    EmojiAsset('🗺️', '地图 路线 攻略'),
    EmojiAsset('🧳', '行李箱 出发 旅行'),
    EmojiAsset('🎒', '背包 出门'),
    EmojiAsset('🏔️', '雪山 高山'),
    EmojiAsset('⛰️', '山 爬山'),
    EmojiAsset('🏖️', '海滩 沙滩 度假'),
    EmojiAsset('🏝️', '海岛 小岛'),
    EmojiAsset('🏕️', '露营 野营'),
    EmojiAsset('🌆', '城市 黄昏'),
    EmojiAsset('🌃', '夜景 城市 夜晚'),
    EmojiAsset('🏙️', '城市 天际线'),
    EmojiAsset('🗼', '铁塔 东京'),
    EmojiAsset('🗽', '自由女神 纽约'),
    EmojiAsset('🏰', '城堡 童话'),
    EmojiAsset('⛩️', '神社 日本'),
    EmojiAsset('🏯', '城 日式'),
    EmojiAsset('🏡', '家 房子 小院'),
    EmojiAsset('🏠', '家 房子'),
    EmojiAsset('🚏', '车站 站牌'),
    EmojiAsset('🛎️', '酒店 前台 铃'),
  ],
  '物品': [
    EmojiAsset('📖', '书 阅读 读书'),
    EmojiAsset('📚', '书本 书堆 学习'),
    EmojiAsset('📔', '笔记本 手账 日记'),
    EmojiAsset('📝', '记录 写字 便签'),
    EmojiAsset('✏️', '铅笔 写字'),
    EmojiAsset('🖊️', '钢笔 签字笔'),
    EmojiAsset('🖍️', '蜡笔 涂色'),
    EmojiAsset('🖌️', '画笔 上色'),
    EmojiAsset('📌', '图钉 标记'),
    EmojiAsset('📎', '回形针 夹住'),
    EmojiAsset('✂️', '剪刀 手工'),
    EmojiAsset('📏', '尺子 直尺'),
    EmojiAsset('🗓️', '日历 日程'),
    EmojiAsset('⏰', '闹钟 时间 起床'),
    EmojiAsset('⌚', '手表 时间'),
    EmojiAsset('💡', '灯泡 想法 灵感'),
    EmojiAsset('🕯️', '蜡烛 温暖 香薰'),
    EmojiAsset('🔑', '钥匙 开门'),
    EmojiAsset('🔒', '锁 隐私 加密'),
    EmojiAsset('💌', '情书 信 心意'),
    EmojiAsset('✉️', '信封 邮件'),
    EmojiAsset('📮', '邮筒 寄信'),
    EmojiAsset('📦', '包裹 快递'),
    EmojiAsset('🛍️', '购物 逛街 买'),
    EmojiAsset('💰', '钱 存钱 理财'),
    EmojiAsset('💳', '银行卡 支付'),
    EmojiAsset('📱', '手机 电话'),
    EmojiAsset('💻', '电脑 办公 上班'),
    EmojiAsset('📷', '相机 拍照 摄影'),
    EmojiAsset('📸', '拍照 闪光'),
    EmojiAsset('🎬', '电影 拍摄'),
    EmojiAsset('🔍', '放大镜 搜索 查找'),
    EmojiAsset('🧸', '玩偶 泰迪熊 毛绒'),
    EmojiAsset('🛏️', '床 睡觉 休息'),
    EmojiAsset('🛋️', '沙发 客厅 休息'),
    EmojiAsset('🧺', '篮子 野餐 洗衣'),
    EmojiAsset('☂️', '雨伞 挡雨'),
    EmojiAsset('🕊️', '白鸽 和平 自由'),
  ],
  '符号': [
    EmojiAsset('❤️', '爱心 红心 喜欢'),
    EmojiAsset('🧡', '橙心 爱心'),
    EmojiAsset('💛', '黄心 爱心'),
    EmojiAsset('💚', '绿心 爱心'),
    EmojiAsset('💙', '蓝心 爱心'),
    EmojiAsset('💜', '紫心 爱心'),
    EmojiAsset('🤍', '白心 爱心'),
    EmojiAsset('🖤', '黑心 爱心'),
    EmojiAsset('💕', '两颗心 喜欢'),
    EmojiAsset('💖', '闪亮的心 心动'),
    EmojiAsset('💗', '心动 跳动'),
    EmojiAsset('💓', '心跳 悸动'),
    EmojiAsset('💞', '双心 缘分'),
    EmojiAsset('💘', '一箭穿心 表白'),
    EmojiAsset('💝', '心形礼物 礼物'),
    EmojiAsset('💔', '心碎 失恋'),
    EmojiAsset('✅', '完成 打勾 已办'),
    EmojiAsset('☑️', '勾选 待办'),
    EmojiAsset('❌', '错 取消 否'),
    EmojiAsset('❗', '感叹号 重点'),
    EmojiAsset('❓', '问号 疑问'),
    EmojiAsset('💯', '满分 一百 完美'),
    EmojiAsset('⚡', '闪电 快 电'),
    EmojiAsset('♻️', '循环 环保'),
    EmojiAsset('🔔', '铃铛 提醒 通知'),
    EmojiAsset('🔕', '静音 免打扰'),
    EmojiAsset('🚩', '旗 标记 打卡'),
    EmojiAsset('🏁', '终点 完成 旗'),
    EmojiAsset('🔖', '书签 标签'),
    EmojiAsset('🏷️', '标签 分类'),
    EmojiAsset('🆕', '新 新增'),
    EmojiAsset('🔴', '红点 圆点'),
    EmojiAsset('🟠', '橙点 圆点'),
    EmojiAsset('🟡', '黄点 圆点'),
    EmojiAsset('🟢', '绿点 圆点'),
    EmojiAsset('🔵', '蓝点 圆点'),
    EmojiAsset('🟣', '紫点 圆点'),
    EmojiAsset('⬛', '黑块 方块'),
    EmojiAsset('⬜', '白块 方块'),
  ],
};

/// 扁平化的 emoji 字符列表（保留原 `stickerPalette` 引用点不破坏）。
List<String> get stickerPalette => [
  for (final list in emojiCategories.values)
    for (final e in list) e.char,
];

/// 贴纸基础字号(编辑与导出共用,保持视觉一致)。
const stickerBaseFontSize = 34.0;
