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

/// 按类目组织的常用 emoji 全集（REQ-17.7,覆盖 Unicode 常用 emoji 主体）。
/// key 为类目中文名,面板按此分组展示并支持快速跳转;
/// 每项自带中文检索词,是 REQ-17.6 跨页签搜索的词库来源。
/// 收录原则:只收基础形态,不铺开肤色/性别修饰符与 ZWJ 组合的全部排列,
/// 避免条目爆量且在 Android / Windows 两端渲染不一致。
const Map<String, List<EmojiAsset>> emojiCategories = {
  '表情': [
    // 笑与开心
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
    EmojiAsset('🫠', '融化 无奈 化了'),
    EmojiAsset('😉', '眨眼 调皮 暗示'),
    EmojiAsset('😊', '微笑 害羞 温柔'),
    EmojiAsset('😇', '天使 乖 光环'),
    // 喜欢与亲昵
    EmojiAsset('🥰', '喜欢 幸福 爱心'),
    EmojiAsset('😍', '花痴 喜欢 星星眼'),
    EmojiAsset('🤩', '崇拜 惊艳 星星眼'),
    EmojiAsset('😘', '飞吻 亲亲 喜欢'),
    EmojiAsset('😗', '嘟嘴 亲 吹口哨'),
    EmojiAsset('☺️', '微笑 温柔 害羞'),
    EmojiAsset('😚', '亲 害羞 闭眼'),
    EmojiAsset('😙', '微笑 亲 眯眼'),
    EmojiAsset('🥲', '苦笑 含泪 感动'),
    // 调皮与馋
    EmojiAsset('😋', '好吃 美味 舔嘴'),
    EmojiAsset('😛', '吐舌 调皮 俏皮'),
    EmojiAsset('😜', '吐舌 调皮 眨眼'),
    EmojiAsset('🤪', '搞怪 夸张 疯'),
    EmojiAsset('😝', '吐舌 眯眼 调皮'),
    EmojiAsset('🤑', '财迷 钱 贪财'),
    EmojiAsset('🤗', '抱抱 拥抱 温暖'),
    EmojiAsset('🤭', '捂嘴 偷笑 害羞'),
    EmojiAsset('🫢', '捂嘴 惊讶 意外'),
    EmojiAsset('🫣', '偷看 遮眼 害羞'),
    EmojiAsset('🤫', '嘘 安静 保密'),
    EmojiAsset('🤔', '思考 想 疑问'),
    EmojiAsset('🫡', '敬礼 收到 致敬'),
    // 无语与平静
    EmojiAsset('🤐', '闭嘴 拉链 保密'),
    EmojiAsset('🤨', '挑眉 怀疑 质疑'),
    EmojiAsset('😐', '面无表情 平静 无语'),
    EmojiAsset('😑', '无语 无奈 面瘫'),
    EmojiAsset('😶', '无言 沉默 无话'),
    EmojiAsset('😏', '得意 坏笑 挑眉'),
    EmojiAsset('😒', '无奈 不屑 嫌弃'),
    EmojiAsset('🙄', '白眼 无语 翻白眼'),
    EmojiAsset('😬', '尴尬 龇牙 紧张'),
    EmojiAsset('🤥', '说谎 长鼻子 假话'),
    EmojiAsset('😌', '满足 放松 舒服'),
    // 困倦与不适
    EmojiAsset('😔', '失落 难过 低落'),
    EmojiAsset('😪', '困 瞌睡 累'),
    EmojiAsset('🤤', '流口水 馋 想吃'),
    EmojiAsset('😴', '睡觉 晚安 呼呼'),
    EmojiAsset('😷', '口罩 感冒 防护'),
    EmojiAsset('🤒', '生病 发烧 不舒服'),
    EmojiAsset('🤕', '受伤 包扎 头疼'),
    EmojiAsset('🤢', '恶心 反胃 想吐'),
    EmojiAsset('🤮', '呕吐 难受 吐了'),
    EmojiAsset('🤧', '打喷嚏 感冒 纸巾'),
    EmojiAsset('🥵', '热 炎热 出汗'),
    EmojiAsset('🥶', '冷 寒冷 冻'),
    EmojiAsset('🥴', '晕 醉 迷糊'),
    EmojiAsset('😵', '晕 眩晕 打转'),
    EmojiAsset('🤯', '震惊 崩溃 爆炸'),
    // 造型与人设
    EmojiAsset('🤠', '牛仔 帽子 西部'),
    EmojiAsset('🥳', '庆祝 派对 生日'),
    EmojiAsset('🥸', '伪装 假胡子 眼镜'),
    EmojiAsset('😎', '酷 墨镜 得意'),
    EmojiAsset('🤓', '书呆 眼镜 学霸'),
    EmojiAsset('🧐', '单片镜 审视 打量'),
    // 困惑与担忧
    EmojiAsset('😕', '困惑 疑惑 为难'),
    EmojiAsset('🫤', '一言难尽 无奈 勉强'),
    EmojiAsset('😟', '担心 忧虑 皱眉'),
    EmojiAsset('🙁', '不开心 皱眉 低落'),
    EmojiAsset('☹️', '不高兴 难过 皱眉'),
    EmojiAsset('😮', '惊讶 张嘴 哇'),
    EmojiAsset('😯', '惊讶 意外 咦'),
    EmojiAsset('😲', '震惊 吃惊 目瞪口呆'),
    EmojiAsset('😳', '脸红 害羞 惊呆'),
    EmojiAsset('🥺', '可怜 撒娇 求'),
    EmojiAsset('🥹', '感动 忍泪 委屈'),
    EmojiAsset('😦', '惊讶 张口 皱眉'),
    EmojiAsset('😧', '痛苦 惊恐 难受'),
    EmojiAsset('😨', '害怕 恐惧 惊'),
    EmojiAsset('😰', '焦虑 冷汗 紧张'),
    EmojiAsset('😥', '失望 难过 松口气'),
    // 悲伤与愤怒
    EmojiAsset('😢', '哭 难过 眼泪'),
    EmojiAsset('😭', '大哭 伤心 眼泪'),
    EmojiAsset('😱', '惊恐 害怕 尖叫'),
    EmojiAsset('😖', '难受 困扰 纠结'),
    EmojiAsset('😣', '忍耐 难受 坚持'),
    EmojiAsset('😞', '失望 沮丧 低头'),
    EmojiAsset('😓', '冷汗 委屈 辛苦'),
    EmojiAsset('😩', '疲惫 累坏 崩溃'),
    EmojiAsset('😫', '累 疲倦 受不了'),
    EmojiAsset('🥱', '打哈欠 困 累'),
    EmojiAsset('😤', '生气 不服 哼'),
    EmojiAsset('😡', '生气 愤怒 火大'),
    EmojiAsset('😠', '生气 恼火 不高兴'),
    EmojiAsset('🤬', '骂人 暴怒 脏话'),
    // 怪物与角色脸
    EmojiAsset('😈', '小恶魔 调皮 坏笑'),
    EmojiAsset('👿', '恶魔 生气 坏'),
    EmojiAsset('💀', '骷髅 死 惨'),
    EmojiAsset('☠️', '骷髅 危险 剧毒'),
    EmojiAsset('💩', '便便 搞笑 糟糕'),
    EmojiAsset('🤡', '小丑 装傻 讽刺'),
    EmojiAsset('👹', '鬼怪 妖怪 红鬼'),
    EmojiAsset('👺', '天狗 妖怪 面具'),
    EmojiAsset('👻', '幽灵 万圣节 调皮'),
    EmojiAsset('👽', '外星人 神秘 星际'),
    EmojiAsset('👾', '像素怪 游戏 复古'),
    EmojiAsset('🤖', '机器人 智能 科技'),
    // 猫脸与三不猴
    EmojiAsset('😺', '猫脸 开心 喵'),
    EmojiAsset('😸', '猫脸 笑 开心'),
    EmojiAsset('😹', '猫脸 笑哭 眼泪'),
    EmojiAsset('😻', '猫脸 花痴 喜欢'),
    EmojiAsset('😼', '猫脸 坏笑 得意'),
    EmojiAsset('😽', '猫脸 亲亲 撒娇'),
    EmojiAsset('🙀', '猫脸 惊恐 吓到'),
    EmojiAsset('😿', '猫脸 哭 难过'),
    EmojiAsset('😾', '猫脸 生气 不满'),
    EmojiAsset('🙈', '捂眼 不看 害羞'),
    EmojiAsset('🙉', '捂耳 不听 装聋'),
    EmojiAsset('🙊', '捂嘴 不说 保密'),
    // 情绪符号
    EmojiAsset('💢', '怒气 生气 青筋'),
    EmojiAsset('💥', '爆炸 碰撞 冲击'),
    EmojiAsset('💦', '汗 水花 溅'),
    EmojiAsset('💨', '一阵风 冲 溜走'),
    EmojiAsset('💤', '睡着 呼呼 打盹'),
  ],
  '手势': [
    // 招呼与手掌
    EmojiAsset('👋', '挥手 你好 再见'),
    EmojiAsset('🤚', '手背 举手 停'),
    EmojiAsset('🖐️', '张开手掌 五 手'),
    EmojiAsset('✋', '手掌 停 举手'),
    EmojiAsset('🖖', '瓦肯礼 手势 星际'),
    EmojiAsset('🫱', '右手 递 伸手'),
    EmojiAsset('🫲', '左手 递 伸手'),
    EmojiAsset('🫳', '手心向下 压 手势'),
    EmojiAsset('🫴', '手心向上 托 手势'),
    // 比划与态度
    EmojiAsset('👌', '好的 可以 完美'),
    EmojiAsset('🤌', '捏 意大利 手势'),
    EmojiAsset('🤏', '一点点 少 捏'),
    EmojiAsset('✌️', '耶 胜利 剪刀手'),
    EmojiAsset('🤞', '祈祷 好运 交叉'),
    EmojiAsset('🫰', '比心 手势 爱心'),
    EmojiAsset('🤟', '爱你 手势 喜欢'),
    EmojiAsset('🤘', '摇滚 手势 酷'),
    EmojiAsset('🤙', '打电话 手势 联系'),
    // 指向
    EmojiAsset('👈', '左 指向 指'),
    EmojiAsset('👉', '右 指向 指'),
    EmojiAsset('👆', '上 指向 指'),
    EmojiAsset('👇', '下 指向 指'),
    EmojiAsset('☝️', '重点 指向 一'),
    EmojiAsset('🫵', '指你 点名 你'),
    // 评价与拳
    EmojiAsset('👍', '赞 点赞 好'),
    EmojiAsset('👎', '踩 不好 差'),
    EmojiAsset('✊', '拳头 加油 力量'),
    EmojiAsset('👊', '拳头 碰拳 出击'),
    EmojiAsset('🤛', '左拳 碰拳 兄弟'),
    EmojiAsset('🤜', '右拳 碰拳 兄弟'),
    // 双手
    EmojiAsset('👏', '鼓掌 表扬 棒'),
    EmojiAsset('🙌', '举双手 欢呼 庆祝'),
    EmojiAsset('🫶', '比心 爱心 双手'),
    EmojiAsset('👐', '张开双手 拥抱 迎接'),
    EmojiAsset('🤲', '捧 双手 祈求'),
    EmojiAsset('🤝', '握手 合作 成交'),
    EmojiAsset('🙏', '拜托 祈祷 感谢'),
    // 动作
    EmojiAsset('✍️', '写字 记录 书写'),
    EmojiAsset('💅', '美甲 涂指甲 精致'),
    EmojiAsset('🤳', '自拍 拍照 手机'),
    EmojiAsset('💪', '加油 力量 肌肉'),
  ],
  '身体': [
    EmojiAsset('🦾', '机械臂 义肢 科技'),
    EmojiAsset('🦿', '机械腿 义肢 科技'),
    EmojiAsset('🦵', '腿 大腿 踢'),
    EmojiAsset('🦶', '脚 脚丫 踩'),
    EmojiAsset('👂', '耳朵 听 倾听'),
    EmojiAsset('🦻', '助听器 听力 辅助'),
    EmojiAsset('👃', '鼻子 闻 味道'),
    EmojiAsset('🧠', '大脑 思考 脑子'),
    EmojiAsset('🫀', '心脏 心跳 器官'),
    EmojiAsset('🫁', '肺 呼吸 器官'),
    EmojiAsset('🦷', '牙齿 牙 洁牙'),
    EmojiAsset('🦴', '骨头 骨骼 硬'),
    EmojiAsset('👀', '眼睛 看 围观'),
    EmojiAsset('👁️', '眼睛 注视 观察'),
    EmojiAsset('👅', '舌头 舔 调皮'),
    EmojiAsset('👄', '嘴唇 嘴 说话'),
    EmojiAsset('🩸', '血 血滴 献血'),
  ],
  '人物': [
    // 年龄段
    EmojiAsset('👶', '宝宝 婴儿 小孩'),
    EmojiAsset('🧒', '小孩 儿童 孩子'),
    EmojiAsset('👦', '男孩 少年 小男生'),
    EmojiAsset('👧', '女孩 少女 小女生'),
    EmojiAsset('🧑', '人 成人 中性'),
    EmojiAsset('👨', '男人 爸爸 男生'),
    EmojiAsset('👩', '女人 妈妈 女生'),
    EmojiAsset('🧔', '胡子 大叔 络腮'),
    EmojiAsset('👱', '金发 人物 造型'),
    EmojiAsset('🧓', '老人 长辈 年长'),
    EmojiAsset('👴', '爷爷 老人 外公'),
    EmojiAsset('👵', '奶奶 老人 外婆'),
    // 职业与身份
    EmojiAsset('👮', '警察 巡逻 治安'),
    EmojiAsset('🕵️', '侦探 调查 神秘'),
    EmojiAsset('💂', '卫兵 士兵 站岗'),
    EmojiAsset('🥷', '忍者 潜行 夜行'),
    EmojiAsset('👷', '工人 建筑 工地'),
    EmojiAsset('🤴', '王子 王室 贵族'),
    EmojiAsset('👸', '公主 王室 童话'),
    EmojiAsset('👳', '头巾 人物 民族'),
    EmojiAsset('👲', '瓜皮帽 人物 传统'),
    EmojiAsset('🧕', '头巾 女性 民族'),
    EmojiAsset('🤵', '新郎 礼服 婚礼'),
    EmojiAsset('👰', '新娘 婚礼 婚纱'),
    EmojiAsset('🤰', '孕妇 怀孕 待产'),
    EmojiAsset('🤱', '哺乳 育儿 母婴'),
    EmojiAsset('👼', '天使 小天使 纯真'),
    EmojiAsset('🎅', '圣诞老人 圣诞 礼物'),
    EmojiAsset('🤶', '圣诞奶奶 圣诞 节日'),
    // 幻想角色
    EmojiAsset('🦸', '超级英雄 英雄 拯救'),
    EmojiAsset('🦹', '反派 坏人 boss'),
    EmojiAsset('🧙', '魔法师 巫师 施法'),
    EmojiAsset('🧚', '仙子 精灵 翅膀'),
    EmojiAsset('🧛', '吸血鬼 万圣节 尖牙'),
    EmojiAsset('🧜', '人鱼 美人鱼 海洋'),
    EmojiAsset('🧝', '精灵 奇幻 尖耳'),
    EmojiAsset('🧞', '灯神 精灵 许愿'),
    EmojiAsset('🧟', '僵尸 万圣节 丧尸'),
    // 姿态与表达
    EmojiAsset('🙍', '皱眉 不开心 郁闷'),
    EmojiAsset('🙎', '撇嘴 不满 闹脾气'),
    EmojiAsset('🙅', '拒绝 不行 打叉'),
    EmojiAsset('🙆', '同意 好的 打圈'),
    EmojiAsset('💁', '介绍 摊手 服务'),
    EmojiAsset('🙋', '举手 提问 我来'),
    EmojiAsset('🧏', '失聪 手语 听障'),
    EmojiAsset('🙇', '鞠躬 道歉 拜托'),
    EmojiAsset('🤦', '捂脸 无语 扶额'),
    EmojiAsset('🤷', '摊手 无奈 耸肩'),
    // 日常与休息
    EmojiAsset('💆', '按摩 放松 护理'),
    EmojiAsset('💇', '理发 剪发 发型'),
    EmojiAsset('🚶', '走路 散步 溜达'),
    EmojiAsset('🧍', '站立 站着 等人'),
    EmojiAsset('🧎', '跪 跪坐 恳求'),
    EmojiAsset('🏃', '跑步 运动 锻炼'),
    EmojiAsset('💃', '跳舞 舞蹈 热情'),
    EmojiAsset('🕺', '跳舞 男生 舞步'),
    EmojiAsset('🕴️', '西装 商务 悬浮'),
    EmojiAsset('👯', '双人 兔女郎 舞蹈'),
    EmojiAsset('🧖', '桑拿 蒸汽 放松'),
    EmojiAsset('🧘', '冥想 瑜伽 放松'),
    EmojiAsset('🛀', '泡澡 洗澡 放松'),
    EmojiAsset('🛌', '躺下 睡觉 休息'),
    // 关系
    EmojiAsset('👪', '家庭 家人 全家'),
    EmojiAsset('👨‍👩‍👧‍👦', '一家四口 全家福 家庭'),
    EmojiAsset('💑', '情侣 恋爱 约会'),
    EmojiAsset('💏', '接吻 情侣 亲吻'),
    EmojiAsset('👫', '朋友 拉手 男女'),
    EmojiAsset('👭', '闺蜜 姐妹 手拉手'),
    EmojiAsset('👬', '兄弟 好友 手拉手'),
    EmojiAsset('🗣️', '说话 发言 讲'),
    EmojiAsset('👤', '剪影 用户 个人'),
    EmojiAsset('👥', '双人 群体 伙伴'),
    EmojiAsset('🫂', '拥抱 抱抱 安慰'),
    EmojiAsset('👣', '脚印 足迹 走过'),
  ],
  '动物': [
    // 犬科与猫科
    EmojiAsset('🐶', '狗 小狗 汪'),
    EmojiAsset('🐕', '狗 遛狗 犬'),
    EmojiAsset('🦮', '导盲犬 服务犬 陪伴'),
    EmojiAsset('🐩', '贵宾犬 卷毛 狗'),
    EmojiAsset('🐺', '狼 野狼 嚎'),
    EmojiAsset('🦊', '狐狸 狡黠 橘'),
    EmojiAsset('🦝', '浣熊 小浣熊 洗手'),
    EmojiAsset('🐱', '猫 猫咪 喵'),
    EmojiAsset('🐈', '猫 家猫 小猫'),
    EmojiAsset('🦁', '狮子 兽王 威武'),
    EmojiAsset('🐯', '老虎 虎 虎头'),
    EmojiAsset('🐅', '老虎 猛虎 森林'),
    EmojiAsset('🐆', '豹 猎豹 斑点'),
    // 马与蹄类
    EmojiAsset('🐴', '马 马头 骏马'),
    EmojiAsset('🐎', '马 赛马 奔跑'),
    EmojiAsset('🦄', '独角兽 梦幻 彩虹'),
    EmojiAsset('🦓', '斑马 条纹 草原'),
    EmojiAsset('🦌', '鹿 小鹿 森林'),
    EmojiAsset('🦬', '野牛 草原 壮'),
    EmojiAsset('🐮', '牛 奶牛 哞'),
    EmojiAsset('🐂', '公牛 牛 力气'),
    EmojiAsset('🐃', '水牛 耕田 牛'),
    EmojiAsset('🐄', '奶牛 牛奶 牧场'),
    EmojiAsset('🐷', '猪 小猪 粉'),
    EmojiAsset('🐖', '猪 肥猪 猪身'),
    EmojiAsset('🐗', '野猪 獠牙 山林'),
    EmojiAsset('🐽', '猪鼻 猪 鼻子'),
    EmojiAsset('🐏', '公羊 羊 弯角'),
    EmojiAsset('🐑', '羊 绵羊 咩'),
    EmojiAsset('🐐', '山羊 羊 胡子'),
    EmojiAsset('🐪', '骆驼 单峰 沙漠'),
    EmojiAsset('🐫', '骆驼 双峰 沙漠'),
    EmojiAsset('🦙', '羊驼 草泥马 毛'),
    EmojiAsset('🦒', '长颈鹿 长脖子 高'),
    EmojiAsset('🐘', '大象 象 长鼻'),
    EmojiAsset('🦣', '猛犸象 远古 长毛'),
    EmojiAsset('🦏', '犀牛 独角 厚皮'),
    EmojiAsset('🦛', '河马 大嘴 水'),
    // 小型动物
    EmojiAsset('🐭', '老鼠 鼠 吱'),
    EmojiAsset('🐁', '老鼠 小鼠 白鼠'),
    EmojiAsset('🐀', '大老鼠 鼠 灰'),
    EmojiAsset('🐹', '仓鼠 小仓鼠 圆'),
    EmojiAsset('🐰', '兔子 兔 小白兔'),
    EmojiAsset('🐇', '兔 兔子 蹦跳'),
    EmojiAsset('🐿️', '松鼠 坚果 尾巴'),
    EmojiAsset('🦫', '河狸 水坝 啃木'),
    EmojiAsset('🦔', '刺猬 小刺球 扎'),
    EmojiAsset('🦇', '蝙蝠 夜行 万圣节'),
    EmojiAsset('🐻', '熊 小熊 抱抱'),
    EmojiAsset('🐨', '考拉 树袋熊 慵懒'),
    EmojiAsset('🐼', '熊猫 国宝 黑白'),
    EmojiAsset('🦥', '树懒 慢 悠闲'),
    EmojiAsset('🦦', '水獭 可爱 游泳'),
    EmojiAsset('🦨', '臭鼬 气味 黑白'),
    EmojiAsset('🦘', '袋鼠 跳 澳洲'),
    EmojiAsset('🦡', '獾 挖洞 野生'),
    EmojiAsset('🐒', '猴 猴子 淘气'),
    EmojiAsset('🐵', '猴子 猴脸 顽皮'),
    EmojiAsset('🦍', '大猩猩 力量 丛林'),
    EmojiAsset('🦧', '猩猩 红毛 丛林'),
    EmojiAsset('🐾', '爪印 脚印 宠物'),
    // 鸟类
    EmojiAsset('🦃', '火鸡 感恩节 烤'),
    EmojiAsset('🐔', '鸡 母鸡 咯咯'),
    EmojiAsset('🐓', '公鸡 打鸣 清晨'),
    EmojiAsset('🐣', '破壳 小鸡 孵化'),
    EmojiAsset('🐤', '小鸡 雏鸟 黄'),
    EmojiAsset('🐥', '小鸡 正面 毛茸'),
    EmojiAsset('🐦', '小鸟 鸟 啾'),
    EmojiAsset('🐧', '企鹅 南极 憨'),
    EmojiAsset('🕊️', '白鸽 和平 自由'),
    EmojiAsset('🦅', '老鹰 鹰 翱翔'),
    EmojiAsset('🦆', '鸭子 鸭 嘎'),
    EmojiAsset('🦢', '天鹅 优雅 湖'),
    EmojiAsset('🦉', '猫头鹰 夜猫 智慧'),
    EmojiAsset('🪶', '羽毛 轻盈 飘'),
    EmojiAsset('🦩', '火烈鸟 粉色 优雅'),
    EmojiAsset('🦚', '孔雀 开屏 华丽'),
    EmojiAsset('🦜', '鹦鹉 学舌 彩色'),
    // 爬行与两栖
    EmojiAsset('🐸', '青蛙 蛙 呱'),
    EmojiAsset('🐊', '鳄鱼 凶猛 河'),
    EmojiAsset('🐢', '乌龟 龟 慢'),
    EmojiAsset('🦎', '蜥蜴 壁虎 爬行'),
    EmojiAsset('🐍', '蛇 小蛇 缠'),
    EmojiAsset('🐲', '龙头 龙 中国龙'),
    EmojiAsset('🐉', '龙 神龙 祥瑞'),
    EmojiAsset('🦕', '恐龙 长颈龙 远古'),
    EmojiAsset('🦖', '霸王龙 恐龙 凶猛'),
    // 海洋
    EmojiAsset('🐳', '鲸鱼 鲸 喷水'),
    EmojiAsset('🐋', '鲸 蓝鲸 深海'),
    EmojiAsset('🐬', '海豚 聪明 跃'),
    EmojiAsset('🦭', '海豹 圆滚 冰'),
    EmojiAsset('🐟', '鱼 小鱼 游'),
    EmojiAsset('🐠', '鱼 热带鱼 珊瑚'),
    EmojiAsset('🐡', '河豚 鼓 鱼'),
    EmojiAsset('🦈', '鲨鱼 大白鲨 海'),
    EmojiAsset('🐙', '章鱼 触手 海'),
    EmojiAsset('🐚', '贝壳 海边 沙滩'),
    EmojiAsset('🪸', '珊瑚 海底 礁'),
    EmojiAsset('🦀', '螃蟹 蟹 横行'),
    EmojiAsset('🦞', '龙虾 大虾 海鲜'),
    EmojiAsset('🦐', '虾 小虾 海鲜'),
    EmojiAsset('🦑', '鱿鱼 墨鱼 海鲜'),
    EmojiAsset('🦪', '牡蛎 生蚝 海鲜'),
    // 昆虫与微生物
    EmojiAsset('🐌', '蜗牛 慢 壳'),
    EmojiAsset('🦋', '蝴蝶 春天 飞舞'),
    EmojiAsset('🐛', '毛毛虫 虫 爬'),
    EmojiAsset('🐜', '蚂蚁 勤劳 小'),
    EmojiAsset('🐝', '蜜蜂 采蜜 嗡'),
    EmojiAsset('🪲', '甲虫 昆虫 壳'),
    EmojiAsset('🐞', '瓢虫 七星 虫'),
    EmojiAsset('🦗', '蟋蟀 蛐蛐 夏夜'),
    EmojiAsset('🪳', '蟑螂 害虫 小强'),
    EmojiAsset('🕷️', '蜘蛛 八爪 结网'),
    EmojiAsset('🕸️', '蛛网 蜘蛛网 尘封'),
    EmojiAsset('🦂', '蝎子 毒 沙漠'),
    EmojiAsset('🦟', '蚊子 叮 夏天'),
    EmojiAsset('🪰', '苍蝇 嗡嗡 讨厌'),
    EmojiAsset('🪱', '蚯蚓 松土 泥'),
    EmojiAsset('🦠', '细菌 病毒 微生物'),
  ],
  '植物': [
    // 花
    EmojiAsset('💐', '花束 鲜花 礼物'),
    EmojiAsset('🌸', '樱花 花 春天'),
    EmojiAsset('💮', '白花 花朵 印章'),
    EmojiAsset('🪷', '莲花 荷花 清雅'),
    EmojiAsset('🏵️', '花结 装饰 勋花'),
    EmojiAsset('🌹', '玫瑰 花 表白'),
    EmojiAsset('🥀', '枯萎 凋谢 落寞'),
    EmojiAsset('🌺', '扶桑 花 热带'),
    EmojiAsset('🌻', '向日葵 太阳花 阳光'),
    EmojiAsset('🌼', '雏菊 小花 清新'),
    EmojiAsset('🌷', '郁金香 花 春'),
    // 枝叶
    EmojiAsset('🌱', '发芽 种子 新生'),
    EmojiAsset('🪴', '盆栽 绿植 植物'),
    EmojiAsset('🌲', '松树 常青树 冬'),
    EmojiAsset('🌳', '树 大树 阴凉'),
    EmojiAsset('🌴', '棕榈 椰子树 海边'),
    EmojiAsset('🌵', '仙人掌 多肉 沙漠'),
    EmojiAsset('🌾', '稻穗 麦 秋收'),
    EmojiAsset('🌿', '绿叶 香草 清新'),
    EmojiAsset('☘️', '三叶草 幸运 绿'),
    EmojiAsset('🍀', '四叶草 幸运 许愿'),
    EmojiAsset('🍁', '枫叶 秋天 红'),
    EmojiAsset('🍂', '落叶 秋天 飘'),
    EmojiAsset('🍃', '树叶 风 清新'),
    EmojiAsset('🍄', '蘑菇 菌 森林'),
    EmojiAsset('🌰', '栗子 坚果 秋'),
    EmojiAsset('🎋', '竹 许愿 七夕'),
    EmojiAsset('🎍', '松竹 新年 门松'),
    EmojiAsset('🪵', '木头 木材 原木'),
    EmojiAsset('🪨', '石头 石 硬'),
  ],
  '天气': [
    // 日与月
    EmojiAsset('☀️', '晴天 太阳 阳光'),
    EmojiAsset('🌞', '太阳 笑脸 晴朗'),
    EmojiAsset('🌝', '满月 月亮 笑脸'),
    EmojiAsset('🌛', '弯月 月亮 笑脸'),
    EmojiAsset('🌜', '弯月 月亮 睡觉'),
    EmojiAsset('🌚', '新月 月亮 黑脸'),
    EmojiAsset('🌑', '新月 月相 暗'),
    EmojiAsset('🌒', '蛾眉月 月相 初'),
    EmojiAsset('🌓', '上弦月 月相 半'),
    EmojiAsset('🌔', '盈凸月 月相 将圆'),
    EmojiAsset('🌕', '满月 月圆 中秋'),
    EmojiAsset('🌖', '亏凸月 月相 渐缺'),
    EmojiAsset('🌗', '下弦月 月相 半'),
    EmojiAsset('🌘', '残月 月相 将尽'),
    EmojiAsset('🌙', '月亮 夜晚 晚安'),
    // 星与宇宙
    EmojiAsset('🪐', '土星 行星 星球'),
    EmojiAsset('⭐', '星星 星 收藏'),
    EmojiAsset('🌟', '闪耀 星光 亮'),
    EmojiAsset('✨', '闪光 亮晶晶 高光'),
    EmojiAsset('💫', '旋转 星星 眩晕'),
    EmojiAsset('☄️', '彗星 流星 划过'),
    EmojiAsset('🌠', '流星 许愿 夜空'),
    EmojiAsset('🌌', '银河 星空 浪漫'),
    // 云雨风雪
    EmojiAsset('☁️', '阴天 云朵 多云'),
    EmojiAsset('⛅', '多云 云 间晴'),
    EmojiAsset('🌤️', '晴间多云 天气 晴'),
    EmojiAsset('🌥️', '多云 阴 天气'),
    EmojiAsset('🌦️', '太阳雨 阵雨 天气'),
    EmojiAsset('🌧️', '下雨 雨天 阴雨'),
    EmojiAsset('⛈️', '雷雨 打雷 暴雨'),
    EmojiAsset('🌩️', '闪电 雷 电闪'),
    EmojiAsset('🌨️', '下雪 雪 天气'),
    EmojiAsset('🌫️', '雾 雾天 朦胧'),
    EmojiAsset('🌬️', '风 吹风 大风'),
    EmojiAsset('🌪️', '龙卷风 旋风 风暴'),
    EmojiAsset('🌀', '台风 漩涡 旋转'),
    EmojiAsset('🌈', '彩虹 雨后 七彩'),
    EmojiAsset('❄️', '雪花 下雪 冬天'),
    EmojiAsset('☃️', '雪人 冬天 堆雪'),
    EmojiAsset('⛄', '雪人 堆雪人 冬'),
    EmojiAsset('☔', '下雨 雨伞 雨具'),
    EmojiAsset('💧', '水滴 水 一滴'),
    EmojiAsset('🌊', '海浪 大海 波浪'),
    EmojiAsset('🔥', '火 火焰 热'),
    EmojiAsset('🌡️', '温度 气温 冷热'),
    // 地景与晨昏
    EmojiAsset('🌍', '地球 世界 欧非'),
    EmojiAsset('🌎', '地球 美洲 世界'),
    EmojiAsset('🌏', '地球 亚洲 世界'),
    EmojiAsset('🌐', '地球 网络 全球'),
    EmojiAsset('🌋', '火山 喷发 岩浆'),
    EmojiAsset('🌅', '日出 早晨 海上'),
    EmojiAsset('🌄', '日出 山 清晨'),
    EmojiAsset('🌇', '日落 黄昏 余晖'),
  ],
  '食物': [
    // 水果
    EmojiAsset('🍇', '葡萄 水果 串'),
    EmojiAsset('🍈', '甜瓜 香瓜 水果'),
    EmojiAsset('🍉', '西瓜 夏天 水果'),
    EmojiAsset('🍊', '橘子 橙子 水果'),
    EmojiAsset('🍋', '柠檬 酸 水果'),
    EmojiAsset('🍌', '香蕉 水果 黄'),
    EmojiAsset('🍍', '菠萝 凤梨 水果'),
    EmojiAsset('🥭', '芒果 水果 热带'),
    EmojiAsset('🍎', '苹果 水果 红'),
    EmojiAsset('🍏', '青苹果 水果 酸'),
    EmojiAsset('🍐', '梨 水果 秋'),
    EmojiAsset('🍑', '桃子 蜜桃 水果'),
    EmojiAsset('🍒', '樱桃 水果 红'),
    EmojiAsset('🍓', '草莓 水果 甜'),
    EmojiAsset('🫐', '蓝莓 水果 小果'),
    EmojiAsset('🥝', '猕猴桃 奇异果 水果'),
    EmojiAsset('🍅', '番茄 西红柿 蔬菜'),
    EmojiAsset('🫒', '橄榄 果实 油'),
    EmojiAsset('🥥', '椰子 水果 热带'),
    // 蔬菜与坚果
    EmojiAsset('🥑', '牛油果 鳄梨 健康'),
    EmojiAsset('🍆', '茄子 蔬菜 紫'),
    EmojiAsset('🥔', '土豆 马铃薯 蔬菜'),
    EmojiAsset('🥕', '胡萝卜 蔬菜 橙'),
    EmojiAsset('🌽', '玉米 蔬菜 粮食'),
    EmojiAsset('🌶️', '辣椒 辣 川菜'),
    EmojiAsset('🫑', '甜椒 青椒 蔬菜'),
    EmojiAsset('🥒', '黄瓜 蔬菜 清爽'),
    EmojiAsset('🥬', '青菜 生菜 蔬菜'),
    EmojiAsset('🥦', '西兰花 蔬菜 健康'),
    EmojiAsset('🧄', '大蒜 调味 香'),
    EmojiAsset('🧅', '洋葱 调味 辣眼'),
    EmojiAsset('🥜', '花生 坚果 香'),
    EmojiAsset('🫘', '豆子 豆类 杂粮'),
    // 主食与烘焙
    EmojiAsset('🍞', '面包 早餐 吐司'),
    EmojiAsset('🥐', '可颂 牛角包 早餐'),
    EmojiAsset('🥖', '法棍 面包 硬'),
    EmojiAsset('🫓', '馕 扁面包 烤'),
    EmojiAsset('🥨', '碱水结 面包 咸'),
    EmojiAsset('🥯', '贝果 早餐 面包'),
    EmojiAsset('🥞', '松饼 薄煎饼 早餐'),
    EmojiAsset('🧇', '华夫饼 早餐 格子'),
    EmojiAsset('🧀', '奶酪 芝士 香'),
    // 荤菜与快餐
    EmojiAsset('🍖', '肉 排骨 烤肉'),
    EmojiAsset('🍗', '鸡腿 炸鸡 香'),
    EmojiAsset('🥩', '牛排 生肉 蛋白'),
    EmojiAsset('🥓', '培根 早餐 咸'),
    EmojiAsset('🍔', '汉堡 快餐 牛肉'),
    EmojiAsset('🍟', '薯条 快餐 油炸'),
    EmojiAsset('🍕', '披萨 意大利 芝士'),
    EmojiAsset('🌭', '热狗 快餐 香肠'),
    EmojiAsset('🥪', '三明治 早餐 便携'),
    EmojiAsset('🌮', '塔可 墨西哥 卷'),
    EmojiAsset('🌯', '卷饼 墨西哥 裹'),
    EmojiAsset('🫔', '玉米粽 墨西哥 蒸'),
    EmojiAsset('🥙', '皮塔卷 中东 夹馅'),
    EmojiAsset('🧆', '豆丸 中东 炸'),
    EmojiAsset('🥚', '鸡蛋 蛋 蛋白'),
    EmojiAsset('🍳', '煎蛋 早餐 平底锅'),
    EmojiAsset('🥘', '炖菜 焖锅 家常'),
    EmojiAsset('🍲', '火锅 炖汤 热乎'),
    EmojiAsset('🫕', '芝士火锅 蘸 西式'),
    EmojiAsset('🥣', '麦片 一碗 早餐'),
    EmojiAsset('🥗', '沙拉 蔬菜 健康'),
    EmojiAsset('🍿', '爆米花 电影 零食'),
    EmojiAsset('🧈', '黄油 烘焙 香'),
    EmojiAsset('🧂', '盐 调味 咸'),
    EmojiAsset('🥫', '罐头 储备 食品'),
    // 亚洲美食
    EmojiAsset('🍱', '便当 盒饭 日式'),
    EmojiAsset('🍘', '米饼 仙贝 零食'),
    EmojiAsset('🍙', '饭团 日式 便当'),
    EmojiAsset('🍚', '米饭 白饭 主食'),
    EmojiAsset('🍛', '咖喱饭 咖喱 盖饭'),
    EmojiAsset('🍜', '拉面 面条 汤面'),
    EmojiAsset('🍝', '意面 意大利面 番茄'),
    EmojiAsset('🍠', '烤红薯 红薯 冬天'),
    EmojiAsset('🍢', '关东煮 串 暖'),
    EmojiAsset('🍣', '寿司 日料 生鱼'),
    EmojiAsset('🍤', '天妇罗 炸虾 日料'),
    EmojiAsset('🍥', '鱼板 拉面 配菜'),
    EmojiAsset('🥮', '月饼 中秋 团圆'),
    EmojiAsset('🍡', '团子 丸子 日式'),
    EmojiAsset('🥟', '饺子 中餐 团圆'),
    EmojiAsset('🥠', '幸运饼干 签 运势'),
    EmojiAsset('🥡', '打包盒 外卖 带走'),
    // 甜点
    EmojiAsset('🍦', '冰淇淋 甜筒 夏天'),
    EmojiAsset('🍧', '刨冰 冰沙 消暑'),
    EmojiAsset('🍨', '冰淇淋 甜点 一球'),
    EmojiAsset('🍩', '甜甜圈 甜点 糖霜'),
    EmojiAsset('🍪', '饼干 甜点 曲奇'),
    EmojiAsset('🎂', '生日蛋糕 庆祝 蜡烛'),
    EmojiAsset('🍰', '蛋糕 甜点 切块'),
    EmojiAsset('🧁', '纸杯蛋糕 甜点 奶油'),
    EmojiAsset('🥧', '派 馅饼 烘焙'),
    EmojiAsset('🍫', '巧克力 甜 可可'),
    EmojiAsset('🍬', '糖果 甜 零食'),
    EmojiAsset('🍭', '棒棒糖 甜 童年'),
    EmojiAsset('🍮', '布丁 甜点 焦糖'),
    EmojiAsset('🍯', '蜂蜜 甜 罐'),
    // 饮品
    EmojiAsset('🍼', '奶瓶 婴儿 牛奶'),
    EmojiAsset('🥛', '牛奶 一杯 早餐'),
    EmojiAsset('☕', '咖啡 提神 下午茶'),
    EmojiAsset('🫖', '茶壶 泡茶 待客'),
    EmojiAsset('🍵', '茶 绿茶 抹茶'),
    EmojiAsset('🍶', '清酒 日式 小酌'),
    EmojiAsset('🍾', '香槟 开瓶 庆祝'),
    EmojiAsset('🍷', '红酒 葡萄酒 微醺'),
    EmojiAsset('🍸', '鸡尾酒 调酒 夜'),
    EmojiAsset('🍹', '果酒 热带 饮品'),
    EmojiAsset('🍺', '啤酒 干杯 爽'),
    EmojiAsset('🍻', '干杯 啤酒 聚会'),
    EmojiAsset('🥂', '干杯 香槟 庆祝'),
    EmojiAsset('🥃', '威士忌 烈酒 一杯'),
    EmojiAsset('🫗', '倒水 洒 液体'),
    EmojiAsset('🥤', '饮料 汽水 冷饮'),
    EmojiAsset('🧋', '奶茶 珍珠 甜'),
    EmojiAsset('🧃', '果汁 饮料 盒装'),
    EmojiAsset('🧉', '马黛茶 饮品 南美'),
    EmojiAsset('🧊', '冰块 冰 降温'),
    // 餐具
    EmojiAsset('🥢', '筷子 餐具 中式'),
    EmojiAsset('🍽️', '餐具 用餐 刀叉'),
    EmojiAsset('🍴', '刀叉 吃饭 西餐'),
    EmojiAsset('🥄', '勺子 汤匙 舀'),
    EmojiAsset('🔪', '菜刀 切 厨房'),
    EmojiAsset('🫙', '罐子 玻璃瓶 储存'),
    EmojiAsset('🏺', '陶罐 古物 器皿'),
  ],
  '活动': [
    // 节庆
    EmojiAsset('🎉', '庆祝 派对 撒花'),
    EmojiAsset('🎊', '彩球 庆祝 彩带'),
    EmojiAsset('🎈', '气球 生日 派对'),
    EmojiAsset('🎁', '礼物 惊喜 送礼'),
    EmojiAsset('🎀', '蝴蝶结 装饰 丝带'),
    EmojiAsset('🎗️', '丝带 纪念 公益'),
    EmojiAsset('🎄', '圣诞树 圣诞 冬'),
    EmojiAsset('🎃', '南瓜 万圣节 鬼脸'),
    EmojiAsset('🧨', '鞭炮 新年 热闹'),
    EmojiAsset('🎆', '烟花 跨年 绚烂'),
    EmojiAsset('🎇', '烟花 夜晚 火花'),
    EmojiAsset('🧧', '红包 新年 压岁'),
    EmojiAsset('🏮', '灯笼 新年 中式'),
    EmojiAsset('🎏', '鲤鱼旗 儿童节 日式'),
    EmojiAsset('🎐', '风铃 夏日 清凉'),
    EmojiAsset('🎑', '赏月 中秋 秋'),
    EmojiAsset('🎎', '人偶 女儿节 日式'),
    EmojiAsset('🪅', '彩罐 派对 敲'),
    EmojiAsset('🪩', '镜面球 蹦迪 舞厅'),
    EmojiAsset('🎫', '门票 入场 票'),
    EmojiAsset('🎟️', '票 演出 入场券'),
    // 手作与游戏
    EmojiAsset('🎨', '画画 绘画 艺术'),
    EmojiAsset('🎭', '戏剧 表演 面具'),
    EmojiAsset('🖼️', '画框 相框 展示'),
    EmojiAsset('🧵', '线 缝纫 手工'),
    EmojiAsset('🪡', '缝针 针线 手作'),
    EmojiAsset('🧶', '毛线 编织 手工'),
    EmojiAsset('🪢', '绳结 打结 手作'),
    EmojiAsset('🎮', '游戏 打游戏 手柄'),
    EmojiAsset('🕹️', '摇杆 街机 复古'),
    EmojiAsset('🎰', '老虎机 抽奖 运气'),
    EmojiAsset('🎲', '骰子 桌游 随机'),
    EmojiAsset('🧩', '拼图 益智 拼'),
    EmojiAsset('♟️', '棋子 国际象棋 对弈'),
    EmojiAsset('🎯', '目标 靶心 计划'),
    EmojiAsset('🎳', '保龄球 运动 娱乐'),
    EmojiAsset('🪁', '风筝 放风筝 春'),
    EmojiAsset('🎴', '花札 纸牌 日式'),
    EmojiAsset('🀄', '麻将 红中 牌'),
    EmojiAsset('🃏', '小丑牌 扑克 王牌'),
    // 音乐
    EmojiAsset('🎤', '唱歌 麦克风 演唱'),
    EmojiAsset('🎧', '耳机 听歌 音乐'),
    EmojiAsset('🎼', '乐谱 五线谱 作曲'),
    EmojiAsset('🎵', '音符 音乐 旋律'),
    EmojiAsset('🎶', '音乐 旋律 歌声'),
    EmojiAsset('🎙️', '麦克风 录音 播客'),
    EmojiAsset('🎚️', '推子 音量 调节'),
    EmojiAsset('🎛️', '旋钮 调音 控制'),
    EmojiAsset('📻', '收音机 电台 复古'),
    EmojiAsset('🎷', '萨克斯 乐器 爵士'),
    EmojiAsset('🪗', '手风琴 乐器 民谣'),
    EmojiAsset('🎸', '吉他 乐器 弹唱'),
    EmojiAsset('🎹', '钢琴 乐器 键盘'),
    EmojiAsset('🎺', '小号 乐器 铜管'),
    EmojiAsset('🎻', '小提琴 乐器 弦乐'),
    EmojiAsset('🪕', '班卓 乐器 弹拨'),
    EmojiAsset('🥁', '鼓 打鼓 节奏'),
    EmojiAsset('🪘', '长鼓 打击乐 手鼓'),
    // 球类
    EmojiAsset('⚽', '足球 运动 球'),
    EmojiAsset('🏀', '篮球 运动 球'),
    EmojiAsset('🏈', '橄榄球 美式 运动'),
    EmojiAsset('⚾', '棒球 运动 球'),
    EmojiAsset('🥎', '垒球 运动 球'),
    EmojiAsset('🎾', '网球 运动 球拍'),
    EmojiAsset('🏐', '排球 运动 球'),
    EmojiAsset('🏉', '橄榄球 英式 运动'),
    EmojiAsset('🥏', '飞盘 运动 户外'),
    EmojiAsset('🎱', '台球 桌球 八号'),
    EmojiAsset('🏓', '乒乓球 运动 球拍'),
    EmojiAsset('🏸', '羽毛球 运动 球拍'),
    EmojiAsset('🥅', '球门 守门 进球'),
    EmojiAsset('🏒', '冰球 曲棍 冰上'),
    EmojiAsset('🏑', '曲棍球 运动 草地'),
    EmojiAsset('🥍', '长曲棍球 运动 网兜'),
    EmojiAsset('🏏', '板球 运动 击球'),
    EmojiAsset('🪃', '回旋镖 投掷 户外'),
    // 运动与户外
    EmojiAsset('🥊', '拳击 拳套 格斗'),
    EmojiAsset('🥋', '道服 武术 柔道'),
    EmojiAsset('🛹', '滑板 街头 极限'),
    EmojiAsset('🛼', '旱冰鞋 轮滑 运动'),
    EmojiAsset('⛸️', '溜冰 冰刀 冰上'),
    EmojiAsset('🎿', '滑雪 双板 冬季'),
    EmojiAsset('🛷', '雪橇 滑雪 冬'),
    EmojiAsset('🥌', '冰壶 运动 冰上'),
    EmojiAsset('⛷️', '滑雪 运动 雪道'),
    EmojiAsset('🏂', '单板滑雪 运动 雪'),
    EmojiAsset('🪂', '跳伞 极限 飞'),
    EmojiAsset('🏋️', '举重 健身 力量'),
    EmojiAsset('🤸', '体操 翻跟头 柔韧'),
    EmojiAsset('🤼', '摔跤 格斗 较量'),
    EmojiAsset('🤺', '击剑 运动 剑'),
    EmojiAsset('🤾', '手球 运动 投掷'),
    EmojiAsset('🤹', '杂耍 抛球 表演'),
    EmojiAsset('🧗', '攀岩 运动 攀登'),
    EmojiAsset('🚴', '骑行 骑车 运动'),
    EmojiAsset('🚵', '山地车 越野 骑行'),
    EmojiAsset('🏇', '赛马 骑马 竞速'),
    EmojiAsset('🏄', '冲浪 海边 浪'),
    EmojiAsset('🏊', '游泳 运动 泳池'),
    EmojiAsset('🤽', '水球 运动 泳池'),
    EmojiAsset('🚣', '划船 皮划艇 水上'),
    EmojiAsset('🤿', '潜水 面镜 深潜'),
    EmojiAsset('🎣', '钓鱼 垂钓 悠闲'),
    EmojiAsset('⛺', '露营 帐篷 户外'),
    // 荣誉
    EmojiAsset('🏆', '奖杯 冠军 第一'),
    EmojiAsset('🏅', '奖牌 获奖 荣誉'),
    EmojiAsset('🥇', '金牌 第一 冠军'),
    EmojiAsset('🥈', '银牌 第二 亚军'),
    EmojiAsset('🥉', '铜牌 第三 季军'),
    EmojiAsset('🎖️', '勋章 荣誉 军功'),
  ],
  '旅行': [
    // 陆上交通
    EmojiAsset('🚗', '汽车 开车 自驾'),
    EmojiAsset('🚕', '出租车 打车 的士'),
    EmojiAsset('🚙', '越野车 汽车 家用'),
    EmojiAsset('🚌', '公交 巴士 通勤'),
    EmojiAsset('🚎', '电车 无轨 公交'),
    EmojiAsset('🏎️', '赛车 赛道 竞速'),
    EmojiAsset('🚓', '警车 警察 出警'),
    EmojiAsset('🚑', '救护车 急救 医疗'),
    EmojiAsset('🚒', '消防车 消防 救火'),
    EmojiAsset('🚐', '面包车 中巴 接送'),
    EmojiAsset('🛻', '皮卡 货车 拉货'),
    EmojiAsset('🚚', '货车 卡车 运输'),
    EmojiAsset('🚛', '大卡车 挂车 物流'),
    EmojiAsset('🚜', '拖拉机 农用 田地'),
    EmojiAsset('🛵', '电动车 踏板 代步'),
    EmojiAsset('🏍️', '摩托车 机车 骑行'),
    EmojiAsset('🛺', '三轮车 突突车 代步'),
    EmojiAsset('🚲', '自行车 骑行 单车'),
    EmojiAsset('🛴', '滑板车 代步 通勤'),
    EmojiAsset('🦽', '手动轮椅 辅助 出行'),
    EmojiAsset('🦼', '电动轮椅 辅助 出行'),
    EmojiAsset('🚔', '警车 巡逻 迎面'),
    EmojiAsset('🚍', '公交 迎面 车'),
    EmojiAsset('🚘', '汽车 迎面 车'),
    EmojiAsset('🚖', '出租车 迎面 打车'),
    // 轨道交通
    EmojiAsset('🚡', '缆车 索道 空中'),
    EmojiAsset('🚠', '山地缆车 索道 登山'),
    EmojiAsset('🚟', '悬挂列车 轨道 交通'),
    EmojiAsset('🚃', '车厢 列车 通勤'),
    EmojiAsset('🚋', '有轨电车 车厢 城市'),
    EmojiAsset('🚞', '山地火车 观光 铁道'),
    EmojiAsset('🚝', '单轨 列车 轻轨'),
    EmojiAsset('🚄', '高铁 火车 出行'),
    EmojiAsset('🚅', '高铁 子弹头 提速'),
    EmojiAsset('🚈', '轻轨 城铁 通勤'),
    EmojiAsset('🚂', '蒸汽机车 火车 复古'),
    EmojiAsset('🚆', '列车 火车 铁路'),
    EmojiAsset('🚇', '地铁 通勤 换乘'),
    EmojiAsset('🚊', '有轨电车 交通 城市'),
    EmojiAsset('🚉', '火车站 车站 出发'),
    // 空中与水上
    EmojiAsset('✈️', '飞机 旅行 出行'),
    EmojiAsset('🛫', '起飞 出发 航班'),
    EmojiAsset('🛬', '降落 抵达 航班'),
    EmojiAsset('🛩️', '小飞机 私人机 螺旋桨'),
    EmojiAsset('💺', '座位 靠窗 航班'),
    EmojiAsset('🚁', '直升机 飞行 救援'),
    EmojiAsset('🛸', '飞碟 外星 神秘'),
    EmojiAsset('🚀', '火箭 出发 冲'),
    EmojiAsset('🛰️', '卫星 太空 信号'),
    EmojiAsset('🛶', '独木舟 划船 溪流'),
    EmojiAsset('⛵', '帆船 海边 航行'),
    EmojiAsset('🛥️', '快艇 游艇 海上'),
    EmojiAsset('🚤', '快艇 冲浪艇 水上'),
    EmojiAsset('🛳️', '客轮 游轮 度假'),
    EmojiAsset('⛴️', '渡轮 摆渡 航线'),
    EmojiAsset('🚢', '轮船 邮轮 远航'),
    EmojiAsset('⚓', '锚 停泊 航海'),
    // 路况与设施
    EmojiAsset('🚏', '车站 站牌 等车'),
    EmojiAsset('🛣️', '高速 公路 自驾'),
    EmojiAsset('🛤️', '铁轨 铁路 远方'),
    EmojiAsset('⛽', '加油站 加油 补给'),
    EmojiAsset('🚧', '施工 路障 注意'),
    EmojiAsset('🚨', '警灯 警报 紧急'),
    EmojiAsset('🚦', '红绿灯 信号 路口'),
    EmojiAsset('🚥', '信号灯 交通 横向'),
    // 地图与地标
    EmojiAsset('🗺️', '地图 路线 攻略'),
    EmojiAsset('🧭', '指南针 方向 探索'),
    EmojiAsset('🗿', '石像 复活节岛 神秘'),
    EmojiAsset('🗽', '自由女神 纽约 地标'),
    EmojiAsset('🗼', '铁塔 东京 地标'),
    EmojiAsset('🏰', '城堡 童话 欧式'),
    EmojiAsset('🏯', '天守阁 日式 古建'),
    EmojiAsset('🏟️', '体育场 场馆 比赛'),
    EmojiAsset('🎡', '摩天轮 游乐园 约会'),
    EmojiAsset('🎢', '过山车 游乐园 刺激'),
    EmojiAsset('🎠', '旋转木马 游乐园 童年'),
    EmojiAsset('🎪', '马戏团 帐篷 表演'),
    EmojiAsset('⛲', '喷泉 广场 水景'),
    EmojiAsset('⛱️', '遮阳伞 沙滩 度假'),
    EmojiAsset('🏖️', '海滩 沙滩 度假'),
    EmojiAsset('🏝️', '海岛 小岛 无人'),
    EmojiAsset('🏜️', '沙漠 荒漠 干旱'),
    EmojiAsset('⛰️', '山 爬山 郊游'),
    EmojiAsset('🏔️', '雪山 高山 远眺'),
    EmojiAsset('🗻', '富士山 名山 远景'),
    EmojiAsset('🏕️', '露营 野营 山野'),
    // 建筑与场所
    EmojiAsset('🛖', '小屋 茅屋 原始'),
    EmojiAsset('🏠', '家 房子 住处'),
    EmojiAsset('🏡', '家 房子 小院'),
    EmojiAsset('🏘️', '住宅区 小区 街坊'),
    EmojiAsset('🏚️', '老房子 破屋 荒废'),
    EmojiAsset('🏗️', '工地 施工 建设'),
    EmojiAsset('🏭', '工厂 厂房 制造'),
    EmojiAsset('🏢', '办公楼 写字楼 上班'),
    EmojiAsset('🏬', '百货 商场 逛街'),
    EmojiAsset('🏣', '邮局 日式 邮政'),
    EmojiAsset('🏤', '邮局 欧式 邮政'),
    EmojiAsset('🏥', '医院 就医 看病'),
    EmojiAsset('🏦', '银行 存款 柜台'),
    EmojiAsset('🏨', '酒店 住宿 出差'),
    EmojiAsset('🏪', '便利店 小卖部 夜宵'),
    EmojiAsset('🏫', '学校 教学楼 上学'),
    EmojiAsset('🏩', '情侣酒店 住宿 粉'),
    EmojiAsset('💒', '教堂 婚礼 誓约'),
    EmojiAsset('⛪', '教堂 礼拜 尖顶'),
    EmojiAsset('🕌', '清真寺 建筑 圆顶'),
    EmojiAsset('🕍', '会堂 犹太 建筑'),
    EmojiAsset('🛕', '神庙 印度 建筑'),
    EmojiAsset('🕋', '天房 麦加 朝圣'),
    EmojiAsset('⛩️', '鸟居 神社 日本'),
    // 城市景观与行囊
    EmojiAsset('🌁', '雾城 大桥 朦胧'),
    EmojiAsset('🌃', '夜景 城市 夜晚'),
    EmojiAsset('🌆', '城市 黄昏 天际'),
    EmojiAsset('🏙️', '城市 天际线 高楼'),
    EmojiAsset('🌉', '夜桥 大桥 夜景'),
    EmojiAsset('🗾', '日本 地图 列岛'),
    EmojiAsset('🧳', '行李箱 出发 旅行'),
    EmojiAsset('🎒', '背包 出门 上学'),
    EmojiAsset('🛎️', '前台 铃 酒店'),
  ],
  '服饰': [
    // 眼镜与外套
    EmojiAsset('👓', '眼镜 近视 斯文'),
    EmojiAsset('🕶️', '墨镜 太阳镜 酷'),
    EmojiAsset('🥽', '护目镜 防护 实验'),
    EmojiAsset('🥼', '白大褂 实验 医生'),
    EmojiAsset('🦺', '反光衣 安全 施工'),
    EmojiAsset('👔', '领带 正装 商务'),
    EmojiAsset('👕', '短袖 上衣 休闲'),
    EmojiAsset('👖', '牛仔裤 裤子 休闲'),
    EmojiAsset('🧣', '围巾 保暖 冬'),
    EmojiAsset('🧤', '手套 保暖 冬'),
    EmojiAsset('🧥', '外套 大衣 秋冬'),
    EmojiAsset('🧦', '袜子 保暖 一双'),
    // 裙装与泳装
    EmojiAsset('👗', '连衣裙 裙子 女装'),
    EmojiAsset('👘', '和服 日式 传统'),
    EmojiAsset('🥻', '纱丽 印度 传统'),
    EmojiAsset('🩱', '泳衣 连体 泳装'),
    EmojiAsset('🩲', '泳裤 内裤 贴身'),
    EmojiAsset('🩳', '短裤 运动裤 夏'),
    EmojiAsset('👙', '比基尼 泳装 海边'),
    EmojiAsset('👚', '女装 上衣 衬衫'),
    // 包与鞋
    EmojiAsset('👛', '零钱包 钱包 小包'),
    EmojiAsset('👜', '手提包 包 女包'),
    EmojiAsset('👝', '手拿包 小包 出门'),
    EmojiAsset('👞', '皮鞋 男鞋 正装'),
    EmojiAsset('👟', '运动鞋 球鞋 舒适'),
    EmojiAsset('🥾', '登山靴 靴子 户外'),
    EmojiAsset('🥿', '平底鞋 单鞋 舒适'),
    EmojiAsset('👠', '高跟鞋 女鞋 优雅'),
    EmojiAsset('👡', '凉鞋 女鞋 夏'),
    EmojiAsset('🩰', '芭蕾舞鞋 舞蹈 足尖'),
    EmojiAsset('👢', '长靴 女靴 秋冬'),
    // 帽饰与首饰
    EmojiAsset('👑', '皇冠 王冠 第一'),
    EmojiAsset('👒', '遮阳帽 草帽 夏'),
    EmojiAsset('🎩', '礼帽 绅士 复古'),
    EmojiAsset('🎓', '毕业 学位帽 学习'),
    EmojiAsset('🧢', '鸭舌帽 棒球帽 街头'),
    EmojiAsset('⛑️', '安全帽 救援 防护'),
    EmojiAsset('📿', '念珠 项链 祈福'),
    EmojiAsset('💄', '口红 化妆 精致'),
    EmojiAsset('💍', '戒指 求婚 结婚'),
    EmojiAsset('💎', '钻石 宝石 珍贵'),
  ],
  '物品': [
    // 书与纸
    EmojiAsset('📖', '书 阅读 读书'),
    EmojiAsset('📕', '红书 教材 合上'),
    EmojiAsset('📗', '绿书 书本 教材'),
    EmojiAsset('📘', '蓝书 书本 教材'),
    EmojiAsset('📙', '橙书 书本 教材'),
    EmojiAsset('📚', '书本 书堆 学习'),
    EmojiAsset('📓', '笔记本 记事 本子'),
    EmojiAsset('📔', '笔记本 手账 日记'),
    EmojiAsset('📒', '账本 记账 台账'),
    EmojiAsset('📃', '卷页 文稿 纸'),
    EmojiAsset('📜', '卷轴 古籍 证书'),
    EmojiAsset('📄', '文件 纸张 单页'),
    EmojiAsset('📰', '报纸 新闻 早报'),
    EmojiAsset('🗞️', '报纸 卷起 新闻'),
    EmojiAsset('📑', '分页 标签 书签条'),
    // 文具
    EmojiAsset('✏️', '铅笔 写字 涂改'),
    EmojiAsset('✒️', '蘸水笔 书法 笔尖'),
    EmojiAsset('🖋️', '钢笔 书写 签名'),
    EmojiAsset('🖊️', '圆珠笔 签字笔 记录'),
    EmojiAsset('🖌️', '画笔 上色 水彩'),
    EmojiAsset('🖍️', '蜡笔 涂色 童趣'),
    EmojiAsset('📝', '记录 写字 便签'),
    EmojiAsset('📁', '文件夹 归档 资料'),
    EmojiAsset('📂', '打开文件夹 资料 查阅'),
    EmojiAsset('🗂️', '索引卡 分类 整理'),
    EmojiAsset('📅', '日历 日期 计划'),
    EmojiAsset('📆', '台历 日期 翻页'),
    EmojiAsset('🗒️', '便签本 记事 提醒'),
    EmojiAsset('🗓️', '日历 日程 安排'),
    EmojiAsset('📇', '名片盒 索引 联系人'),
    EmojiAsset('📈', '上升 增长 图表'),
    EmojiAsset('📉', '下降 下滑 图表'),
    EmojiAsset('📊', '柱状图 数据 统计'),
    EmojiAsset('📋', '剪贴板 清单 待办'),
    EmojiAsset('📌', '图钉 标记 钉住'),
    EmojiAsset('📍', '定位 位置 地点'),
    EmojiAsset('📎', '回形针 夹住 附件'),
    EmojiAsset('🖇️', '回形针 串联 成组'),
    EmojiAsset('📏', '尺子 直尺 测量'),
    EmojiAsset('📐', '三角尺 制图 角度'),
    EmojiAsset('✂️', '剪刀 手工 裁剪'),
    EmojiAsset('🗃️', '档案盒 收纳 归档'),
    EmojiAsset('🗄️', '文件柜 归档 办公'),
    EmojiAsset('🗑️', '垃圾桶 删除 丢弃'),
    // 锁与工具
    EmojiAsset('🔒', '锁 隐私 加密'),
    EmojiAsset('🔓', '解锁 打开 开放'),
    EmojiAsset('🔏', '加密 保护 带笔'),
    EmojiAsset('🔐', '上锁 安全 钥匙'),
    EmojiAsset('🔑', '钥匙 开门 关键'),
    EmojiAsset('🗝️', '老式钥匙 复古 秘密'),
    EmojiAsset('🔨', '锤子 修理 敲'),
    EmojiAsset('🪓', '斧头 劈柴 户外'),
    EmojiAsset('⛏️', '镐 挖矿 开采'),
    EmojiAsset('⚒️', '锤凿 工具 手作'),
    EmojiAsset('🛠️', '工具 维修 扳手'),
    EmojiAsset('🗡️', '匕首 短剑 锋利'),
    EmojiAsset('⚔️', '交叉剑 战斗 对决'),
    EmojiAsset('🛡️', '盾牌 防护 守护'),
    EmojiAsset('🔧', '扳手 维修 拧'),
    EmojiAsset('🪛', '螺丝刀 拧 维修'),
    EmojiAsset('🔩', '螺丝 零件 五金'),
    EmojiAsset('⚙️', '齿轮 设置 机械'),
    EmojiAsset('🗜️', '夹钳 压紧 固定'),
    EmojiAsset('⚖️', '天平 公平 平衡'),
    EmojiAsset('🦯', '盲杖 辅助 导盲'),
    EmojiAsset('🔗', '链接 链条 关联'),
    EmojiAsset('⛓️', '锁链 束缚 铁链'),
    EmojiAsset('🪤', '捕鼠夹 陷阱 诱饵'),
    EmojiAsset('🧰', '工具箱 维修 备件'),
    EmojiAsset('🧲', '磁铁 吸引 磁力'),
    EmojiAsset('🪜', '梯子 攀爬 高处'),
    // 科学与医疗
    EmojiAsset('🧪', '试管 实验 化学'),
    EmojiAsset('🧫', '培养皿 实验 生物'),
    EmojiAsset('🧬', '基因 遗传 螺旋'),
    EmojiAsset('🔬', '显微镜 观察 科研'),
    EmojiAsset('🔭', '望远镜 观星 远眺'),
    EmojiAsset('📡', '天线 信号 接收'),
    EmojiAsset('💉', '针筒 打针 疫苗'),
    EmojiAsset('💊', '药 药丸 吃药'),
    EmojiAsset('🩺', '听诊器 医生 体检'),
    EmojiAsset('🩹', '创可贴 受伤 包扎'),
    // 家居
    EmojiAsset('🚪', '门 出入 关门'),
    EmojiAsset('🪞', '镜子 照镜 反射'),
    EmojiAsset('🪟', '窗户 采光 通风'),
    EmojiAsset('🛏️', '床 睡觉 休息'),
    EmojiAsset('🛋️', '沙发 客厅 休息'),
    EmojiAsset('🪑', '椅子 座位 坐'),
    EmojiAsset('🚽', '马桶 卫生间 洗手间'),
    EmojiAsset('🪠', '搋子 疏通 卫生'),
    EmojiAsset('🚿', '淋浴 洗澡 花洒'),
    EmojiAsset('🛁', '浴缸 泡澡 放松'),
    EmojiAsset('🪣', '水桶 打水 清洁'),
    EmojiAsset('🧴', '乳液 护肤 瓶子'),
    EmojiAsset('🧷', '别针 固定 尿布针'),
    EmojiAsset('🧹', '扫帚 打扫 清洁'),
    EmojiAsset('🧺', '篮子 野餐 洗衣'),
    EmojiAsset('🧻', '卷纸 纸巾 抽纸'),
    EmojiAsset('🧼', '肥皂 洗手 清洁'),
    EmojiAsset('🪥', '牙刷 刷牙 清洁'),
    EmojiAsset('🧽', '海绵 清洁 擦'),
    EmojiAsset('🧯', '灭火器 消防 安全'),
    // 购物与钱
    EmojiAsset('🛒', '购物车 买 超市'),
    EmojiAsset('🛍️', '购物 逛街 买买买'),
    EmojiAsset('💰', '钱 存钱 理财'),
    EmojiAsset('🪙', '硬币 钱币 零钱'),
    EmojiAsset('💴', '日元 钞票 外币'),
    EmojiAsset('💵', '美元 钞票 外币'),
    EmojiAsset('💶', '欧元 钞票 外币'),
    EmojiAsset('💷', '英镑 钞票 外币'),
    EmojiAsset('💸', '花钱 转账 破财'),
    EmojiAsset('💳', '银行卡 支付 刷卡'),
    EmojiAsset('🧾', '收据 账单 报销'),
    EmojiAsset('💹', '行情 上涨 图表'),
    // 邮件与通讯
    EmojiAsset('✉️', '信封 邮件 来信'),
    EmojiAsset('📧', '邮件 电邮 收信'),
    EmojiAsset('📨', '收件 邮件 到达'),
    EmojiAsset('📩', '发信 邮件 箭头'),
    EmojiAsset('📤', '发件箱 发送 寄出'),
    EmojiAsset('📥', '收件箱 接收 收纳'),
    EmojiAsset('📦', '包裹 快递 收货'),
    EmojiAsset('📫', '邮箱 信箱 关闭'),
    EmojiAsset('📪', '邮箱 空 降旗'),
    EmojiAsset('📬', '邮箱 有信 打开'),
    EmojiAsset('📭', '邮箱 无信 打开'),
    EmojiAsset('📮', '邮筒 寄信 投递'),
    EmojiAsset('🗳️', '投票箱 选择 表决'),
    EmojiAsset('💌', '情书 心意 信'),
    EmojiAsset('📢', '喇叭 宣传 通知'),
    EmojiAsset('📣', '扩音器 呐喊 加油'),
    EmojiAsset('📯', '号角 邮号 复古'),
    // 数码
    EmojiAsset('📱', '手机 电话 移动'),
    EmojiAsset('📲', '来电 手机 接收'),
    EmojiAsset('☎️', '电话 座机 复古'),
    EmojiAsset('📞', '电话 通话 听筒'),
    EmojiAsset('📟', '传呼机 复古 呼叫'),
    EmojiAsset('📠', '传真机 办公 复古'),
    EmojiAsset('🔋', '电池 电量 满电'),
    EmojiAsset('🪫', '低电量 没电 充电'),
    EmojiAsset('🔌', '插头 充电 通电'),
    EmojiAsset('💻', '电脑 办公 上班'),
    EmojiAsset('🖥️', '台式机 显示器 桌面'),
    EmojiAsset('🖨️', '打印机 打印 输出'),
    EmojiAsset('⌨️', '键盘 打字 输入'),
    EmojiAsset('🖱️', '鼠标 点击 外设'),
    EmojiAsset('🖲️', '轨迹球 输入 外设'),
    EmojiAsset('💽', '磁盘 存储 复古'),
    EmojiAsset('💾', '软盘 保存 复古'),
    EmojiAsset('💿', '光碟 唱片 存储'),
    EmojiAsset('📀', '光盘 影碟 存储'),
    EmojiAsset('🧮', '算盘 计算 传统'),
    // 影像
    EmojiAsset('🎥', '摄影机 拍摄 电影'),
    EmojiAsset('🎞️', '胶片 电影 复古'),
    EmojiAsset('📽️', '放映机 电影 老片'),
    EmojiAsset('🎬', '场记板 电影 开拍'),
    EmojiAsset('📺', '电视 追剧 频道'),
    EmojiAsset('📷', '相机 拍照 摄影'),
    EmojiAsset('📸', '拍照 闪光 咔嚓'),
    EmojiAsset('📹', '摄像机 录像 记录'),
    EmojiAsset('📼', '录像带 复古 回放'),
    EmojiAsset('🔍', '放大镜 搜索 查找'),
    EmojiAsset('🔎', '放大镜 查找 细看'),
    // 光与时间
    EmojiAsset('🕯️', '蜡烛 温暖 香薰'),
    EmojiAsset('💡', '灯泡 想法 灵感'),
    EmojiAsset('🔦', '手电筒 照明 夜路'),
    EmojiAsset('🪔', '油灯 灯火 传统'),
    EmojiAsset('⌛', '沙漏 时间 等待'),
    EmojiAsset('⏳', '沙漏 计时 流逝'),
    EmojiAsset('⌚', '手表 时间 腕表'),
    EmojiAsset('⏰', '闹钟 时间 起床'),
    EmojiAsset('⏱️', '秒表 计时 冲刺'),
    EmojiAsset('⏲️', '定时器 计时 倒数'),
    EmojiAsset('🕰️', '座钟 时钟 复古'),
    // 玩物与其他
    EmojiAsset('🧸', '玩偶 泰迪熊 毛绒'),
    EmojiAsset('🪆', '套娃 俄罗斯 摆件'),
    EmojiAsset('🧿', '蓝眼 护身 辟邪'),
    EmojiAsset('🪬', '护身符 手掌 祈福'),
    EmojiAsset('🪄', '魔法棒 变身 施法'),
    EmojiAsset('🔮', '水晶球 占卜 神秘'),
    EmojiAsset('☂️', '雨伞 挡雨 撑伞'),
    EmojiAsset('🌂', '收伞 雨具 合起'),
    EmojiAsset('🛢️', '油桶 石油 储罐'),
    EmojiAsset('🔫', '水枪 玩具枪 射'),
    EmojiAsset('🏹', '弓箭 射箭 瞄准'),
    EmojiAsset('🪝', '钩子 挂钩 悬挂'),
    EmojiAsset('🕳️', '洞 黑洞 掉坑'),
  ],
  '符号': [
    // 爱心
    EmojiAsset('❤️', '爱心 红心 喜欢'),
    EmojiAsset('🧡', '橙心 爱心 温暖'),
    EmojiAsset('💛', '黄心 爱心 友情'),
    EmojiAsset('💚', '绿心 爱心 治愈'),
    EmojiAsset('💙', '蓝心 爱心 平静'),
    EmojiAsset('💜', '紫心 爱心 梦幻'),
    EmojiAsset('🤎', '棕心 爱心 沉稳'),
    EmojiAsset('🖤', '黑心 爱心 酷'),
    EmojiAsset('🤍', '白心 爱心 纯净'),
    EmojiAsset('💕', '两颗心 喜欢 甜'),
    EmojiAsset('💖', '闪亮的心 心动 亮'),
    EmojiAsset('💗', '心动 跳动 增长'),
    EmojiAsset('💓', '心跳 悸动 怦然'),
    EmojiAsset('💞', '双心 缘分 环绕'),
    EmojiAsset('💘', '一箭穿心 表白 丘比特'),
    EmojiAsset('💝', '心形礼物 礼物 心意'),
    EmojiAsset('💟', '心形装饰 爱 标记'),
    EmojiAsset('❣️', '心叹号 喜欢 强调'),
    EmojiAsset('💔', '心碎 失恋 难过'),
    EmojiAsset('💋', '唇印 亲吻 口红印'),
    // 对话
    EmojiAsset('💬', '对话 说话 气泡'),
    EmojiAsset('🗨️', '对话框 引用 左向'),
    EmojiAsset('🗯️', '怒气 对话 爆炸框'),
    EmojiAsset('💭', '想法 气泡 白日梦'),
    // 判定与强调
    EmojiAsset('✅', '完成 打勾 已办'),
    EmojiAsset('☑️', '勾选 待办 方框'),
    EmojiAsset('✔️', '对勾 确认 是'),
    EmojiAsset('❎', '叉 取消 方框'),
    EmojiAsset('❌', '错 取消 否'),
    EmojiAsset('⭕', '圆圈 正确 圈出'),
    EmojiAsset('🚫', '禁止 不许 禁'),
    EmojiAsset('⛔', '禁止 停 进入'),
    EmojiAsset('🔞', '未成年 限制 禁'),
    EmojiAsset('❗', '感叹号 重点 注意'),
    EmojiAsset('❕', '感叹号 提示 白'),
    EmojiAsset('❓', '问号 疑问 不解'),
    EmojiAsset('❔', '问号 疑问 白'),
    EmojiAsset('‼️', '双感叹 强调 紧急'),
    EmojiAsset('⁉️', '惊问 意外 疑惑'),
    EmojiAsset('💯', '满分 一百 完美'),
    EmojiAsset('⚡', '闪电 快 电'),
    EmojiAsset('♻️', '循环 环保 回收'),
    EmojiAsset('✳️', '星号 标记 六角'),
    EmojiAsset('✴️', '八角星 标记 亮'),
    EmojiAsset('❇️', '闪耀 火花 装饰'),
    EmojiAsset('✖️', '乘号 叉 运算'),
    EmojiAsset('➕', '加号 增加 运算'),
    EmojiAsset('➖', '减号 减少 运算'),
    EmojiAsset('➗', '除号 除 运算'),
    EmojiAsset('🟰', '等号 相等 运算'),
    EmojiAsset('♾️', '无限 永远 循环'),
    EmojiAsset('〽️', '波形 标记 转折'),
    EmojiAsset('🔱', '三叉戟 标志 海神'),
    EmojiAsset('⚜️', '鸢尾 纹章 法式'),
    EmojiAsset('🔰', '新手 初学 嫩芽'),
    // 箭头
    EmojiAsset('⬆️', '上 箭头 向上'),
    EmojiAsset('↗️', '右上 箭头 斜'),
    EmojiAsset('➡️', '右 箭头 向右'),
    EmojiAsset('↘️', '右下 箭头 斜'),
    EmojiAsset('⬇️', '下 箭头 向下'),
    EmojiAsset('↙️', '左下 箭头 斜'),
    EmojiAsset('⬅️', '左 箭头 向左'),
    EmojiAsset('↖️', '左上 箭头 斜'),
    EmojiAsset('↕️', '上下 箭头 纵向'),
    EmojiAsset('↔️', '左右 箭头 横向'),
    EmojiAsset('↩️', '返回 回退 折返'),
    EmojiAsset('↪️', '前进 转向 折返'),
    EmojiAsset('⤴️', '向上转 箭头 抬升'),
    EmojiAsset('⤵️', '向下转 箭头 下沉'),
    EmojiAsset('🔃', '顺时针 刷新 旋转'),
    EmojiAsset('🔄', '循环 刷新 重来'),
    EmojiAsset('🔙', '后退 返回 上一步'),
    EmojiAsset('🔚', '结束 完结 终'),
    EmojiAsset('🔛', '开启 进行中 标记'),
    EmojiAsset('🔜', '即将 快了 预告'),
    EmojiAsset('🔝', '置顶 顶部 最上'),
    // 播放与音量
    EmojiAsset('▶️', '播放 开始 前进'),
    EmojiAsset('⏸️', '暂停 停一下 歇'),
    EmojiAsset('⏯️', '播放暂停 切换 控制'),
    EmojiAsset('⏹️', '停止 结束 方块'),
    EmojiAsset('⏺️', '录制 录音 红点'),
    EmojiAsset('⏭️', '下一个 快进 跳过'),
    EmojiAsset('⏮️', '上一个 回退 跳回'),
    EmojiAsset('⏩', '快进 加速 前进'),
    EmojiAsset('⏪', '快退 倒带 后退'),
    EmojiAsset('🔼', '上 三角 增大'),
    EmojiAsset('🔽', '下 三角 减小'),
    EmojiAsset('🔀', '随机 洗牌 乱序'),
    EmojiAsset('🔁', '循环 重复 列表'),
    EmojiAsset('🔂', '单曲循环 重复 一首'),
    EmojiAsset('🔊', '音量 大声 外放'),
    EmojiAsset('🔉', '音量 适中 声音'),
    EmojiAsset('🔈', '音量 小声 声音'),
    EmojiAsset('🔇', '静音 消音 关闭'),
    EmojiAsset('🔔', '铃铛 提醒 通知'),
    EmojiAsset('🔕', '静音 免打扰 关铃'),
    // 标识与警示
    EmojiAsset('🚻', '洗手间 卫生间 公共'),
    EmojiAsset('🚹', '男厕 男 标识'),
    EmojiAsset('🚺', '女厕 女 标识'),
    EmojiAsset('🚼', '母婴 婴儿 标识'),
    EmojiAsset('🚾', '厕所 水厕 标识'),
    EmojiAsset('🛗', '电梯 升降 标识'),
    EmojiAsset('🅿️', '停车 车位 标识'),
    EmojiAsset('🚭', '禁烟 禁止吸烟 标识'),
    EmojiAsset('📵', '禁用手机 静音 标识'),
    EmojiAsset('⚠️', '警告 注意 小心'),
    EmojiAsset('☢️', '辐射 危险 核'),
    EmojiAsset('☣️', '生化 危险 病毒'),
    EmojiAsset('🚸', '儿童 注意 通行'),
    EmojiAsset('🔖', '书签 标签 收藏'),
    EmojiAsset('🏷️', '标签 分类 挂牌'),
    EmojiAsset('🚩', '旗 标记 打卡'),
    EmojiAsset('🏁', '终点 完成 方格旗'),
    EmojiAsset('🏳️', '白旗 投降 停战'),
    EmojiAsset('🏴', '黑旗 海盗 神秘'),
    EmojiAsset('🎌', '交叉旗 日本 庆典'),
    // 星座
    EmojiAsset('♈', '白羊座 星座 三月'),
    EmojiAsset('♉', '金牛座 星座 四月'),
    EmojiAsset('♊', '双子座 星座 五月'),
    EmojiAsset('♋', '巨蟹座 星座 六月'),
    EmojiAsset('♌', '狮子座 星座 七月'),
    EmojiAsset('♍', '处女座 星座 八月'),
    EmojiAsset('♎', '天秤座 星座 九月'),
    EmojiAsset('♏', '天蝎座 星座 十月'),
    EmojiAsset('♐', '射手座 星座 十一月'),
    EmojiAsset('♑', '摩羯座 星座 十二月'),
    EmojiAsset('♒', '水瓶座 星座 一月'),
    EmojiAsset('♓', '双鱼座 星座 二月'),
    EmojiAsset('⛎', '蛇夫座 星座 第十三'),
    // 信仰与祈愿
    EmojiAsset('☮️', '和平 反战 标志'),
    EmojiAsset('☯️', '太极 阴阳 平衡'),
    EmojiAsset('☸️', '法轮 佛教 标志'),
    EmojiAsset('✝️', '十字 基督 信仰'),
    EmojiAsset('☪️', '星月 伊斯兰 标志'),
    EmojiAsset('🕉️', '梵 印度教 标志'),
    EmojiAsset('✡️', '六芒星 犹太 标志'),
    EmojiAsset('🔯', '六芒星 占卜 神秘'),
    // 数字与字母
    EmojiAsset('0️⃣', '零 数字 键'),
    EmojiAsset('1️⃣', '一 数字 第一'),
    EmojiAsset('2️⃣', '二 数字 第二'),
    EmojiAsset('3️⃣', '三 数字 第三'),
    EmojiAsset('4️⃣', '四 数字 第四'),
    EmojiAsset('5️⃣', '五 数字 第五'),
    EmojiAsset('6️⃣', '六 数字 第六'),
    EmojiAsset('7️⃣', '七 数字 第七'),
    EmojiAsset('8️⃣', '八 数字 第八'),
    EmojiAsset('9️⃣', '九 数字 第九'),
    EmojiAsset('🔟', '十 数字 满分'),
    EmojiAsset('#️⃣', '井号 标签 话题'),
    EmojiAsset('*️⃣', '星号 按键 标记'),
    EmojiAsset('🆕', '新 新增 上新'),
    EmojiAsset('🆓', '免费 白送 标识'),
    EmojiAsset('🆒', '酷 厉害 标识'),
    EmojiAsset('🆗', '好 可以 标识'),
    EmojiAsset('🆙', '提升 升级 标识'),
    EmojiAsset('🆖', '不行 差 标识'),
    EmojiAsset('🆑', '清除 重置 标识'),
    EmojiAsset('🅰️', '甲型 血型 字母'),
    EmojiAsset('🅱️', '乙型 血型 字母'),
    EmojiAsset('🆎', '混合 血型 字母'),
    EmojiAsset('🅾️', '零型 血型 字母'),
    EmojiAsset('ℹ️', '信息 说明 提示'),
    EmojiAsset('Ⓜ️', '地铁 标志 圆圈'),
    EmojiAsset('🔠', '大写 字母 输入'),
    EmojiAsset('🔡', '小写 字母 输入'),
    EmojiAsset('🔢', '数字 输入 键盘'),
    EmojiAsset('🔣', '符号 输入 键盘'),
    EmojiAsset('🔤', '字母 输入 键盘'),
    EmojiAsset('㊗️', '祝 祝贺 日文'),
    EmojiAsset('㊙️', '秘 秘密 日文'),
    EmojiAsset('🈚', '无 免 日文'),
    EmojiAsset('🈶', '有 收费 日文'),
    EmojiAsset('🈯', '指定 预留 日文'),
    EmojiAsset('🈷️', '月 月度 日文'),
    EmojiAsset('🈴', '合格 及格 日文'),
    EmojiAsset('🈵', '满 客满 日文'),
    EmojiAsset('🈹', '折扣 打折 日文'),
    EmojiAsset('🈲', '禁止 禁 日文'),
    EmojiAsset('🈸', '申请 申 日文'),
    EmojiAsset('🈺', '营业 开门 日文'),
    EmojiAsset('🉐', '划算 得 日文'),
    EmojiAsset('🉑', '可以 认可 日文'),
    // 形状与色块
    EmojiAsset('🔴', '红点 圆点 色点'),
    EmojiAsset('🟠', '橙点 圆点 色点'),
    EmojiAsset('🟡', '黄点 圆点 色点'),
    EmojiAsset('🟢', '绿点 圆点 色点'),
    EmojiAsset('🔵', '蓝点 圆点 色点'),
    EmojiAsset('🟣', '紫点 圆点 色点'),
    EmojiAsset('🟤', '棕点 圆点 色点'),
    EmojiAsset('⚫', '黑点 圆点 色点'),
    EmojiAsset('⚪', '白点 圆点 色点'),
    EmojiAsset('🟥', '红方块 色块 标记'),
    EmojiAsset('🟧', '橙方块 色块 标记'),
    EmojiAsset('🟨', '黄方块 色块 标记'),
    EmojiAsset('🟩', '绿方块 色块 标记'),
    EmojiAsset('🟦', '蓝方块 色块 标记'),
    EmojiAsset('🟪', '紫方块 色块 标记'),
    EmojiAsset('🟫', '棕方块 色块 标记'),
    EmojiAsset('⬛', '黑块 方块 色块'),
    EmojiAsset('⬜', '白块 方块 色块'),
    EmojiAsset('◼️', '黑块 方块 中号'),
    EmojiAsset('◻️', '白块 方块 中号'),
    EmojiAsset('▪️', '黑块 方块 小号'),
    EmojiAsset('▫️', '白块 方块 小号'),
    EmojiAsset('🔶', '橙菱形 大 装饰'),
    EmojiAsset('🔷', '蓝菱形 大 装饰'),
    EmojiAsset('🔸', '橙菱形 小 装饰'),
    EmojiAsset('🔹', '蓝菱形 小 装饰'),
    EmojiAsset('🔺', '红三角 向上 标记'),
    EmojiAsset('🔻', '红三角 向下 标记'),
    EmojiAsset('💠', '菱形 装饰 花纹'),
    EmojiAsset('🔘', '圆钮 单选 按钮'),
    EmojiAsset('🔳', '白框 按钮 方'),
    EmojiAsset('🔲', '黑框 按钮 方'),
  ],
};

/// 扁平化的 emoji 字符列表（保留原 `stickerPalette` 引用点不破坏）。
List<String> get stickerPalette => [
  for (final list in emojiCategories.values)
    for (final e in list) e.char,
];

/// 贴纸基础字号(编辑与导出共用,保持视觉一致)。
const stickerBaseFontSize = 34.0;
