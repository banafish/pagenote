import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 内置矢量贴纸素材库（调研一阶段「素材升级」）。
/// 全部为程序绘制的矢量图形：免抠、无版权成本、任意缩放不糊，
/// 延续本项目「零图片资产」的离线免费定位。
/// 坐标系：每个贴纸在 100×100 逻辑画布内绘制，渲染时缩放至元素框。

class StickerAsset {
  const StickerAsset(this.id, this.category, this.name, [this.keywords = '']);

  /// 唯一 id（存入 StickerElement.key 的 `vec:<id>` 部分）。
  /// NFR-08：一经发布不得重命名或删除，只能新增。
  final String id;

  /// 分类：自然 / 美食 / 生活 / 可爱。
  final String category;

  /// 素材面板中的名称。
  final String name;

  /// 搜索关键词（REQ-17.6），空格分隔的 3～5 个中文词。
  final String keywords;

  /// 该素材是否命中搜索词（名称 / id / 关键词 / 分类）。
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.contains(q) ||
        category.contains(q) ||
        keywords.contains(q) ||
        id.toLowerCase().contains(q);
  }
}

/// 贴纸分类顺序（面板 tab 顺序）。
const stickerCategories = ['自然', '美食', '生活', '可爱'];

const List<StickerAsset> vectorStickers = [
  // ---- 自然 ----
  StickerAsset('flower', '自然', '小花', '花朵 植物 春天 浪漫 粉色'),
  StickerAsset('sun', '自然', '太阳', '晴天 阳光 夏天 天气 温暖'),
  StickerAsset('moon', '自然', '月亮', '夜晚 晚安 睡觉 月牙 安静'),
  StickerAsset('cloud', '自然', '云朵', '天气 多云 天空 柔软 蓝色'),
  StickerAsset('rainbow', '自然', '彩虹', '天气 雨后 色彩 治愈 希望'),
  StickerAsset('star', '自然', '星星', '夜空 闪耀 愿望 高光 收藏'),
  StickerAsset('leaf', '自然', '叶子', '植物 绿色 自然 秋天 清新'),
  StickerAsset('clover', '自然', '四叶草', '幸运 植物 绿色 好运 许愿'),
  // ---- 美食 ----
  StickerAsset('coffee', '美食', '咖啡', '饮品 下午茶 提神 拿铁 早晨'),
  StickerAsset('cake', '美食', '蛋糕', '生日 甜点 庆祝 派对 奶油'),
  StickerAsset('icecream', '美食', '冰淇淋', '甜点 夏天 冰激凌 凉爽 甜筒'),
  StickerAsset('cherry', '美食', '樱桃', '水果 甜 红色 夏天 可爱'),
  StickerAsset('strawberry', '美食', '草莓', '水果 甜点 红色 春天 可爱'),
  StickerAsset('watermelon', '美食', '西瓜', '水果 夏天 解暑 甜 红色'),
  StickerAsset('candy', '美食', '糖果', '零食 甜 童年 粉色 小食'),
  StickerAsset('donut', '美食', '甜甜圈', '甜点 下午茶 零食 早餐 可爱'),
  // ---- 生活 ----
  StickerAsset('book', '生活', '书本', '阅读 读书 学习 笔记 知识'),
  StickerAsset('camera', '生活', '相机', '拍照 旅行 记录 摄影 回忆'),
  StickerAsset('mail', '生活', '信件', '信封 邮件 书信 想念 收到'),
  StickerAsset('gift', '生活', '礼物', '生日 惊喜 节日 礼盒 庆祝'),
  StickerAsset('bow', '生活', '蝴蝶结', '装饰 丝带 少女 粉色 可爱'),
  StickerAsset('candle', '生活', '蜡烛', '生日 温暖 香薰 夜晚 治愈'),
  StickerAsset('music', '生活', '音乐', '歌曲 音符 听歌 耳机 旋律'),
  StickerAsset('mug', '生活', '热茶', '饮品 马克杯 温暖 下午茶 休息'),
  // ---- 可爱 ----
  StickerAsset('cat', '可爱', '猫咪', '动物 宠物 喵 萌 撸猫'),
  StickerAsset('butterfly', '可爱', '蝴蝶', '动物 春天 飞舞 昆虫 浪漫'),
  StickerAsset('bird', '可爱', '小鸟', '动物 飞翔 自由 春天 鸟儿'),
  StickerAsset('bear', '可爱', '小熊', '动物 玩偶 萌 抱抱 治愈'),
  StickerAsset('heart', '可爱', '爱心', '喜欢 心形 love 表白 红色'),
  StickerAsset('smiley', '可爱', '笑脸', '开心 微笑 心情 快乐 表情'),
  StickerAsset('balloon', '可爱', '气球', '庆祝 生日 派对 飞起 童年'),
  StickerAsset('flag', '可爱', '小旗', '标记 目标 打卡 旗帜 计划'),
];

StickerAsset? stickerById(String id) =>
    vectorStickers.where((s) => s.id == id).firstOrNull;

// ---------------------------------------------------------------------------
// 贴纸 key 体系
// ---------------------------------------------------------------------------

/// `StickerElement.key` 的三种前缀：
/// - `vec:<id>`      内置矢量贴纸
/// - `emoji:<字符>`  系统 emoji
/// - `img:<sha1>`    自定义图片贴纸（REQ-20，内容寻址使 key 跨设备稳定）
const stickerKeyVector = 'vec:';
const stickerKeyEmoji = 'emoji:';
const stickerKeyImage = 'img:';

/// 自定义图片贴纸（REQ-20）：id 为文件内容 sha1，天然去重且跨设备稳定。
class CustomSticker {
  CustomSticker({
    required this.id,
    required this.name,
    this.category = '我的',
    this.keywords = '',
    this.ext = '.png',
    this.packId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 文件内容 sha1（同时是文件名主干）。
  final String id;
  String name;

  /// 旧版「分组」功能的自由文本。分组 UI 已下线，仅随 DB / 备份 /
  /// 分享包往返保留（默认「我的」），新导入不再指定。
  String category;
  String keywords;

  /// 所属素材包（[StickerPack.id]）；null = 未分组。
  /// 分享包导入时按包落位，相册单张导入落在未分组。
  String? packId;

  /// 文件扩展名（含点）。
  final String ext;
  final DateTime createdAt;

  /// 画布元素引用它时使用的 key。
  String get stickerKey => '$stickerKeyImage$id';

  String get fileName => '$id$ext';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        category.contains(q) ||
        keywords.toLowerCase().contains(q);
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'keywords': keywords,
    'ext': ext,
    'packId': packId,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static CustomSticker fromMap(Map<String, Object?> map) => CustomSticker(
    id: map['id']! as String,
    name: (map['name'] ?? '') as String,
    category: (map['category'] ?? '我的') as String,
    keywords: (map['keywords'] ?? '') as String,
    ext: (map['ext'] ?? '.png') as String,
    packId: map['packId'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] ?? 0) as int,
    ),
  );
}

/// 素材包：模板（v8 起）与自定义贴纸共用的分组容器。
///
/// 两条来源：分享包导入（[originId] 记录包内 pack.json 的 id,
/// 同一个包重复导入时按它归位而不是再建一个同名包,与模板的
/// originId 同一套溯源语义）与用户在管理页手工新建。
/// 手工包首次整包导出时也会补配一个 originId 并落库,
/// 保证包身份在转发链上稳定。
class StickerPack {
  StickerPack({
    required this.id,
    required this.name,
    this.author = '',
    this.originId,
    this.sortIndex = 0,
    this.coverPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 本机包 id（`pack-<makeId()>` 风格，备份恢复时原样保留）。
  final String id;
  String name;

  /// 来源署名（分享包的 author）；手工建的包为空。
  String author;

  /// 分享包内 pack.json 的 id；手工包在首次整包导出前为 null。
  String? originId;

  /// 包列表里的手动顺序（REQ-26.5）：升序排列，越小越靠前。
  /// 存量包由 v9 迁移按 createdAt 倒序赋初值，
  /// 新建 / 新导入的包取当前最小值 - 1 落在最前。
  int sortIndex;

  /// 封面文件名（REQ-27，pack_covers/ 目录内的相对名）；null = 未设置。
  /// 封面由用户上传或分享包内 cover.png 导入，不从包内容自动合成。
  String? coverPath;

  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'author': author,
    'originId': originId,
    'sortIndex': sortIndex,
    'coverPath': coverPath,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static StickerPack fromMap(Map<String, Object?> map) => StickerPack(
    id: map['id']! as String,
    name: (map['name'] ?? '') as String,
    author: (map['author'] ?? '') as String,
    originId: map['originId'] as String?,
    sortIndex: (map['sortIndex'] ?? 0) as int,
    coverPath: map['coverPath'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] ?? 0) as int,
    ),
  );
}

/// 自定义贴纸的本机索引（REQ-20）。
///
/// 渲染端（CanvasView / 分享长图 / 时间线卡片）大多拿不到 Provider，
/// 因此由 CustomStickerProvider 在加载与增删时同步刷新这份全局索引，
/// 供渲染与引用完整性校验同步查询。
class CustomStickerIndex {
  CustomStickerIndex._();

  static final CustomStickerIndex instance = CustomStickerIndex._();

  final Map<String, String> _paths = {};
  final Map<String, String> _names = {};

  /// sha1 → 本机文件绝对路径；不存在返回 null。
  String? pathOf(String id) => _paths[id];

  /// sha1 → 素材名；未知返回 null。
  String? nameOf(String id) => _names[id];

  bool contains(String id) => _paths.containsKey(id);

  void replaceAll(Map<String, String> paths, Map<String, String> names) {
    _paths
      ..clear()
      ..addAll(paths);
    _names
      ..clear()
      ..addAll(names);
  }
}

/// 该贴纸 key 在本机是否可渲染（FIX-03 引用完整性校验）。
bool isKnownStickerKey(String key) {
  if (key.startsWith(stickerKeyVector)) {
    return stickerById(key.substring(stickerKeyVector.length)) != null;
  }
  if (key.startsWith(stickerKeyImage)) {
    return CustomStickerIndex.instance.contains(
      key.substring(stickerKeyImage.length),
    );
  }
  // emoji 与裸字符恒可渲染（系统字体兜底）。
  return true;
}

/// 贴纸 key 的可读名称（缺失提示与导入预览页复用）。
String stickerKeyLabel(String key) {
  if (key.startsWith(stickerKeyVector)) {
    final id = key.substring(stickerKeyVector.length);
    return stickerById(id)?.name ?? '矢量贴纸 $id';
  }
  if (key.startsWith(stickerKeyImage)) {
    final id = key.substring(stickerKeyImage.length);
    final name = CustomStickerIndex.instance.nameOf(id);
    return name ?? '自定义贴纸 ${id.length > 8 ? id.substring(0, 8) : id}';
  }
  if (key.startsWith(stickerKeyEmoji)) {
    return key.substring(stickerKeyEmoji.length);
  }
  return key;
}

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
///
/// [tint] 非空时对素材内部调色板做统一色相迁移（REQ-19）：
/// 轮廓墨色与白/奶白等中性色保持原样，多色层次（小熊的鼻头、
/// 猫的胡须）因此仍可辨识，而非整体单色填充。
///
/// 未知 id 绘制为明确的缺失占位（虚线框 + ?），
/// 不再静默回退成星星（FIX-03）。
class StickerPainter extends CustomPainter {
  const StickerPainter(this.id, {this.tint});

  final String id;

  /// 目标色调（0xAARRGGBB）；null 为素材原配色。
  final int? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = _stickerPainters[id] ?? _missing;
    // 统一缩放：素材绘制在 100×100 逻辑画布。
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    // 绘制期间生效的色调：_p() 读取它做色相迁移，
    // 32 个绘制函数无需逐个改写。paint 全程同步，无并发风险。
    _activeTint = tint == null || painter == _missing ? null : Color(tint!);
    try {
      painter(canvas);
    } finally {
      _activeTint = null;
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant StickerPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.tint != tint;
}

/// id → 绘制函数。缺失的 id 不再落到 `_star`（FIX-03）。
const Map<String, void Function(Canvas)> _stickerPainters = {
  'flower': _flower,
  'sun': _sun,
  'moon': _moon,
  'cloud': _cloud,
  'rainbow': _rainbow,
  'star': _star,
  'leaf': _leaf,
  'clover': _clover,
  'coffee': _coffee,
  'cake': _cake,
  'icecream': _icecream,
  'cherry': _cherry,
  'strawberry': _strawberry,
  'watermelon': _watermelon,
  'candy': _candy,
  'donut': _donut,
  'book': _book,
  'camera': _camera,
  'mail': _mail,
  'gift': _gift,
  'bow': _bow,
  'candle': _candle,
  'music': _music,
  'mug': _mug,
  'cat': _cat,
  'butterfly': _butterfly,
  'bird': _bird,
  'bear': _bear,
  'heart': _heart,
  'smiley': _smiley,
  'balloon': _balloon,
  'flag': _flag,
};

/// 缺失素材占位（FIX-03.2）：虚线圆角框 + 问号。
/// 与任何正常贴纸在视觉上明显可区分，用户一眼看出「这里少了个素材」。
void _missing(Canvas c) {
  final border = Paint()
    ..color = const Color(0xFF9A8C7C)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(10, 10, 90, 90),
      const Radius.circular(12),
    ),
    Paint()..color = const Color(0x14000000),
  );
  // 虚线边框：沿矩形按 10/7 的实虚节奏画短线。
  const rect = Rect.fromLTRB(10, 10, 90, 90);
  const dash = 10.0, gap = 7.0;
  for (var x = rect.left + 12; x < rect.right - 8; x += dash + gap) {
    final end = math.min(x + dash, rect.right - 8);
    c.drawLine(Offset(x, rect.top), Offset(end, rect.top), border);
    c.drawLine(Offset(x, rect.bottom), Offset(end, rect.bottom), border);
  }
  for (var y = rect.top + 12; y < rect.bottom - 8; y += dash + gap) {
    final end = math.min(y + dash, rect.bottom - 8);
    c.drawLine(Offset(rect.left, y), Offset(rect.left, end), border);
    c.drawLine(Offset(rect.right, y), Offset(rect.right, end), border);
  }
  // 问号：绘制为路径，避免依赖字体。
  final mark = Paint()
    ..color = const Color(0xFF7A6A58)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  c.drawArc(
    const Rect.fromLTRB(36, 28, 64, 54),
    math.pi * 0.9,
    math.pi * 1.35,
    false,
    mark,
  );
  c.drawLine(const Offset(50, 52), const Offset(50, 64), mark);
  c.drawCircle(const Offset(50, 76), 4.5, Paint()..color = const Color(0xFF7A6A58));
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
  ..color = _tinted(color)
  ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..isAntiAlias = true;

/// 当前绘制生效的色调（REQ-19）。由 [StickerPainter.paint] 在同步的
/// 绘制过程中设置与清空，绘制函数经 [_p] 间接读取。
Color? _activeTint;

/// 色相迁移：把素材色拉到目标色相，饱和度与目标混合，
/// 明度以原色为主 —— 多色层次（高光、暗部）因此得以保留。
/// 轮廓墨色与白/奶白等中性色原样返回，保证五官与线条仍可辨识（REQ-19.3）。
Color _tinted(Color color) {
  final tint = _activeTint;
  if (tint == null) return color;
  final hsl = HSLColor.fromColor(color);
  if (hsl.saturation < 0.2 || hsl.lightness > 0.93 || hsl.lightness < 0.12) {
    return color;
  }
  final target = HSLColor.fromColor(tint);
  return HSLColor.fromAHSL(
    hsl.alpha,
    target.hue,
    (hsl.saturation * 0.4 + target.saturation * 0.6).clamp(0.0, 1.0),
    (hsl.lightness * 0.72 + target.lightness * 0.28).clamp(0.1, 0.95),
  ).toColor();
}

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
