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

  /// 最近一次套用时间（REQ-18.4 排序用）；null 为从未使用。
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

/// 内置模板清单（REQ-09.1 ≥4 套 + 调研二阶段「今日手账」）。
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
