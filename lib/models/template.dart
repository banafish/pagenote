import '../utils/journal_id.dart';
import 'canvas_page.dart';

/// 手账模板（REQ-09 + 调研二阶段整页版式升级）：
/// 文本骨架（title/content/tags）之外可选携带整页画布版式
/// （纸张 + 贴纸/胶带预设 + 文字占位 + 字体），套用后只替换文字即可成稿。
class JournalTemplate {
  JournalTemplate({
    required this.id,
    required this.name,
    this.title = '',
    this.content = '',
    List<String>? tags,
    this.builtin = false,
    this.canvas,
    this.originId,
    this.packId,
    this.lastUsedAt,
    this.sortIndex = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : tags = tags ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;

  /// 模板名（在模板列表中展示）。
  String name;

  /// 套用后填充的手账标题。
  String title;

  /// 套用后填充的分节结构正文。
  String content;
  List<String> tags;

  /// 整页版式；null 为纯文本模板（兼容旧数据）。
  JournalCanvas? canvas;

  /// 内置模板不可删除。
  /// 该标志只能由本机内置清单决定,不接受外部文件的自称（FIX-02）。
  final bool builtin;

  /// 分享包安装而来的模板：原包内 id（FIX-02.2）。
  /// 本地 id 一律重新分配,originId 用于识别「同一模板的新版本」——
  /// 重复导入同一分享包时按它原位更新,而不是再装一份。
  String? originId;

  /// 所属素材包（[StickerPack.id]，v8）；null = 未分组。
  /// 分享包导入时随整包落位；重复导入会把先前散落的同一模板归位回包。
  String? packId;

  /// 最近一次套用时间；null 为从未使用。
  DateTime? lastUsedAt;

  /// 手动排序序号，越小越靠前（REQ-18.4）。
  int sortIndex;

  final DateTime createdAt;
  DateTime updatedAt;

  /// 「今日手账」模板：套用时把当天每日一问自动填入正文占位。
  bool get isTodayTemplate => id == 'builtin-today';

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'title': title,
    'content': content,
    'tags': tags.join('\u001F'),
    'builtin': builtin ? 1 : 0,
    'canvas': encodeCanvas(canvas),
    'originId': originId,
    'packId': packId,
    'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
    'sortIndex': sortIndex,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static JournalTemplate fromMap(Map<String, Object?> map) => JournalTemplate(
    id: map['id']! as String,
    name: map['name']! as String,
    title: (map['title'] ?? '') as String,
    content: (map['content'] ?? '') as String,
    tags: map['tags'] == null || (map['tags'] as String).isEmpty
        ? []
        : (map['tags'] as String).split('\u001F'),
    builtin: (map['builtin'] ?? 0) as int == 1,
    canvas: decodeCanvas((map['canvas'] ?? '') as String),
    originId: map['originId'] as String?,
    packId: map['packId'] as String?,
    lastUsedAt: map['lastUsedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['lastUsedAt']! as int),
    sortIndex: (map['sortIndex'] ?? 0) as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']! as int),
  );

  /// 从不可信的外部文件（备份包 / 分享包）解析（FIX-02.1）。
  /// `builtin` 一律由本机内置清单推导,忽略文件里的自称——否则手工
  /// 改造的包可以塞进永远删不掉的模板。
  static JournalTemplate fromExternalMap(Map<String, Object?> map) {
    final parsed = fromMap(map);
    final trusted = isBuiltinTemplateId(parsed.id);
    if (trusted == parsed.builtin) return parsed;
    return JournalTemplate(
      id: parsed.id,
      name: parsed.name,
      title: parsed.title,
      content: parsed.content,
      tags: parsed.tags,
      builtin: trusted,
      canvas: parsed.canvas,
      originId: parsed.originId,
      packId: parsed.packId,
      lastUsedAt: parsed.lastUsedAt,
      sortIndex: parsed.sortIndex,
      createdAt: parsed.createdAt,
      updatedAt: parsed.updatedAt,
    );
  }

  JournalTemplate copy() => JournalTemplate.fromMap(toMap());

  /// 复制为一份新的用户模板（REQ-18.2「复制一份」/ REQ-18.3「复制内置模板」）。
  /// 新 id + `builtin = false`,因此副本可自由改名、编辑与删除。
  /// 副本不继承 originId / packId：它是用户自己的新模板,
  /// 不再跟随原包做版本更新,也不出现在原包分组里。
  JournalTemplate copyAsNew({String? name, String? originId}) =>
      JournalTemplate(
        id: newTemplateId(),
        name: name ?? this.name,
        title: title,
        content: content,
        tags: List.of(tags),
        canvas: canvas?.clone(),
        originId: originId,
      );
}

/// 内置模板清单（REQ-09.1 ≥4 套 + 调研二阶段「今日手账」+ 生活场景扩充）。
/// 每套均为整页版式：纸张 + 贴纸/胶带预设 + 文字占位 + 花样字体。
final builtinTemplates = [
  JournalTemplate(
    id: 'builtin-today',
    name: '今日手账',
    title: '',
    content: '',
    tags: const [],
    builtin: true,
    canvas: _todayCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-daily-review',
    name: '每日复盘',
    title: '每日复盘',
    content: '【今日亮点】\n\n\n【做得好的】\n\n\n【待改进】\n\n\n【明天想做的】\n',
    tags: const ['复盘'],
    builtin: true,
    canvas: _dailyReviewCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-reading-notes',
    name: '读书笔记',
    title: '《书名》读书笔记',
    content: '📖 书名：\n✍️ 作者：\n\n【摘录】\n\n\n【想法】\n\n\n【行动】\n',
    tags: const ['阅读'],
    builtin: true,
    canvas: _readingCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-travel',
    name: '旅行手账',
    title: '✈️ 旅行手账',
    content: '📍 地点：\n\n【好吃的好玩的】\n\n\n【心情】\n',
    tags: const ['旅行'],
    builtin: true,
    canvas: _travelCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-weekly',
    name: '周记',
    title: '周记',
    content: '【本周回顾】\n\n\n【本周心情】\n\n\n【下周计划】\n',
    tags: const ['周记'],
    builtin: true,
    canvas: _weeklyCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-gratitude',
    name: '感恩清单',
    title: '感恩清单',
    content: '今天值得感恩的三件小事：\n1. \n2. \n3. \n\n【想对自己说】\n',
    tags: const ['感恩'],
    builtin: true,
    canvas: _gratitudeCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-birthday',
    name: '生日纪念',
    title: '🎂 又长大一岁啦',
    content: '🎂 今天的主角：\n🎈 新的一岁，希望：\n\n【今天最开心的瞬间】\n\n\n【写给下一岁的自己】\n',
    tags: const ['生日', '纪念'],
    builtin: true,
    canvas: _birthdayCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-food-diary',
    name: '美食日记',
    title: '美食日记',
    content: '🍽 今天吃了：\n😋 味道打分：⭐️⭐️⭐️\n\n【最惊艳的一道】\n\n\n【店铺/做法记录】\n',
    tags: const ['美食'],
    builtin: true,
    canvas: _foodCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-movie',
    name: '观影手记',
    title: '🎬 观影手记',
    content: '🎞 片名：\n🎥 导演 / 年份：\n⭐️ 我的评分：☆☆☆☆☆\n\n【一句话剧情】\n\n\n【戳中我的台词】\n\n\n【散场后想说】\n',
    tags: const ['观影'],
    builtin: true,
    canvas: _movieCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-fitness',
    name: '运动打卡',
    title: '运动打卡 💪',
    content: '🏃 今日训练：\n⏱ 时长 / 强度：\n\n【身体的感觉】\n\n\n【给明天的小目标】\n',
    tags: const ['运动'],
    builtin: true,
    canvas: _fitnessCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-goodnight',
    name: '晚安日记',
    title: '🌙 晚安日记',
    content: '今天的三件小事：\n1. \n2. \n3. \n\n【此刻的心情】\n\n\n【明早醒来想做的一件小事】\n',
    tags: const ['晚安'],
    builtin: true,
    canvas: _goodnightCanvas(),
  ),
  JournalTemplate(
    id: 'builtin-weekend-plan',
    name: '周末计划',
    title: '周末计划',
    content: '□ 睡到自然醒\n□ 吃一顿好吃的\n□ 出门走走晒太阳\n□ 见想见的人\n□ 做一件喜欢的小事\n\n【本周末关键词】\n\n【下周也想…】\n',
    tags: const ['计划'],
    builtin: true,
    canvas: _weekendPlanCanvas(),
  ),
];

/// 生成不冲突的新模板 id。
String newTemplateId() => 'tpl-${makeId()}';

/// 内置模板 id 清单（NFR-08：一经发布不得重命名或删除,只能新增）。
final Set<String> builtinTemplateIds = {
  for (final t in builtinTemplates) t.id,
};

/// 该 id 是否属于本机内置模板。
/// `builtin` 标志的唯一可信来源——外部文件里的自称一律忽略（FIX-02）。
bool isBuiltinTemplateId(String id) => builtinTemplateIds.contains(id);

// ---------------------------------------------------------------------------
// 内置整页版式
// ---------------------------------------------------------------------------

const _kai = 'LXGW WenKai';
const _kuaiLe = 'ZCOOL KuaiLe';

/// 今日手账：日期/心情/天气组件 + 标题与正文占位（每日一问在套用时填入）。
JournalCanvas _todayCanvas() => JournalCanvas(
  paperId: 'mist',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.52, h: 0.12),
    StructuredElement(kind: ComponentKind.mood, x: 0.6, y: 0.05, w: 0.32, h: 0.14),
    StructuredElement(kind: ComponentKind.weather, x: 0.6, y: 0.19, w: 0.32, h: 0.1),
    StickerElement(key: 'vec:cloud', x: 0.46, y: 0.045, w: 0.13, h: 0.13),
    StickerElement(key: 'vec:star', x: 0.8, y: 0.2, w: 0.1, h: 0.1, rotation: 15),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.24,
      w: 0.84,
      text: '',
      fontScale: 0.05,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.36,
      w: 0.84,
      text: '',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 每日复盘：横线纸 + 星星贴纸 + 四节结构。
JournalCanvas _dailyReviewCanvas() => JournalCanvas(
  paperId: 'lines',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.mood, x: 0.62, y: 0.05, w: 0.3, h: 0.14),
    StickerElement(key: 'vec:star', x: 0.8, y: 0.2, w: 0.12, h: 0.12, rotation: 12),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.22,
      w: 0.84,
      text: '每日复盘',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.32,
      w: 0.84,
      text: '【今日亮点】\n\n\n【做得好的】\n\n\n【待改进】\n\n\n【明天想做的】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 读书笔记：书本贴纸 + 胶带 + 三节结构。
JournalCanvas _readingCanvas() => JournalCanvas(
  paperId: 'plain',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    TapeElement(x: 0.6, y: 0.03, w: 0.3, h: 0.075, rotation: -6, style: 'stripes', color: 0xFF8FC1E3),
    StickerElement(key: 'vec:book', x: 0.66, y: 0.14, w: 0.2, h: 0.2, rotation: 8),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.22,
      w: 0.84,
      text: '《书名》读书笔记',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.32,
      w: 0.84,
      text: '📖 书名：\n✍️ 作者：\n\n【摘录】\n\n\n【想法】\n\n\n【行动】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 旅行手账：波纹纸 + 两张拍立得占位 + 胶带。
JournalCanvas _travelCanvas() => JournalCanvas(
  paperId: 'waves',
  height: 1.45,
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.weather, x: 0.6, y: 0.06, w: 0.32, h: 0.1),
    StickerElement(key: 'vec:camera', x: 0.78, y: 0.02, w: 0.16, h: 0.16, rotation: 10),
    TapeElement(x: 0.05, y: 0.3, w: 0.28, h: 0.08, rotation: -35, style: 'dots', color: 0xFFF4A9A0),
    ImageElement(
      path: '',
      x: 0.12,
      y: 0.24,
      w: 0.4,
      h: 0.46,
      rotation: -3,
      mask: ImageMask.polaroid,
    ),
    ImageElement(
      path: '',
      x: 0.54,
      y: 0.32,
      w: 0.36,
      h: 0.42,
      rotation: 4,
      mask: ImageMask.polaroid,
    ),
    TapeElement(x: 0.62, y: 0.68, w: 0.28, h: 0.08, rotation: 30, style: 'stripes', color: 0xFFF6C94A),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.2,
      w: 0.5,
      h: 0.1,
      text: '✈️ 旅行手账',
      fontScale: 0.05,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.12,
      y: 0.8,
      w: 0.76,
      text: '📍 地点：\n\n【好吃的好玩的】\n\n\n【心情】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 周记：方格纸 + 小旗贴纸。
JournalCanvas _weeklyCanvas() => JournalCanvas(
  paperId: 'grid',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.mood, x: 0.62, y: 0.05, w: 0.3, h: 0.14),
    StickerElement(key: 'vec:flag', x: 0.72, y: 0.18, w: 0.2, h: 0.2, rotation: -6),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.22,
      w: 0.84,
      text: '周记',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.32,
      w: 0.84,
      text: '【本周回顾】\n\n\n【本周心情】\n\n\n【下周计划】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 感恩清单：樱粉纯色纸 + 爱心贴纸。
JournalCanvas _gratitudeCanvas() => JournalCanvas(
  paperId: 'sakura',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StickerElement(key: 'vec:heart', x: 0.06, y: 0.16, w: 0.14, h: 0.14, rotation: -12),
    StickerElement(key: 'vec:heart', x: 0.82, y: 0.12, w: 0.1, h: 0.1, rotation: 14),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.22,
      w: 0.84,
      text: '感恩清单',
      fontScale: 0.052,
      bold: true,
      fontFamily: 'Ma Shan Zheng',
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.32,
      w: 0.84,
      text: '今天值得感恩的三件小事：\n1. \n2. \n3. \n\n【想对自己说】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 生日纪念：落日渐变纸，居中标题两侧气球与礼物，
/// 爱心胶带封着两张拍立得照片位 —— 打开就是一张庆祝页。
JournalCanvas _birthdayCanvas() => JournalCanvas(
  paperId: 'sunset',
  height: 1.5,
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StickerElement(key: 'vec:balloon', x: 0.85, y: 0.02, w: 0.11, h: 0.14, rotation: 12),
    StickerElement(key: 'vec:balloon', x: 0.055, y: 0.165, w: 0.115, h: 0.145, rotation: -14),
    StickerElement(key: 'vec:gift', x: 0.835, y: 0.175, w: 0.11, h: 0.11, rotation: 10),
    TextElement(
      role: 'title',
      x: 0.15,
      y: 0.195,
      w: 0.7,
      text: '🎂 又长大一岁啦',
      fontScale: 0.054,
      align: 1,
      fontFamily: 'Ma Shan Zheng',
      lineHeight: 1.5,
    ),
    TapeElement(x: 0.395, y: 0.3, w: 0.23, h: 0.07, rotation: -4, style: 'hearts', color: 0xFFF4A9A0),
    ImageElement(path: '', x: 0.09, y: 0.345, w: 0.43, h: 0.46, rotation: -3, mask: ImageMask.polaroid),
    ImageElement(path: '', x: 0.555, y: 0.385, w: 0.36, h: 0.44, rotation: 4, mask: ImageMask.polaroid),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.9,
      w: 0.84,
      text: '🎂 今天的主角：\n🎈 新的一岁，希望：\n\n【今天最开心的瞬间】\n\n\n【写给下一岁的自己】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 美食日记：奶油黄纸，波点胶带把奶茶与甜甜圈贴在页角，
/// 圆形 + 拍立得两个照片位对应「摆盘照」与「探店照」。
JournalCanvas _foodCanvas() => JournalCanvas(
  paperId: 'butter',
  height: 1.42,
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.mood, x: 0.62, y: 0.05, w: 0.3, h: 0.14),
    TapeElement(x: 0.66, y: 0.155, w: 0.26, h: 0.07, rotation: -5, style: 'dots', color: 0xFFF2A65A),
    StickerElement(key: 'vec:boba', x: 0.79, y: 0.185, w: 0.13, h: 0.13, rotation: 8),
    StickerElement(key: 'vec:donut', x: 0.65, y: 0.2, w: 0.105, h: 0.105, rotation: -12),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.215,
      w: 0.84,
      text: '美食日记',
      fontScale: 0.054,
      fontFamily: _kuaiLe,
      lineHeight: 1.5,
    ),
    ImageElement(path: '', x: 0.09, y: 0.315, w: 0.34, h: 0.34, rotation: -2, mask: ImageMask.circle),
    ImageElement(path: '', x: 0.52, y: 0.3, w: 0.38, h: 0.46, rotation: 3, mask: ImageMask.polaroid),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.86,
      w: 0.84,
      text: '🍽 今天吃了：\n😋 味道打分：⭐️⭐️⭐️\n\n【最惊艳的一道】\n\n\n【店铺/做法记录】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 观影手记：星屑紫纸营造深夜影院感，月亮相伴、
/// 五颗空心星当评分栏，纯文字段落式排版。
JournalCanvas _movieCanvas() => JournalCanvas(
  paperId: 'stars',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    TapeElement(x: 0.58, y: 0.035, w: 0.28, h: 0.07, rotation: 6, style: 'stripes', color: 0xFFB8A4DB),
    StickerElement(key: 'vec:moon', x: 0.64, y: 0.155, w: 0.11, h: 0.11, rotation: -8),
    StickerElement(key: 'vec:star', x: 0.80, y: 0.145, w: 0.115, h: 0.115, rotation: 18),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.215,
      w: 0.84,
      text: '🎬 观影手记',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.325,
      w: 0.84,
      text: '🎞 片名：\n🎥 导演 / 年份：\n⭐️ 我的评分：☆☆☆☆☆\n\n【一句话剧情】\n\n\n【戳中我的台词】\n\n\n【散场后想说】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 运动打卡：薄荷绿纸，活动组件直接排在标题下
/// （勾过的活动进统计页），小旗标记今日目标。
JournalCanvas _fitnessCanvas() => JournalCanvas(
  paperId: 'mint',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.weather, x: 0.62, y: 0.05, w: 0.3, h: 0.1),
    StickerElement(key: 'vec:flag', x: 0.82, y: 0.155, w: 0.13, h: 0.13, rotation: 8),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.205,
      w: 0.84,
      text: '运动打卡 💪',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    StructuredElement(kind: ComponentKind.activities, x: 0.08, y: 0.31, w: 0.84, h: 0.13),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.47,
      w: 0.84,
      text: '🏃 今日训练：\n⏱ 时长 / 强度：\n\n【身体的感觉】\n\n\n【给明天的小目标】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 晚安日记：海空渐变纸，月亮与小星散布右上角，
/// 波浪蓝胶带压住标题上沿 —— 一页安安静静的睡前仪式。
JournalCanvas _goodnightCanvas() => JournalCanvas(
  paperId: 'ocean',
  height: 1.4,
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StickerElement(key: 'vec:star', x: 0.68, y: 0.045, w: 0.07, h: 0.07, rotation: 10),
    StickerElement(key: 'vec:moon', x: 0.80, y: 0.03, w: 0.13, h: 0.13, rotation: -10),
    StickerElement(key: 'vec:star', x: 0.90, y: 0.15, w: 0.06, h: 0.06, rotation: 20),
    TapeElement(x: 0.05, y: 0.165, w: 0.24, h: 0.07, rotation: -5, style: 'waves', color: 0xFF8FC1E3),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.235,
      w: 0.84,
      text: '🌙 晚安日记',
      fontScale: 0.052,
      bold: true,
      fontFamily: _kai,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.35,
      w: 0.84,
      text: '今天的三件小事：\n1. \n2. \n3. \n\n【此刻的心情】\n\n\n【明早醒来想做的一件小事】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);

/// 周末计划：春野渐变纸，帐篷与纸飞机预告出门的好心情，
/// 快乐体标题配勾选清单，逐条打勾即成稿。
JournalCanvas _weekendPlanCanvas() => JournalCanvas(
  paperId: 'spring',
  elements: [
    StructuredElement(kind: ComponentKind.date, x: 0.08, y: 0.06, w: 0.5, h: 0.12),
    StructuredElement(kind: ComponentKind.weather, x: 0.62, y: 0.05, w: 0.3, h: 0.1),
    StickerElement(key: 'vec:tent', x: 0.655, y: 0.17, w: 0.12, h: 0.12, rotation: -8),
    StickerElement(key: 'vec:paperplane', x: 0.82, y: 0.165, w: 0.13, h: 0.13, rotation: 12),
    TextElement(
      role: 'title',
      x: 0.08,
      y: 0.215,
      w: 0.84,
      text: '周末计划',
      fontScale: 0.054,
      fontFamily: _kuaiLe,
      lineHeight: 1.5,
    ),
    TextElement(
      role: 'body',
      x: 0.08,
      y: 0.325,
      w: 0.84,
      text: '□ 睡到自然醒\n□ 吃一顿好吃的\n□ 出门走走晒太阳\n□ 见想见的人\n□ 做一件喜欢的小事\n\n【本周末关键词】\n\n【下周也想…】\n',
      fontScale: 0.038,
      fontFamily: _kai,
    ),
  ],
);
