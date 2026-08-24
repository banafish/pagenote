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
const stickerCategories = ['自然', '美食', '生活', '可爱', '旅行', '心情'];

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
  StickerAsset('sunflower', '自然', '向日葵', '花朵 夏日 阳光 植物 黄色'),
  StickerAsset('tulip', '自然', '郁金香', '花朵 春天 荷兰 植物 浪漫'),
  StickerAsset('tree', '自然', '小树', '植物 森林 绿色 树木 自然'),
  StickerAsset('cactus', '自然', '仙人掌', '植物 沙漠 多肉 绿色 盆栽'),
  StickerAsset('potted', '自然', '盆栽', '植物 绿植 室内 叶子 养护'),
  StickerAsset('mushroom', '自然', '蘑菇', '菌菇 森林 红色 可爱 卡通'),
  StickerAsset('snowflake', '自然', '雪花', '冬天 下雪 冰冷 蓝色 季节'),
  StickerAsset('mountain', '自然', '山峰', '山峦 雪山 户外 风景 旅行'),
  StickerAsset('wave', '自然', '海浪', '海洋 海边 夏天 蓝色 波浪'),
  // ---- 美食 ----
  StickerAsset('coffee', '美食', '咖啡', '饮品 下午茶 提神 拿铁 早晨'),
  StickerAsset('cake', '美食', '蛋糕', '生日 甜点 庆祝 派对 奶油'),
  StickerAsset('icecream', '美食', '冰淇淋', '甜点 夏天 冰激凌 凉爽 甜筒'),
  StickerAsset('cherry', '美食', '樱桃', '水果 甜 红色 夏天 可爱'),
  StickerAsset('strawberry', '美食', '草莓', '水果 甜点 红色 春天 可爱'),
  StickerAsset('watermelon', '美食', '西瓜', '水果 夏天 解暑 甜 红色'),
  StickerAsset('candy', '美食', '糖果', '零食 甜 童年 粉色 小食'),
  StickerAsset('donut', '美食', '甜甜圈', '甜点 下午茶 零食 早餐 可爱'),
  StickerAsset('boba', '美食', '珍珠奶茶', '饮品 奶茶 波霸 珍珠 下午茶'),
  StickerAsset('toast', '美食', '吐司', '面包 早餐 烤片 烘焙 奶油'),
  StickerAsset('onigiri', '美食', '饭团', '日料 寿司 米饭 海苔 便当'),
  StickerAsset('cupcake', '美食', '纸杯蛋糕', '甜点 生日 派对 奶油 烘焙'),
  StickerAsset('cookie', '美食', '饼干', '零食 曲奇 巧克力 下午茶 烘焙'),
  StickerAsset('lemon', '美食', '柠檬', '水果 酸 黄色 维C 饮品'),
  StickerAsset('peach', '美食', '桃子', '水果 甜美 粉色 夏天 多汁'),
  StickerAsset('sushi', '美食', '寿司', '日料 刺身 海苔 米饭 美食'),
  // ---- 生活 ----
  StickerAsset('book', '生活', '书本', '阅读 读书 学习 笔记 知识'),
  StickerAsset('camera', '生活', '相机', '拍照 旅行 记录 摄影 回忆'),
  StickerAsset('mail', '生活', '信件', '信封 邮件 书信 想念 收到'),
  StickerAsset('gift', '生活', '礼物', '生日 惊喜 节日 礼盒 庆祝'),
  StickerAsset('bow', '生活', '蝴蝶结', '装饰 丝带 少女 粉色 可爱'),
  StickerAsset('candle', '生活', '蜡烛', '生日 温暖 香薰 夜晚 治愈'),
  StickerAsset('music', '生活', '音乐', '歌曲 音符 听歌 耳机 旋律'),
  StickerAsset('mug', '生活', '热茶', '饮品 马克杯 温暖 下午茶 休息'),
  StickerAsset('pencil', '生活', '铅笔', '文具 书写 学习 绘画 画笔'),
  StickerAsset('brush', '生活', '画笔', '绘画 颜料 文具 创作 艺术'),
  StickerAsset('lightbulb', '生活', '灯泡', '想法 创意 灵感 点子 发光'),
  StickerAsset('umbrella', '生活', '雨伞', '雨天 遮伞 天气 出行 防雨'),
  StickerAsset('key', '生活', '钥匙', '开门 锁 家门 金属 黄色'),
  StickerAsset('clock', '生活', '闹钟', '时间 早起 提醒 作息 指针'),
  StickerAsset('paperclip', '生活', '回形针', '文具 办公 夹子 整理 别针'),
  StickerAsset('shopping', '生活', '购物袋', '购物 逛街 买买买 袋子 出门'),
  // ---- 可爱 ----
  StickerAsset('cat', '可爱', '猫咪', '动物 宠物 喵 萌 撸猫'),
  StickerAsset('butterfly', '可爱', '蝴蝶', '动物 春天 飞舞 昆虫 浪漫'),
  StickerAsset('bird', '可爱', '小鸟', '动物 飞翔 自由 春天 鸟儿'),
  StickerAsset('bear', '可爱', '小熊', '动物 玩偶 萌 抱抱 治愈'),
  StickerAsset('heart', '可爱', '爱心', '喜欢 心形 love 表白 红色'),
  StickerAsset('smiley', '可爱', '笑脸', '开心 微笑 心情 快乐 表情'),
  StickerAsset('balloon', '可爱', '气球', '庆祝 生日 派对 飞起 童年'),
  StickerAsset('flag', '可爱', '小旗', '标记 目标 打卡 旗帜 计划'),
  StickerAsset('rabbit', '可爱', '兔子', '动物 宠物 萌 耳朵 蹦跳'),
  StickerAsset('panda', '可爱', '熊猫', '动物 国宝 黑白 萌 吃竹子'),
  StickerAsset('chick', '可爱', '小鸡', '动物 小鸟 黄色 萌 破壳'),
  StickerAsset('penguin', '可爱', '企鹅', '动物 南极 黑白 冰雪 摇摆'),
  StickerAsset('whale', '可爱', '鲸鱼', '动物 海洋 蓝色 喷水 大海'),
  StickerAsset('snail', '可爱', '蜗牛', '动物 慢慢 壳 爬行 治愈'),
  StickerAsset('ghost', '可爱', '幽灵', '万圣节 捣蛋 夜晚 灵异 白色'),
  StickerAsset('paw', '可爱', '猫爪', '猫 动物 爪印 萌 宠物'),
  // ---- 旅行 ----
  StickerAsset('paperplane', '旅行', '纸飞机', '折纸 飞翔 出发 想念 童年'),
  StickerAsset('suitcase', '旅行', '行李箱', '旅行 出差 打包 度假 行李'),
  StickerAsset('tent', '旅行', '帐篷', '露营 野外 宿营 星空 户外'),
  StickerAsset('map', '旅行', '地图', '导航 路线 出行 攻略 指路'),
  StickerAsset('compass', '旅行', '指南针', '方向 指北 探险 定位 户外'),
  StickerAsset('hotairballoon', '旅行', '热气球', '飞行 天空 浪漫 缤纷 出游'),
  StickerAsset('bicycle', '旅行', '自行车', '骑行 单车 出行 运动 环保'),
  StickerAsset('lighthouse', '旅行', '灯塔', '海边 航行 指引 海岸 夜晚'),
  // ---- 心情 ----
  StickerAsset('loveface', '心情', '爱心眼', '喜欢 心动 表情 恋爱 花痴'),
  StickerAsset('sleepy', '心情', '睡颜', '困 睡觉 打哈欠 晚安 休息'),
  StickerAsset('shy', '心情', '害羞', '脸红 不好意思 表情 尴尬 萌'),
  StickerAsset('teary', '心情', '委屈', '难过 想哭 泪水 表情 沮丧'),
  StickerAsset('angry', '心情', '生气', '愤怒 冒火 表情 不开心 哼'),
  StickerAsset('wow', '心情', '惊讶', '吃惊 惊叹 表情 震惊 哇'),
  StickerAsset('cool', '心情', '墨镜酷', '得意 表情 潇洒 自信 帅气'),
  StickerAsset('dizzy', '心情', '晕', '迷糊 头晕 表情 转圈 懵'),
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
  Color(0xFFE57373), // 红
  Color(0xFF7FC8BE), // 青
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
  TapeStyle('checker', '棋盘'),
  TapeStyle('stars', '星星'),
  TapeStyle('flowers', '小花'),
  TapeStyle('zigzag', '锯齿'),
  TapeStyle('drops', '雨滴'),
  TapeStyle('triangles', '山峰'),
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
  0xFFE57373, // 樱桃红
  0xFFF2A65A, // 蜜橘
  0xFFC9E4C0, // 薄荷
  0xFFA9D6CE, // 湖水
  0xFFA98467, // 可可
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
  // 80 个绘制函数无需逐个改写。paint 全程同步，无并发风险。
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
  'sunflower': _sunflower,
  'tulip': _tulip,
  'tree': _tree,
  'cactus': _cactus,
  'potted': _potted,
  'mushroom': _mushroom,
  'snowflake': _snowflake,
  'mountain': _mountain,
  'wave': _wave,
  'coffee': _coffee,
  'cake': _cake,
  'icecream': _icecream,
  'cherry': _cherry,
  'strawberry': _strawberry,
  'watermelon': _watermelon,
  'candy': _candy,
  'donut': _donut,
  'boba': _boba,
  'toast': _toast,
  'onigiri': _onigiri,
  'cupcake': _cupcake,
  'cookie': _cookie,
  'lemon': _lemon,
  'peach': _peach,
  'sushi': _sushi,
  'book': _book,
  'camera': _camera,
  'mail': _mail,
  'gift': _gift,
  'bow': _bow,
  'candle': _candle,
  'music': _music,
  'mug': _mug,
  'pencil': _pencil,
  'brush': _brush,
  'lightbulb': _lightbulb,
  'umbrella': _umbrella,
  'key': _key,
  'clock': _clock,
  'paperclip': _paperclip,
  'shopping': _shopping,
  'cat': _cat,
  'butterfly': _butterfly,
  'bird': _bird,
  'bear': _bear,
  'heart': _heart,
  'smiley': _smiley,
  'balloon': _balloon,
  'flag': _flag,
  'rabbit': _rabbit,
  'panda': _panda,
  'chick': _chick,
  'penguin': _penguin,
  'whale': _whale,
  'snail': _snail,
  'ghost': _ghost,
  'paw': _paw,
  'paperplane': _paperplane,
  'suitcase': _suitcase,
  'tent': _tent,
  'map': _map,
  'compass': _compass,
  'hotairballoon': _hotairballoon,
  'bicycle': _bicycle,
  'lighthouse': _lighthouse,
  'loveface': _loveface,
  'sleepy': _sleepy,
  'shy': _shy,
  'teary': _teary,
  'angry': _angry,
  'wow': _wow,
  'cool': _cool,
  'dizzy': _dizzy,
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
const _milkTea = Color(0xFFD9A87C);
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

void _sunflower(Canvas c) {
  c.drawLine(const Offset(50, 52), const Offset(50, 90), _p(_deepGreen, stroke: true, width: 4));
  for (final dir in [-1.0, 1.0]) {
    final leaf = Path()
      ..moveTo(50, 72)
      ..quadraticBezierTo(50 + dir * 22, 62, 50 + dir * 30, 72)
      ..quadraticBezierTo(50 + dir * 20, 82, 50, 78)
      ..close();
    c.drawPath(leaf, _p(_green));
  }
  // 花瓣：绕花心一圈的竖椭圆。
  for (var i = 0; i < 12; i++) {
    c.save();
    c.translate(50, 40);
    c.rotate(i * math.pi / 6);
    c.drawOval(const Rect.fromLTRB(-5, -34, 5, -12), _p(_yellow));
    c.restore();
  }
  _circle(c, const Offset(50, 40), 14, _p(_brown));
  _circle(c, const Offset(50, 40), 14, _p(_ink, stroke: true, width: 2));
  for (final p in const [
    Offset(44, 36),
    Offset(52, 42),
    Offset(46, 46),
    Offset(55, 34),
  ]) {
    _circle(c, p, 1.6, _p(_cream));
  }
}

void _tulip(Canvas c) {
  c.drawLine(const Offset(50, 54), const Offset(50, 92), _p(_deepGreen, stroke: true, width: 4));
  for (final dir in [-1.0, 1.0]) {
    final leaf = Path()
      ..moveTo(50, 90)
      ..quadraticBezierTo(50 + dir * 26, 80, 50 + dir * 22, 56)
      ..quadraticBezierTo(50 + dir * 8, 70, 50, 82)
      ..close();
    c.drawPath(leaf, _p(_green));
  }
  final cup = Path()
    ..moveTo(30, 26)
    ..quadraticBezierTo(26, 52, 50, 60)
    ..quadraticBezierTo(74, 52, 70, 26)
    ..lineTo(60, 38)
    ..lineTo(50, 24)
    ..lineTo(40, 38)
    ..close();
  c.drawPath(cup, _p(_rose));
  c.drawPath(cup, _p(_ink, stroke: true, width: 2.2));
}

void _tree(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(44, 58, 56, 90), const Radius.circular(3)),
    _p(_brown),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(44, 58, 56, 90), const Radius.circular(3)),
    _p(_ink, stroke: true, width: 2),
  );
  // 云朵形树冠（结构与 _cloud 相同的鼓包曲线）。
  final crown = Path()
    ..moveTo(18, 58)
    ..cubicTo(4, 58, 8, 38, 24, 41)
    ..cubicTo(26, 22, 54, 20, 60, 36)
    ..cubicTo(78, 30, 88, 48, 76, 57)
    ..cubicTo(80, 68, 66, 74, 58, 66)
    ..close();
  c.drawPath(crown, _p(_green));
  c.drawPath(crown, _p(_deepGreen, stroke: true, width: 2));
  _circle(c, const Offset(34, 46), 3, _p(_red));
  _circle(c, const Offset(58, 36), 3, _p(_red));
  _circle(c, const Offset(66, 54), 3, _p(_red));
}

void _cactus(Canvas c) {
  final pot = Path()
    ..moveTo(37, 72)
    ..lineTo(63, 72)
    ..lineTo(59, 92)
    ..lineTo(41, 92)
    ..close();
  c.drawPath(pot, _p(_rose));
  c.drawPath(pot, _p(_ink, stroke: true, width: 2));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(33, 64, 67, 74), const Radius.circular(3)),
    _p(_orange),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(33, 64, 67, 74), const Radius.circular(3)),
    _p(_ink, stroke: true, width: 2),
  );
  // 主体与两臂：先整幅铺墨色宽描边、再叠绿色窄描边，拼出整体轮廓。
  final body = Path()
    ..moveTo(50, 28)
    ..lineTo(50, 60);
  final armL = Path()
    ..moveTo(38, 48)
    ..lineTo(26, 48)
    ..lineTo(26, 34);
  final armR = Path()
    ..moveTo(62, 42)
    ..lineTo(74, 42)
    ..lineTo(74, 30);
  for (final shape in [body, armL, armR]) {
    c.drawPath(shape, _p(_ink, stroke: true, width: 26));
  }
  c.drawPath(body, _p(_green, stroke: true, width: 21));
  for (final shape in [armL, armR]) {
    c.drawPath(shape, _p(_green, stroke: true, width: 16));
  }
  // 顶花与刺点
  for (var i = 0; i < 5; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / 5;
    _circle(c, const Offset(50, 13) + Offset(6 * math.cos(a), 6 * math.sin(a)), 4, _p(_pink));
  }
  _circle(c, const Offset(50, 13), 3, _p(_yellow));
  final spike = _p(_ink, stroke: true, width: 1.6);
  c.drawLine(const Offset(40, 32), const Offset(35, 30), spike);
  c.drawLine(const Offset(40, 50), const Offset(35, 52), spike);
  c.drawLine(const Offset(60, 36), const Offset(65, 34), spike);
  c.drawLine(const Offset(60, 54), const Offset(65, 56), spike);
}

void _potted(Canvas c) {
  // 披针叶：从盆口散开，先外后内叠放。
  void leaf(Offset tip, double w, Color color) {
    const base = Offset(50, 60);
    final mid = Offset((base.dx + tip.dx) / 2, (base.dy + tip.dy) / 2);
    final dx = tip.dx - base.dx, dy = tip.dy - base.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final n = Offset(-dy / len, dx / len);
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(mid.dx + n.dx * w, mid.dy + n.dy * w, tip.dx, tip.dy)
      ..quadraticBezierTo(mid.dx - n.dx * w, mid.dy - n.dy * w, base.dx, base.dy)
      ..close();
    c.drawPath(path, _p(color));
    c.drawPath(path, _p(_deepGreen, stroke: true, width: 1.8));
  }

  leaf(const Offset(12, 44), 9, _green);
  leaf(const Offset(88, 44), 9, _green);
  leaf(const Offset(24, 22), 8, _deepGreen);
  leaf(const Offset(76, 22), 8, _deepGreen);
  leaf(const Offset(50, 8), 7, _green);
  // 白瓷盆
  final pot = Path()
    ..moveTo(30, 62)
    ..lineTo(70, 62)
    ..lineTo(64, 90)
    ..lineTo(36, 90)
    ..close();
  c.drawPath(pot, _p(_cream));
  c.drawPath(pot, _p(_ink, stroke: true, width: 2.2));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(27, 56, 73, 66), const Radius.circular(3)),
    _p(_cream),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(27, 56, 73, 66), const Radius.circular(3)),
    _p(_ink, stroke: true, width: 2.2),
  );
}

void _mushroom(Canvas c) {
  final stem = RRect.fromRectAndRadius(const Rect.fromLTRB(37, 48, 63, 90), const Radius.circular(9));
  c.drawRRect(stem, _p(_cream));
  c.drawRRect(stem, _p(_ink, stroke: true, width: 2.2));
  final cap = Path()
    ..moveTo(12, 52)
    ..cubicTo(12, 24, 30, 10, 50, 10)
    ..cubicTo(70, 10, 88, 24, 88, 52)
    ..quadraticBezierTo(50, 62, 12, 52)
    ..close();
  c.drawPath(cap, _p(_red));
  c.drawPath(cap, _p(_ink, stroke: true, width: 2.2));
  for (final p in const [
    Offset(30, 34),
    Offset(56, 24),
    Offset(70, 42),
    Offset(42, 46),
  ]) {
    _circle(c, p, 5, _p(_white));
  }
  _circle(c, const Offset(44, 66), 2.2, _p(_ink));
  _circle(c, const Offset(56, 66), 2.2, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(44, 68, 56, 78),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2),
  );
  _circle(c, const Offset(38, 72), 4, _p(_pink));
  _circle(c, const Offset(62, 72), 4, _p(_pink));
}

void _snowflake(Canvas c) {
  final spoke = _p(_blue, stroke: true, width: 4);
  final branch = _p(_deepBlue, stroke: true, width: 2.6);
  const center = Offset(50, 50);
  for (var i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    final dir = Offset(math.cos(a), math.sin(a));
    c.drawLine(center, center + dir * 38, spoke);
    for (final side in [1.0, -1.0]) {
      final rot = Offset(
        math.cos(a + side * math.pi / 4),
        math.sin(a + side * math.pi / 4),
      );
      final forkAt = center + dir * 22;
      c.drawLine(forkAt, forkAt + rot * 12, branch);
    }
  }
  _circle(c, center, 5, _p(_deepBlue));
}

void _mountain(Canvas c) {
  _circle(c, const Offset(18, 22), 9, _p(_yellow));
  final back = Path()
    ..moveTo(6, 80)
    ..lineTo(42, 28)
    ..lineTo(78, 80)
    ..close();
  final front = Path()
    ..moveTo(30, 82)
    ..lineTo(66, 30)
    ..lineTo(94, 82)
    ..close();
  c.drawPath(back, _p(_blue));
  c.drawPath(front, _p(_deepBlue));
  c.drawPath(back, _p(_ink, stroke: true, width: 2));
  c.drawPath(front, _p(_ink, stroke: true, width: 2));
  // 雪顶：山尖下折两段锯齿。
  c.drawPath(
    Path()
      ..moveTo(42, 28)
      ..lineTo(34, 42)
      ..lineTo(38, 36)
      ..lineTo(42, 42)
      ..lineTo(46, 36)
      ..lineTo(50, 42)
      ..close(),
    _p(_white),
  );
  c.drawPath(
    Path()
      ..moveTo(66, 30)
      ..lineTo(58, 44)
      ..lineTo(62, 38)
      ..lineTo(66, 44)
      ..lineTo(70, 38)
      ..lineTo(74, 44)
      ..close(),
    _p(_white),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(6, 78, 94, 88), const Radius.circular(5)),
    _p(_green),
  );
}

void _wave(Canvas c) {
  _circle(c, const Offset(74, 18), 9, _p(_yellow));
  final colors = [_blue, _deepBlue, _blue];
  for (var row = 0; row < 3; row++) {
    final y = 44.0 + row * 18;
    final humps = Path()..moveTo(2, y);
    for (var cx = 14.0; cx < 98; cx += 24) {
      humps.arcTo(
        Rect.fromCircle(center: Offset(cx, y), radius: 12),
        math.pi,
        math.pi,
        false,
      );
    }
    final fill = Path.from(humps)
      ..lineTo(98, 96)
      ..lineTo(2, 96)
      ..close();
    c.drawPath(fill, _p(colors[row]));
    // 只描波浪顶，下面由后一行覆盖。
    c.drawPath(humps, _p(_ink, stroke: true, width: 2));
  }
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

void _boba(Canvas c) {
  final cup = Path()
    ..moveTo(28, 26)
    ..lineTo(72, 26)
    ..lineTo(66, 88)
    ..lineTo(34, 88)
    ..close();
  c.drawPath(cup, _p(_cream));
  // 奶茶液面在 42，两侧按杯身斜度内收。
  final tea = Path()
    ..moveTo(29.4, 42)
    ..lineTo(70.6, 42)
    ..lineTo(66, 88)
    ..lineTo(34, 88)
    ..close();
  c.drawPath(tea, _p(_milkTea));
  for (final p in const [
    Offset(39, 81),
    Offset(49, 83),
    Offset(59, 81),
    Offset(44, 73),
    Offset(55, 73),
  ]) {
    _circle(c, p, 4, _p(_brown));
  }
  c.drawPath(cup, _p(_ink, stroke: true, width: 2.2));
  // 吸管只画到杯口下沿，再由杯口罩住接缝。
  final straw = Path()
    ..moveTo(57, 4)
    ..lineTo(65, 4)
    ..lineTo(52, 28)
    ..lineTo(44, 28)
    ..close();
  c.drawPath(straw, _p(_rose));
  c.drawPath(straw, _p(_ink, stroke: true, width: 2));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(26, 18, 74, 28), const Radius.circular(4)),
    _p(_rose),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(26, 18, 74, 28), const Radius.circular(4)),
    _p(_ink, stroke: true, width: 2),
  );
}

void _toast(Canvas c) {
  final crust = Path()
    ..moveTo(26, 88)
    ..lineTo(26, 40)
    ..quadraticBezierTo(26, 16, 50, 16)
    ..quadraticBezierTo(74, 16, 74, 40)
    ..lineTo(74, 88)
    ..close();
  c.drawPath(crust, _p(_orange));
  final inner = Path()
    ..moveTo(34, 82)
    ..lineTo(34, 42)
    ..quadraticBezierTo(34, 26, 50, 26)
    ..quadraticBezierTo(66, 26, 66, 42)
    ..lineTo(66, 82)
    ..close();
  c.drawPath(inner, _p(_cream));
  c.drawPath(crust, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(42, 48), 2.6, _p(_ink));
  _circle(c, const Offset(58, 48), 2.6, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(43, 52, 57, 66),
    0.15 * math.pi,
    0.7 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2.4),
  );
  _circle(c, const Offset(36, 56), 4, _p(_pink));
  _circle(c, const Offset(64, 56), 4, _p(_pink));
}

void _onigiri(Canvas c) {
  final body = Path()
    ..moveTo(50, 10)
    ..quadraticBezierTo(58, 12, 66, 30)
    ..quadraticBezierTo(78, 52, 86, 72)
    ..quadraticBezierTo(88, 82, 78, 82)
    ..lineTo(22, 82)
    ..quadraticBezierTo(12, 82, 14, 72)
    ..quadraticBezierTo(22, 52, 34, 30)
    ..quadraticBezierTo(42, 12, 50, 10)
    ..close();
  c.drawPath(body, _p(_white));
  c.drawPath(body, _p(_ink, stroke: true, width: 2.2));
  final nori = RRect.fromRectAndRadius(const Rect.fromLTRB(34, 60, 66, 84), const Radius.circular(5));
  c.drawRRect(nori, _p(_deepGreen));
  c.drawRRect(nori, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(40, 42), 2.4, _p(_ink));
  _circle(c, const Offset(60, 42), 2.4, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(45, 46, 55, 56),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2.2),
  );
  _circle(c, const Offset(32, 50), 3.5, _p(_pink));
  _circle(c, const Offset(68, 50), 3.5, _p(_pink));
}

void _cupcake(Canvas c) {
  final cup = Path()
    ..moveTo(30, 52)
    ..lineTo(70, 52)
    ..lineTo(63, 88)
    ..lineTo(37, 88)
    ..close();
  c.drawPath(cup, _p(_rose));
  // 杯壁竖纹随锥度内收。
  for (final x in [40.0, 50.0, 60.0]) {
    final t = (x - 30) / 40;
    c.drawLine(Offset(x, 54), Offset(37 + t * 26, 86), _p(_pink, stroke: true, width: 3));
  }
  c.drawPath(cup, _p(_ink, stroke: true, width: 2.2));
  // 云朵形奶油（结构同 _cloud）。
  final frost = Path()
    ..moveTo(26, 52)
    ..cubicTo(16, 52, 18, 38, 30, 40)
    ..cubicTo(28, 24, 44, 18, 50, 30)
    ..cubicTo(56, 18, 72, 24, 70, 40)
    ..cubicTo(82, 38, 84, 52, 74, 52)
    ..close();
  c.drawPath(frost, _p(_cream));
  c.drawPath(frost, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(50, 14), 5, _p(_red));
  _circle(c, const Offset(50, 14), 5, _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(51, 10), const Offset(56, 3), _p(_deepGreen, stroke: true, width: 2));
}

void _cookie(Canvas c) {
  // 八瓣圆弧曲奇边。
  const center = Offset(50, 52);
  const rim = 33.0;
  final path = Path();
  var prev = center + const Offset(0, -rim);
  path.moveTo(prev.dx, prev.dy);
  for (var k = 1; k <= 8; k++) {
    final a = -math.pi / 2 + k * math.pi / 4;
    final next = center + Offset(rim * math.cos(a), rim * math.sin(a));
    final mid = Offset((prev.dx + next.dx) / 2, (prev.dy + next.dy) / 2);
    final n = Offset((mid.dx - center.dx) / 14, (mid.dy - center.dy) / 14);
    path.quadraticBezierTo(mid.dx + n.dx * 8, mid.dy + n.dy * 8, next.dx, next.dy);
    prev = next;
  }
  path.close();
  c.drawPath(path, _p(_orange));
  c.drawPath(path, _p(_ink, stroke: true, width: 2.2));
  for (final p in const [
    Offset(40, 42),
    Offset(60, 46),
    Offset(48, 62),
    Offset(62, 64),
    Offset(38, 58),
  ]) {
    _circle(c, p, 3.5, _p(_brown));
  }
}

void _lemon(Canvas c) {
  c.drawLine(const Offset(50, 32), const Offset(47, 16), _p(_deepGreen, stroke: true, width: 3));
  final leaf = Path()
    ..moveTo(47, 18)
    ..quadraticBezierTo(30, 6, 16, 12)
    ..quadraticBezierTo(28, 28, 47, 18)
    ..close();
  c.drawPath(leaf, _p(_green));
  c.drawPath(leaf, _p(_deepGreen, stroke: true, width: 1.8));
  c.drawOval(const Rect.fromLTRB(16, 30, 84, 74), _p(_yellow));
  c.drawOval(const Rect.fromLTRB(16, 30, 84, 74), _p(_ink, stroke: true, width: 2.2));
  c.drawArc(
    const Rect.fromLTRB(26, 38, 48, 60),
    math.pi,
    math.pi * 0.7,
    false,
    _p(_white, stroke: true, width: 4),
  );
}

void _peach(Canvas c) {
  c.drawLine(const Offset(50, 26), const Offset(52, 12), _p(_brown, stroke: true, width: 3));
  final body = Path()
    ..moveTo(50, 24)
    ..cubicTo(38, 18, 20, 30, 20, 52)
    ..cubicTo(20, 76, 34, 88, 50, 88)
    ..cubicTo(66, 88, 80, 76, 80, 52)
    ..cubicTo(80, 30, 62, 18, 50, 24)
    ..close();
  c.drawPath(body, _p(_pink));
  c.drawPath(body, _p(_ink, stroke: true, width: 2.2));
  // 叶片画在果体之后，避免果体轮廓线穿过叶面。
  final leaf = Path()
    ..moveTo(52, 14)
    ..quadraticBezierTo(66, 2, 84, 8)
    ..quadraticBezierTo(72, 18, 52, 14)
    ..close();
  c.drawPath(leaf, _p(_green));
  c.drawPath(leaf, _p(_deepGreen, stroke: true, width: 1.8));
  c.drawPath(
    Path()
      ..moveTo(50, 24)
      ..quadraticBezierTo(44, 46, 50, 66),
    _p(_rose, stroke: true, width: 2.4),
  );
  _circle(c, const Offset(34, 62), 5, _p(_rose));
  _circle(c, const Offset(66, 62), 5, _p(_rose));
}

void _sushi(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_deepGreen));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(50, 50), 26, _p(_white));
  for (final p in const [
    Offset(38, 42),
    Offset(62, 42),
    Offset(38, 58),
    Offset(62, 58),
    Offset(50, 68),
    Offset(50, 34),
  ]) {
    _circle(c, p, 1.6, _p(_cream));
  }
  // 三文鱼玫瑰：五瓣拉开间距，避免糊成一圈靶心。
  for (var i = 0; i < 5; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / 5;
    _circle(
      c,
      const Offset(50, 50) + Offset(9 * math.cos(a), 9 * math.sin(a)),
      5,
      _p(_rose),
    );
  }
  _circle(c, const Offset(50, 50), 4.5, _p(_orange));
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

void _pencil(Canvas c) {
  c.save();
  c.translate(50, 50);
  c.rotate(math.pi * 0.78);
  // 自上而下：橡皮头 / 金属箍 / 笔杆 / 笔尖 / 铅芯。
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(-7, -42, 7, -30), const Radius.circular(3)),
    _p(_rose),
  );
  c.drawRect(const Rect.fromLTRB(-7, -30, 7, -22), _p(_blue));
  c.drawRect(const Rect.fromLTRB(-7, -22, 7, 28), _p(_yellow));
  c.drawLine(const Offset(-2.5, -22), const Offset(-2.5, 28), _p(_orange, stroke: true, width: 1.2));
  c.drawLine(const Offset(2.5, -22), const Offset(2.5, 28), _p(_orange, stroke: true, width: 1.2));
  final tip = Path()
    ..moveTo(-7, 28)
    ..lineTo(7, 28)
    ..lineTo(0, 46)
    ..close();
  c.drawPath(tip, _p(_cream));
  c.drawPath(
    Path()
      ..moveTo(-2.6, 38.5)
      ..lineTo(2.6, 38.5)
      ..lineTo(0, 46)
      ..close(),
    _p(_ink),
  );
  c.drawPath(tip, _p(_ink, stroke: true, width: 1.6));
  c.drawRect(const Rect.fromLTRB(-7, -30, 7, 28), _p(_ink, stroke: true, width: 2));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(-7, -42, 7, -30), const Radius.circular(3)),
    _p(_ink, stroke: true, width: 2),
  );
  c.restore();
}

void _brush(Canvas c) {
  c.save();
  c.translate(50, 50);
  c.rotate(-math.pi * 0.75);
  final handle = RRect.fromRectAndRadius(const Rect.fromLTRB(-6, -44, 6, -8), const Radius.circular(5));
  c.drawRRect(handle, _p(_orange));
  c.drawRect(const Rect.fromLTRB(-7, -8, 7, 2), _p(_cream));
  final hair = Path()
    ..moveTo(-7, 2)
    ..quadraticBezierTo(-6, 20, -3, 34)
    ..quadraticBezierTo(0, 40, 3, 34)
    ..quadraticBezierTo(6, 20, 7, 2)
    ..close();
  c.drawPath(hair, _p(_purple));
  c.drawRRect(handle, _p(_ink, stroke: true, width: 2));
  c.drawRect(const Rect.fromLTRB(-7, -8, 7, 2), _p(_ink, stroke: true, width: 2));
  c.drawPath(hair, _p(_ink, stroke: true, width: 2));
  // 笔尖蘸的颜料滴。
  _circle(c, const Offset(0, 46), 3.5, _p(_rose));
  c.restore();
}

void _lightbulb(Canvas c) {
  final ray = _p(_orange, stroke: true, width: 3);
  for (var i = 0; i < 8; i++) {
    if (i == 2 || i == 3) continue; // 底部留给灯座
    final a = i * math.pi / 4;
    c.drawLine(
      const Offset(50, 40) + Offset(26 * math.cos(a), 26 * math.sin(a)),
      const Offset(50, 40) + Offset(37 * math.cos(a), 37 * math.sin(a)),
      ray,
    );
  }
  _circle(c, const Offset(50, 40), 17, _p(_yellow));
  final wire = _p(_ink, stroke: true, width: 2);
  c.drawLine(const Offset(44, 46), const Offset(44, 52), wire);
  c.drawLine(const Offset(56, 46), const Offset(56, 52), wire);
  c.drawLine(const Offset(44, 52), const Offset(56, 52), wire);
  c.drawLine(const Offset(47, 48), const Offset(47, 56), wire);
  c.drawLine(const Offset(53, 48), const Offset(53, 56), wire);
  _circle(c, const Offset(50, 40), 17, _p(_ink, stroke: true, width: 2.2));
  c.drawRect(const Rect.fromLTRB(43, 55, 57, 64), _p(_yellow));
  c.drawRect(const Rect.fromLTRB(43, 55, 57, 64), _p(_ink, stroke: true, width: 2));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(41, 62, 59, 74), const Radius.circular(4)),
    _p(_cream),
  );
  c.drawLine(const Offset(44, 67), const Offset(56, 67), _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(44, 71), const Offset(56, 71), _p(_ink, stroke: true, width: 1.8));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(41, 62, 59, 74), const Radius.circular(4)),
    _p(_ink, stroke: true, width: 2),
  );
}

void _umbrella(Canvas c) {
  // 伞面：拱顶 + 底边四段下垂扇贝。
  final canopy = Path()
    ..moveTo(10, 54)
    ..cubicTo(10, 24, 30, 12, 50, 12)
    ..cubicTo(70, 12, 90, 24, 90, 54)
    ..arcToPoint(const Offset(70, 54), radius: const Radius.circular(10), clockwise: true)
    ..arcToPoint(const Offset(50, 54), radius: const Radius.circular(10), clockwise: true)
    ..arcToPoint(const Offset(30, 54), radius: const Radius.circular(10), clockwise: true)
    ..arcToPoint(const Offset(10, 54), radius: const Radius.circular(10), clockwise: true)
    ..close();
  c.drawPath(canopy, _p(_rose));
  final seam = _p(_white, stroke: true, width: 2);
  c.drawPath(
    Path()
      ..moveTo(50, 13)
      ..quadraticBezierTo(35, 31, 30, 54),
    seam,
  );
  c.drawPath(
    Path()
      ..moveTo(50, 13)
      ..quadraticBezierTo(65, 31, 70, 54),
    seam,
  );
  c.drawLine(const Offset(50, 12), const Offset(50, 54), seam);
  c.drawPath(canopy, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(50, 9), 2.5, _p(_ink));
  c.drawLine(const Offset(50, 12), const Offset(50, 80), _p(_ink, stroke: true, width: 3));
  c.drawArc(
    const Rect.fromLTRB(38, 74, 50, 86),
    0,
    math.pi,
    false,
    _p(_ink, stroke: true, width: 3),
  );
  for (final p in const [Offset(18, 70), Offset(82, 66), Offset(10, 56)]) {
    _circle(c, p, 2.5, _p(_blue));
  }
}

void _key(Canvas c) {
  _circle(c, const Offset(50, 26), 15, _p(_yellow));
  c.drawPath(_heartPath(const Offset(50, 26), 7), _p(_cream));
  c.drawPath(_heartPath(const Offset(50, 26), 7), _p(_ink, stroke: true, width: 1.8));
  c.drawRect(const Rect.fromLTRB(45, 40, 55, 84), _p(_yellow));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(55, 66, 63, 73), const Radius.circular(2)),
    _p(_yellow),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(55, 78, 66, 86), const Radius.circular(2)),
    _p(_yellow),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(55, 66, 63, 73), const Radius.circular(2)),
    _p(_ink, stroke: true, width: 1.8),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(55, 78, 66, 86), const Radius.circular(2)),
    _p(_ink, stroke: true, width: 1.8),
  );
  c.drawRect(const Rect.fromLTRB(45, 40, 55, 84), _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(50, 26), 15, _p(_ink, stroke: true, width: 2.2));
}

void _clock(Canvas c) {
  _circle(c, const Offset(30, 20), 9, _p(_rose));
  _circle(c, const Offset(70, 20), 9, _p(_rose));
  _circle(c, const Offset(50, 18), 4, _p(_rose));
  c.drawLine(const Offset(34, 78), const Offset(26, 90), _p(_ink, stroke: true, width: 3.5));
  c.drawLine(const Offset(66, 78), const Offset(74, 90), _p(_ink, stroke: true, width: 3.5));
  _circle(c, const Offset(50, 54), 29, _p(_rose));
  _circle(c, const Offset(50, 54), 23, _p(_white));
  _circle(c, const Offset(50, 54), 29, _p(_ink, stroke: true, width: 2.2));
  final tick = _p(_ink, stroke: true, width: 2);
  c.drawLine(const Offset(50, 34), const Offset(50, 38), tick);
  c.drawLine(const Offset(50, 70), const Offset(50, 74), tick);
  c.drawLine(const Offset(30, 54), const Offset(34, 54), tick);
  c.drawLine(const Offset(66, 54), const Offset(70, 54), tick);
  c.drawLine(const Offset(50, 54), const Offset(40, 44), _p(_ink, stroke: true, width: 3));
  c.drawLine(const Offset(50, 54), const Offset(61, 40), _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(50, 54), 3, _p(_rose));
  _circle(c, const Offset(30, 20), 9, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(70, 20), 9, _p(_ink, stroke: true, width: 2));
}

void _paperclip(Canvas c) {
  final clip = _p(_deepBlue, stroke: true, width: 6)..strokeJoin = StrokeJoin.round;
  c.drawPath(
    Path()
      ..moveTo(34, 16)
      ..lineTo(68, 16)
      ..lineTo(68, 76)
      ..lineTo(38, 76)
      ..lineTo(38, 30)
      ..lineTo(60, 30)
      ..lineTo(60, 62)
      ..lineTo(48, 62),
    clip,
  );
}

void _shopping(Canvas c) {
  c.drawArc(const Rect.fromLTRB(34, 12, 48, 40), math.pi, math.pi, false, _p(_rose, stroke: true, width: 3.5));
  c.drawArc(const Rect.fromLTRB(52, 12, 66, 40), math.pi, math.pi, false, _p(_rose, stroke: true, width: 3.5));
  final bag = Path()
    ..moveTo(22, 34)
    ..lineTo(78, 34)
    ..lineTo(73, 90)
    ..lineTo(27, 90)
    ..close();
  c.drawPath(bag, _p(_cream));
  c.drawPath(bag, _p(_ink, stroke: true, width: 2.2));
  c.drawPath(_heartPath(const Offset(50, 58), 11), _p(_rose));
  c.drawPath(_heartPath(const Offset(50, 58), 11), _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(23, 41), const Offset(77, 41), _p(_ink, stroke: true, width: 1.5));
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

void _rabbit(Canvas c) {
  for (final dx in [39.0, 61.0]) {
    c.drawOval(Rect.fromLTRB(dx - 7.5, 7, dx + 7.5, 41), _p(_white));
    c.drawOval(Rect.fromLTRB(dx - 3.5, 14, dx + 3.5, 36), _p(_pink));
    c.drawOval(Rect.fromLTRB(dx - 7.5, 7, dx + 7.5, 41), _p(_ink, stroke: true, width: 2));
  }
  _circle(c, const Offset(50, 60), 27, _p(_white));
  _circle(c, const Offset(50, 60), 27, _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(40, 56), 3, _p(_ink));
  _circle(c, const Offset(60, 56), 3, _p(_ink));
  c.drawPath(
    Path()
      ..moveTo(50, 62)
      ..lineTo(46, 66)
      ..lineTo(54, 66)
      ..close(),
    _p(_rose),
  );
  c.drawArc(
    const Rect.fromLTRB(44, 66, 56, 78),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2),
  );
  _circle(c, const Offset(31, 63), 4, _p(_pink));
  _circle(c, const Offset(69, 63), 4, _p(_pink));
}

void _panda(Canvas c) {
  _circle(c, const Offset(30, 28), 11, _p(_ink));
  _circle(c, const Offset(70, 28), 11, _p(_ink));
  _circle(c, const Offset(50, 54), 30, _p(_white));
  _circle(c, const Offset(50, 54), 30, _p(_ink, stroke: true, width: 2.2));
  for (final side in [-1.0, 1.0]) {
    c.save();
    c.translate(50 + side * 12, 48);
    c.rotate(side * 0.35);
    c.drawOval(const Rect.fromLTRB(-8.5, -10.5, 8.5, 10.5), _p(_ink));
    c.restore();
  }
  _circle(c, const Offset(38, 48), 3.2, _p(_white));
  _circle(c, const Offset(62, 48), 3.2, _p(_white));
  _circle(c, const Offset(38, 48), 1.5, _p(_ink));
  _circle(c, const Offset(62, 48), 1.5, _p(_ink));
  c.drawOval(const Rect.fromLTRB(46, 60, 54, 66), _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(43, 64, 57, 76),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2),
  );
  _circle(c, const Offset(28, 60), 4, _p(_pink));
  _circle(c, const Offset(72, 60), 4, _p(_pink));
}

void _chick(Canvas c) {
  final tuft = _p(_orange, stroke: true, width: 2.5);
  c.drawLine(const Offset(46, 26), const Offset(42, 16), tuft);
  c.drawLine(const Offset(50, 24), const Offset(50, 13), tuft);
  c.drawLine(const Offset(54, 26), const Offset(58, 16), tuft);
  _circle(c, const Offset(50, 56), 27, _p(_yellow));
  _circle(c, const Offset(50, 56), 27, _p(_ink, stroke: true, width: 2.2));
  c.drawArc(const Rect.fromLTRB(20, 52, 40, 72), math.pi * 0.5, math.pi, false, _p(_orange, stroke: true, width: 3));
  c.drawArc(const Rect.fromLTRB(60, 52, 80, 72), -math.pi * 0.5, math.pi, false, _p(_orange, stroke: true, width: 3));
  _circle(c, const Offset(41, 52), 2.8, _p(_ink));
  _circle(c, const Offset(59, 52), 2.8, _p(_ink));
  final beak = Path()
    ..moveTo(45, 58)
    ..lineTo(55, 58)
    ..lineTo(50, 65)
    ..close();
  c.drawPath(beak, _p(_orange));
  c.drawPath(beak, _p(_ink, stroke: true, width: 1.6));
  _circle(c, const Offset(33, 60), 3.5, _p(_pink));
  _circle(c, const Offset(67, 60), 3.5, _p(_pink));
  c.drawLine(const Offset(42, 82), const Offset(42, 90), _p(_orange, stroke: true, width: 2.5));
  c.drawLine(const Offset(58, 82), const Offset(58, 90), _p(_orange, stroke: true, width: 2.5));
}

void _penguin(Canvas c) {
  for (final side in [-1.0, 1.0]) {
    c.save();
    c.translate(50 + side * 27, 56);
    c.rotate(side * 0.5);
    c.drawOval(const Rect.fromLTRB(-6.5, -14, 6.5, 14), _p(_deepBlue));
    c.drawOval(const Rect.fromLTRB(-6.5, -14, 6.5, 14), _p(_ink, stroke: true, width: 2));
    c.restore();
  }
  c.drawOval(const Rect.fromLTRB(22, 20, 78, 84), _p(_deepBlue));
  c.drawOval(const Rect.fromLTRB(32, 39, 68, 81), _p(_white));
  c.drawOval(const Rect.fromLTRB(22, 20, 78, 84), _p(_ink, stroke: true, width: 2.2));
  _circle(c, const Offset(41, 44), 3, _p(_ink));
  _circle(c, const Offset(59, 44), 3, _p(_ink));
  c.drawPath(
    Path()
      ..moveTo(45, 50)
      ..lineTo(55, 50)
      ..lineTo(50, 57)
      ..close(),
    _p(_orange),
  );
  _circle(c, const Offset(34, 50), 3.5, _p(_pink));
  _circle(c, const Offset(66, 50), 3.5, _p(_pink));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(38, 82, 48, 90), const Radius.circular(3)),
    _p(_orange),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(52, 82, 62, 90), const Radius.circular(3)),
    _p(_orange),
  );
}

void _whale(Canvas c) {
  final spout = _p(_deepBlue, stroke: true, width: 2.5);
  c.drawLine(const Offset(40, 28), const Offset(35, 16), spout);
  c.drawLine(const Offset(45, 26), const Offset(45, 12), spout);
  c.drawLine(const Offset(50, 28), const Offset(56, 16), spout);
  final tail = Path()
    ..moveTo(66, 46)
    ..lineTo(90, 30)
    ..quadraticBezierTo(84, 48, 78, 54)
    ..quadraticBezierTo(86, 60, 88, 72)
    ..lineTo(64, 62)
    ..close();
  c.drawPath(tail, _p(_deepBlue));
  c.drawPath(tail, _p(_ink, stroke: true, width: 2));
  final body = Path()
    ..moveTo(10, 58)
    ..cubicTo(10, 32, 40, 26, 52, 34)
    ..cubicTo(66, 40, 72, 46, 72, 56)
    ..cubicTo(70, 72, 52, 78, 36, 74)
    ..cubicTo(18, 70, 10, 66, 10, 58)
    ..close();
  c.drawPath(body, _p(_blue));
  c.drawPath(body, _p(_ink, stroke: true, width: 2.2));
  final ridge = _p(_deepBlue, stroke: true, width: 2);
  c.drawLine(const Offset(26, 68), const Offset(31, 71), ridge);
  c.drawLine(const Offset(34, 71), const Offset(39, 73), ridge);
  c.drawLine(const Offset(42, 73), const Offset(47, 73), ridge);
  _circle(c, const Offset(26, 52), 2.6, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(20, 55, 32, 66),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2),
  );
  _circle(c, const Offset(35, 60), 3.5, _p(_pink));
  _circle(c, const Offset(14, 40), 2.5, _p(_deepBlue));
  _circle(c, const Offset(60, 24), 2.5, _p(_deepBlue));
}

void _snail(Canvas c) {
  // 腹足：宽描边铺墨再叠浅色，圆润的胶囊身体。
  final bodyPath = Path()
    ..moveTo(10, 80)
    ..quadraticBezierTo(40, 92, 62, 74)
    ..quadraticBezierTo(76, 66, 78, 48);
  c.drawPath(bodyPath, _p(_ink, stroke: true, width: 19));
  c.drawPath(bodyPath, _p(_cream, stroke: true, width: 15));
  // 头与触角
  _circle(c, const Offset(78, 44), 9, _p(_cream));
  _circle(c, const Offset(78, 44), 9, _p(_ink, stroke: true, width: 2.2));
  final stalk = _p(_ink, stroke: true, width: 2.2);
  c.drawLine(const Offset(75, 37), const Offset(71, 25), stalk);
  c.drawLine(const Offset(81, 36), const Offset(84, 23), stalk);
  _circle(c, const Offset(71, 23), 3.2, _p(_cream));
  _circle(c, const Offset(84, 21), 3.2, _p(_cream));
  _circle(c, const Offset(71, 23), 1.5, _p(_ink));
  _circle(c, const Offset(84, 21), 1.5, _p(_ink));
  c.drawArc(
    const Rect.fromLTRB(73, 44, 83, 54),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 1.8),
  );
  // 壳与螺旋纹
  _circle(c, const Offset(42, 58), 26, _p(_rose));
  _circle(c, const Offset(42, 58), 26, _p(_ink, stroke: true, width: 2.4));
  final spiral = _p(_white, stroke: true, width: 3);
  c.drawArc(Rect.fromCircle(center: const Offset(42, 58), radius: 17), -math.pi / 2, math.pi * 1.6, false, spiral);
  c.drawArc(Rect.fromCircle(center: const Offset(46, 63), radius: 8), -math.pi / 2, math.pi * 1.5, false, spiral);
}

void _ghost(Canvas c) {
  final body = Path()
    ..moveTo(24, 44)
    ..quadraticBezierTo(24, 16, 50, 16)
    ..quadraticBezierTo(76, 16, 76, 44)
    ..lineTo(76, 74)
    ..arcToPoint(const Offset(64, 74), radius: const Radius.circular(6), clockwise: false)
    ..arcToPoint(const Offset(52, 74), radius: const Radius.circular(6), clockwise: false)
    ..arcToPoint(const Offset(40, 74), radius: const Radius.circular(6), clockwise: false)
    ..arcToPoint(const Offset(28, 74), radius: const Radius.circular(6), clockwise: false)
    ..lineTo(24, 74)
    ..close();
  c.drawPath(body, _p(_white));
  c.drawPath(body, _p(_ink, stroke: true, width: 2.2));
  c.drawOval(const Rect.fromLTRB(37, 39, 45, 50), _p(_ink));
  c.drawOval(const Rect.fromLTRB(55, 39, 63, 50), _p(_ink));
  c.drawOval(const Rect.fromLTRB(46, 56, 54, 66), _p(_ink));
  _circle(c, const Offset(31, 55), 4.5, _p(_pink));
  _circle(c, const Offset(69, 55), 4.5, _p(_pink));
  c.drawPath(_starPath(const Offset(85, 20), 8), _p(_yellow));
}

void _paw(Canvas c) {
  _circle(c, const Offset(24, 42), 8.5, _p(_pink));
  _circle(c, const Offset(42, 30), 9.5, _p(_pink));
  _circle(c, const Offset(60, 30), 9.5, _p(_pink));
  _circle(c, const Offset(78, 42), 8.5, _p(_pink));
  _circle(c, const Offset(36, 62), 12, _p(_rose));
  _circle(c, const Offset(64, 62), 12, _p(_rose));
  _circle(c, const Offset(50, 66), 13, _p(_rose));
}

// ---------------------------------------------------------------------------
// 旅行
// ---------------------------------------------------------------------------

void _paperplane(Canvas c) {
  final trail = _p(_blue, stroke: true, width: 3);
  c.drawLine(const Offset(8, 84), const Offset(18, 78), trail);
  c.drawLine(const Offset(16, 90), const Offset(30, 82), trail);
  c.drawLine(const Offset(26, 94), const Offset(42, 85), trail);
  final top = Path()
    ..moveTo(90, 18)
    ..lineTo(14, 48)
    ..lineTo(58, 54)
    ..close();
  final bottom = Path()
    ..moveTo(90, 18)
    ..lineTo(58, 54)
    ..lineTo(60, 72)
    ..close();
  c.drawPath(top, _p(_white));
  c.drawPath(bottom, _p(_cream));
  c.drawPath(top, _p(_ink, stroke: true, width: 2.2));
  c.drawPath(bottom, _p(_ink, stroke: true, width: 2.2));
  c.drawLine(const Offset(90, 18), const Offset(58, 54), _p(_ink, stroke: true, width: 1.6));
}

void _suitcase(Canvas c) {
  c.drawArc(const Rect.fromLTRB(36, 14, 64, 40), math.pi, math.pi, false, _p(_brown, stroke: true, width: 5));
  final box = RRect.fromRectAndRadius(const Rect.fromLTRB(14, 32, 86, 90), const Radius.circular(10));
  c.drawRRect(box, _p(_rose));
  for (final x in [28.0, 62.0]) {
    c.drawRect(Rect.fromLTRB(x, 32, x + 10, 90), _p(_orange));
  }
  c.drawRRect(box, _p(_ink, stroke: true, width: 2.2));
  c.drawRect(const Rect.fromLTRB(46, 32, 54, 42), _p(_yellow));
  c.drawRect(const Rect.fromLTRB(46, 32, 54, 42), _p(_ink, stroke: true, width: 1.8));
  c.drawPath(_starPath(const Offset(50, 60), 11), _p(_yellow));
  c.drawPath(_starPath(const Offset(50, 60), 11), _p(_ink, stroke: true, width: 1.6));
}

void _tent(Canvas c) {
  final body = Path()
    ..moveTo(8, 86)
    ..lineTo(50, 18)
    ..lineTo(92, 86)
    ..close();
  c.drawPath(body, _p(_green));
  c.drawPath(
    Path()
      ..moveTo(50, 34)
      ..lineTo(33, 86)
      ..lineTo(67, 86)
      ..close(),
    _p(_deepGreen),
  );
  c.drawPath(body, _p(_ink, stroke: true, width: 2.2));
  c.drawLine(const Offset(50, 34), const Offset(33, 86), _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(50, 34), const Offset(67, 86), _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(50, 18), const Offset(50, 8), _p(_brown, stroke: true, width: 2.5));
  c.drawPath(
    Path()
      ..moveTo(50, 8)
      ..lineTo(64, 12)
      ..lineTo(50, 16)
      ..close(),
    _p(_red),
  );
  c.drawLine(const Offset(10, 86), const Offset(90, 86), _p(_deepGreen, stroke: true, width: 3));
}

void _map(Canvas c) {
  final panels = [
    Path()
      ..moveTo(12, 30)
      ..lineTo(36, 24)
      ..lineTo(36, 80)
      ..lineTo(12, 86)
      ..close(),
    Path()
      ..moveTo(36, 24)
      ..lineTo(62, 30)
      ..lineTo(62, 86)
      ..lineTo(36, 80)
      ..close(),
    Path()
      ..moveTo(62, 30)
      ..lineTo(88, 24)
      ..lineTo(88, 80)
      ..lineTo(62, 86)
      ..close(),
  ];
  for (final p in panels) {
    c.drawPath(p, _p(_cream));
    c.drawPath(p, _p(_ink, stroke: true, width: 2));
  }
  // 虚线路线：逐段画前半截、空后半截。
  final route = _p(_rose, stroke: true, width: 3);
  const pts = [Offset(20, 70), Offset(34, 58), Offset(48, 64), Offset(60, 44), Offset(70, 42)];
  for (var i = 0; i < pts.length - 1; i++) {
    c.drawLine(
      pts[i],
      Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2),
      route,
    );
  }
  // 起点叉、终点大头针
  final mark = _p(_ink, stroke: true, width: 2.5);
  c.drawLine(const Offset(17, 67), const Offset(23, 73), mark);
  c.drawLine(const Offset(23, 67), const Offset(17, 73), mark);
  c.drawPath(
    Path()
      ..moveTo(66, 40)
      ..lineTo(78, 40)
      ..lineTo(72, 54)
      ..close(),
    _p(_red),
  );
  _circle(c, const Offset(72, 36), 8, _p(_red));
  _circle(c, const Offset(72, 36), 8, _p(_ink, stroke: true, width: 2));
  _circle(c, const Offset(72, 36), 3, _p(_white));
}

void _compass(Canvas c) {
  _circle(c, const Offset(50, 12), 5, _p(_ink, stroke: true, width: 3));
  c.drawLine(const Offset(50, 14), const Offset(50, 21), _p(_ink, stroke: true, width: 3));
  _circle(c, const Offset(50, 54), 34, _p(_yellow));
  _circle(c, const Offset(50, 54), 26, _p(_white));
  _circle(c, const Offset(50, 54), 34, _p(_ink, stroke: true, width: 2.2));
  final tick = _p(_ink, stroke: true, width: 2);
  c.drawLine(const Offset(50, 31), const Offset(50, 36), tick);
  c.drawLine(const Offset(50, 72), const Offset(50, 77), tick);
  c.drawLine(const Offset(27, 54), const Offset(32, 54), tick);
  c.drawLine(const Offset(68, 54), const Offset(73, 54), tick);
  final south = Path()
    ..moveTo(50, 76)
    ..lineTo(44, 54)
    ..lineTo(56, 54)
    ..close();
  final north = Path()
    ..moveTo(50, 32)
    ..lineTo(44, 54)
    ..lineTo(56, 54)
    ..close();
  c.drawPath(south, _p(_deepBlue));
  c.drawPath(south, _p(_ink, stroke: true, width: 1.6));
  c.drawPath(north, _p(_rose));
  c.drawPath(north, _p(_ink, stroke: true, width: 1.6));
  _circle(c, const Offset(50, 54), 3, _p(_ink));
}

void _hotairballoon(Canvas c) {
  final balloon = Path()
    ..moveTo(50, 8)
    ..cubicTo(24, 8, 16, 34, 16, 46)
    ..cubicTo(16, 58, 34, 66, 42, 72)
    ..lineTo(58, 72)
    ..cubicTo(66, 66, 84, 58, 84, 46)
    ..cubicTo(84, 34, 76, 8, 50, 8)
    ..close();
  c.drawPath(balloon, _p(_rose));
  c.drawPath(
    Path()
      ..moveTo(50, 8)
      ..cubicTo(42, 26, 42, 50, 46, 72)
      ..lineTo(54, 72)
      ..cubicTo(58, 50, 58, 26, 50, 8)
      ..close(),
    _p(_yellow),
  );
  final seam = _p(_ink, stroke: true, width: 1.4);
  c.drawPath(
    Path()
      ..moveTo(36, 10)
      ..cubicTo(30, 28, 30, 52, 44, 71),
    seam,
  );
  c.drawPath(
    Path()
      ..moveTo(64, 10)
      ..cubicTo(70, 28, 70, 52, 56, 71),
    seam,
  );
  c.drawPath(balloon, _p(_ink, stroke: true, width: 2.2));
  c.drawLine(const Offset(43, 72), const Offset(45, 82), _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(57, 72), const Offset(55, 82), _p(_ink, stroke: true, width: 1.8));
  final basket = RRect.fromRectAndRadius(const Rect.fromLTRB(42, 82, 58, 94), const Radius.circular(3));
  c.drawRRect(basket, _p(_brown));
  c.drawRRect(basket, _p(_ink, stroke: true, width: 1.8));
  c.drawLine(const Offset(42, 88), const Offset(58, 88), _p(_ink, stroke: true, width: 1.5));
  _circle(c, const Offset(12, 22), 5, _p(_blue));
  _circle(c, const Offset(17, 26), 6, _p(_blue));
  _circle(c, const Offset(22, 22), 5, _p(_blue));
}

void _bicycle(Canvas c) {
  final tire = _p(_ink, stroke: true, width: 3.5);
  final spoke = _p(_ink, stroke: true, width: 1.5);
  for (final hub in const [Offset(26, 68), Offset(74, 68)]) {
    _circle(c, hub, 17, tire);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 4;
      final d = Offset(13 * math.cos(a), 13 * math.sin(a));
      c.drawLine(hub - d, hub + d, spoke);
    }
    _circle(c, hub, 2, _p(_ink));
  }
  final frame = _p(_rose, stroke: true, width: 3.5);
  c.drawLine(const Offset(26, 68), const Offset(48, 64), frame);
  c.drawLine(const Offset(26, 68), const Offset(43, 38), frame);
  c.drawLine(const Offset(48, 64), const Offset(43, 38), frame);
  c.drawLine(const Offset(43, 38), const Offset(64, 38), frame);
  c.drawLine(const Offset(48, 64), const Offset(64, 38), frame);
  c.drawLine(const Offset(64, 38), const Offset(74, 68), frame);
  c.drawLine(const Offset(36, 34), const Offset(48, 34), _p(_ink, stroke: true, width: 4));
  c.drawLine(const Offset(64, 38), const Offset(64, 30), _p(_ink, stroke: true, width: 3));
  c.drawLine(const Offset(58, 30), const Offset(70, 30), _p(_ink, stroke: true, width: 3.5));
  _circle(c, const Offset(48, 64), 3.5, _p(_ink));
  c.drawLine(const Offset(44, 64), const Offset(52, 64), _p(_ink, stroke: true, width: 3));
}

void _lighthouse(Canvas c) {
  final ray = _p(_yellow, stroke: true, width: 4);
  c.drawLine(const Offset(38, 20), const Offset(16, 12), ray);
  c.drawLine(const Offset(37, 26), const Offset(14, 26), ray);
  c.drawLine(const Offset(62, 20), const Offset(84, 12), ray);
  c.drawLine(const Offset(63, 26), const Offset(86, 26), ray);
  final tower = Path()
    ..moveTo(40, 34)
    ..lineTo(60, 34)
    ..lineTo(66, 84)
    ..lineTo(34, 84)
    ..close();
  c.drawPath(tower, _p(_white));
  // 红色环带随塔身锥度内收。
  void band(double y0, double y1) {
    final w0 = 10 + (y0 - 34) * 0.12, w1 = 10 + (y1 - 34) * 0.12;
    c.drawPath(
      Path()
        ..moveTo(50 - w0, y0)
        ..lineTo(50 + w0, y0)
        ..lineTo(50 + w1, y1)
        ..lineTo(50 - w1, y1)
        ..close(),
      _p(_red),
    );
  }

  band(46, 60);
  band(64, 78);
  c.drawPath(tower, _p(_ink, stroke: true, width: 2.2));
  c.drawRect(const Rect.fromLTRB(36, 34, 64, 40), _p(_rose));
  c.drawRect(const Rect.fromLTRB(36, 34, 64, 40), _p(_ink, stroke: true, width: 2));
  c.drawRect(const Rect.fromLTRB(42, 22, 58, 34), _p(_yellow));
  c.drawRect(const Rect.fromLTRB(42, 22, 58, 34), _p(_ink, stroke: true, width: 2));
  final roof = Path()
    ..moveTo(38, 22)
    ..lineTo(62, 22)
    ..lineTo(50, 10)
    ..close();
  c.drawPath(roof, _p(_red));
  c.drawPath(roof, _p(_ink, stroke: true, width: 2));
  final wave = _p(_blue, stroke: true, width: 3);
  c.drawArc(const Rect.fromLTRB(6, 78, 34, 96), math.pi, math.pi * 0.9, false, wave);
  c.drawArc(const Rect.fromLTRB(64, 78, 94, 96), 0, -math.pi * 0.9, false, wave);
}

// ---------------------------------------------------------------------------
// 心情
// ---------------------------------------------------------------------------

void _loveface(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_pink));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  c.drawPath(_heartPath(const Offset(38, 44), 8), _p(_rose));
  c.drawPath(_heartPath(const Offset(38, 44), 8), _p(_ink, stroke: true, width: 1.6));
  c.drawPath(_heartPath(const Offset(62, 44), 8), _p(_rose));
  c.drawPath(_heartPath(const Offset(62, 44), 8), _p(_ink, stroke: true, width: 1.6));
  c.drawArc(
    const Rect.fromLTRB(34, 52, 66, 78),
    0.15 * math.pi,
    0.7 * math.pi,
    false,
    _p(_ink, stroke: true, width: 3),
  );
  _circle(c, const Offset(26, 56), 5, _p(_rose));
  _circle(c, const Offset(74, 56), 5, _p(_rose));
  c.drawPath(_heartPath(const Offset(80, 14), 7), _p(_rose));
}

void _sleepy(Canvas c) {
  _circle(c, const Offset(50, 52), 32, _p(_blue));
  _circle(c, const Offset(50, 52), 32, _p(_ink, stroke: true, width: 2.2));
  // 闭眼（向下弧）
  c.drawArc(const Rect.fromLTRB(32, 44, 46, 52), 0, math.pi, false, _p(_ink, stroke: true, width: 2.6));
  c.drawArc(const Rect.fromLTRB(54, 44, 68, 52), 0, math.pi, false, _p(_ink, stroke: true, width: 2.6));
  c.drawOval(const Rect.fromLTRB(45, 62, 55, 74), _p(_ink));
  _circle(c, const Offset(24, 58), 5, _p(_pink));
  _circle(c, const Offset(76, 58), 5, _p(_pink));
  // Zzz
  final z = _p(_deepBlue, stroke: true, width: 2.6);
  void zzz(Offset o, double s) {
    c.drawLine(o, o + Offset(s, 0), z);
    c.drawLine(o + Offset(s, 0), o + Offset(0, s), z);
    c.drawLine(o + Offset(0, s), o + Offset(s, s), z);
  }

  zzz(const Offset(66, 6), 10);
  zzz(const Offset(82, 16), 7);
}

void _shy(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_pink));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  // 眯眯眼（向上弧）
  c.drawArc(const Rect.fromLTRB(32, 42, 46, 52), math.pi, math.pi, false, _p(_ink, stroke: true, width: 2.6));
  c.drawArc(const Rect.fromLTRB(54, 42, 68, 52), math.pi, math.pi, false, _p(_ink, stroke: true, width: 2.6));
  // 斜纹腮红
  _circle(c, const Offset(28, 58), 8, _p(_rose));
  _circle(c, const Offset(72, 58), 8, _p(_rose));
  final line = _p(_red, stroke: true, width: 1.5);
  c.drawLine(const Offset(24, 56), const Offset(30, 62), line);
  c.drawLine(const Offset(28, 54), const Offset(34, 60), line);
  c.drawLine(const Offset(68, 56), const Offset(74, 62), line);
  c.drawLine(const Offset(72, 54), const Offset(78, 60), line);
  c.drawArc(
    const Rect.fromLTRB(45, 60, 55, 70),
    0.2 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2.2),
  );
  c.drawPath(_starPath(const Offset(84, 20), 7), _p(_yellow));
}

void _teary(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_cream));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  // 八字眉
  final brow = _p(_ink, stroke: true, width: 2.2);
  c.drawLine(const Offset(32, 38), const Offset(44, 42), brow);
  c.drawLine(const Offset(68, 38), const Offset(56, 42), brow);
  _circle(c, const Offset(39, 50), 3, _p(_ink));
  _circle(c, const Offset(61, 50), 3, _p(_ink));
  final tear = Path()
    ..moveTo(36, 54)
    ..cubicTo(31, 62, 32, 68, 36, 68)
    ..cubicTo(40, 68, 41, 62, 36, 54)
    ..close();
  c.drawPath(tear, _p(_blue));
  c.drawPath(tear, _p(_deepBlue, stroke: true, width: 1.6));
  // 波浪嘴
  final mouth = _p(_ink, stroke: true, width: 2.4);
  c.drawLine(const Offset(40, 64), const Offset(45, 68), mouth);
  c.drawLine(const Offset(45, 68), const Offset(50, 64), mouth);
  c.drawLine(const Offset(50, 64), const Offset(55, 68), mouth);
  c.drawLine(const Offset(55, 68), const Offset(60, 64), mouth);
}

void _angry(Canvas c) {
  _circle(c, const Offset(50, 52), 33, _p(_rose));
  _circle(c, const Offset(50, 52), 33, _p(_ink, stroke: true, width: 2.2));
  final brow = _p(_ink, stroke: true, width: 3);
  c.drawLine(const Offset(32, 38), const Offset(45, 45), brow);
  c.drawLine(const Offset(68, 38), const Offset(55, 45), brow);
  _circle(c, const Offset(40, 52), 3, _p(_ink));
  _circle(c, const Offset(60, 52), 3, _p(_ink));
  // 抿嘴（倒弧）
  c.drawArc(const Rect.fromLTRB(40, 60, 60, 72), math.pi, math.pi, false, _p(_ink, stroke: true, width: 2.6));
  // 怒气符号
  final mark = _p(_red, stroke: true, width: 3);
  for (var i = 0; i < 4; i++) {
    c.drawArc(
      const Rect.fromLTRB(72, 6, 92, 26),
      math.pi * 0.15 + i * math.pi / 2,
      math.pi * 0.45,
      false,
      mark,
    );
  }
}

void _wow(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_orange));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  for (final dx in [38.0, 62.0]) {
    _circle(c, Offset(dx, 44), 8, _p(_white));
    _circle(c, Offset(dx, 44), 8, _p(_ink, stroke: true, width: 1.8));
    _circle(c, Offset(dx, 45), 3.2, _p(_ink));
  }
  c.drawOval(const Rect.fromLTRB(43, 60, 57, 76), _p(_ink));
  _circle(c, const Offset(26, 56), 5, _p(_rose));
  _circle(c, const Offset(74, 56), 5, _p(_rose));
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(80, 8, 85, 22), const Radius.circular(2.5)),
    _p(_red),
  );
  _circle(c, const Offset(82.5, 29), 2.8, _p(_red));
}

void _cool(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_purple));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(20, 38, 46, 56), const Radius.circular(7)), _p(_ink));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(54, 38, 80, 56), const Radius.circular(7)), _p(_ink));
  c.drawLine(const Offset(46, 44), const Offset(54, 44), _p(_ink, stroke: true, width: 3));
  c.drawLine(const Offset(20, 42), const Offset(14, 38), _p(_ink, stroke: true, width: 2.5));
  c.drawLine(const Offset(80, 42), const Offset(86, 38), _p(_ink, stroke: true, width: 2.5));
  // 镜片反光
  c.drawLine(const Offset(26, 50), const Offset(32, 42), _p(_white, stroke: true, width: 2));
  c.drawLine(const Offset(60, 50), const Offset(66, 42), _p(_white, stroke: true, width: 2));
  c.drawArc(
    const Rect.fromLTRB(38, 58, 62, 74),
    0.1 * math.pi,
    0.6 * math.pi,
    false,
    _p(_ink, stroke: true, width: 2.6),
  );
}

void _dizzy(Canvas c) {
  _circle(c, const Offset(50, 50), 34, _p(_cream));
  _circle(c, const Offset(50, 50), 34, _p(_ink, stroke: true, width: 2.2));
  // 螺旋眼：内圈小弧接外圈大弧。
  final pen = _p(_ink, stroke: true, width: 2.2);
  void spiral(Offset o) {
    c.drawArc(Rect.fromCircle(center: o, radius: 4), 0, math.pi * 1.5, false, pen);
    c.drawArc(Rect.fromCircle(center: o + const Offset(0, 4), radius: 8), -math.pi / 2, math.pi * 1.4, false, pen);
  }

  spiral(const Offset(38, 46));
  spiral(const Offset(62, 46));
  final mouth = _p(_ink, stroke: true, width: 2.4);
  c.drawLine(const Offset(42, 66), const Offset(47, 70), mouth);
  c.drawLine(const Offset(47, 70), const Offset(52, 66), mouth);
  c.drawLine(const Offset(52, 66), const Offset(57, 70), mouth);
  c.drawPath(_starPath(const Offset(28, 12), 8), _p(_yellow));
  c.drawPath(_starPath(const Offset(48, 6), 6), _p(_yellow));
  c.drawPath(_starPath(const Offset(68, 12), 8), _p(_yellow));
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
      case 'checker':
        final p = Paint()..color = ink;
        for (var x = 0.0, col = 0; x < size.width; x += unit * 2, col++) {
          for (var y = 0.0, row = 0; y < size.height; y += unit, row++) {
            if ((col + row).isEven) {
              canvas.drawRect(Offset(x, y) & Size(unit * 2, unit), p);
            }
          }
        }
      case 'stars':
        final p = Paint()..color = ink;
        for (var x = unit; x < size.width + unit; x += unit * 2) {
          canvas.drawPath(_starPath(Offset(x, size.height / 2), unit * 0.6), p);
        }
      case 'flowers':
        final p = Paint()..color = ink;
        for (var x = unit; x < size.width + unit; x += unit * 2) {
          final c0 = Offset(x, size.height / 2);
          for (var k = 0; k < 5; k++) {
            final a = -math.pi / 2 + k * 2 * math.pi / 5;
            canvas.drawCircle(
              c0 + Offset(unit * 0.42 * math.cos(a), unit * 0.42 * math.sin(a)),
              unit * 0.24,
              p,
            );
          }
          canvas.drawCircle(c0, unit * 0.18, p);
        }
      case 'zigzag':
        final p = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.38
          ..strokeJoin = StrokeJoin.round;
        final path = Path()..moveTo(0, size.height / 2 - unit * 0.45);
        var x = 0.0;
        var up = true;
        while (x < size.width) {
          path.lineTo(
            x + unit,
            size.height / 2 + (up ? unit * 0.45 : -unit * 0.45),
          );
          x += unit;
          up = !up;
        }
        canvas.drawPath(path, p);
      case 'drops':
        final p = Paint()..color = ink;
        void drop(Offset o, double r) {
          final path = Path()
            ..moveTo(o.dx, o.dy - r)
            ..lineTo(o.dx + r * 0.75, o.dy + r * 0.2)
            ..arcToPoint(
              Offset(o.dx - r * 0.75, o.dy + r * 0.2),
              radius: Radius.circular(r * 0.75),
              clockwise: true,
            )
            ..close();
          canvas.drawPath(path, p);
        }

        for (var x = unit; x < size.width + unit; x += unit * 2) {
          drop(Offset(x, size.height * 0.3), unit * 0.42);
          drop(Offset(x + unit, size.height * 0.72), unit * 0.42);
        }
      case 'triangles':
        final p = Paint()..color = ink;
        for (var x = unit * 0.8; x < size.width + unit; x += unit * 1.6) {
          final path = Path()
            ..moveTo(x - unit * 0.7, size.height / 2 + unit * 0.5)
            ..lineTo(x, size.height / 2 - unit * 0.5)
            ..lineTo(x + unit * 0.7, size.height / 2 + unit * 0.5)
            ..close();
          canvas.drawPath(path, p);
        }
    }
  }

  @override
  bool shouldRepaint(covariant TapePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}
