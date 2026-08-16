import '../utils/journal_id.dart';

/// 手账模板（REQ-09）：预设标题、分节结构与标签。
class JournalTemplate {
  JournalTemplate({
    required this.id,
    required this.name,
    this.title = '',
    this.content = '',
    List<String>? tags,
    this.builtin = false,
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

  /// 内置模板不可删除。
  final bool builtin;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'title': title,
    'content': content,
    'tags': tags.join('\u001F'),
    'builtin': builtin ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static JournalTemplate fromMap(Map<String, Object?> map) => JournalTemplate(
    id: map['id']! as String,
    name: map['name']! as String,
    title: (map['title'] ?? '') as String,
    content: (map['content'] ?? '') as String,
    tags: (map['tags'] == null || (map['tags'] as String).isEmpty)
        ? []
        : (map['tags'] as String).split('\u001F'),
    builtin: (map['builtin'] ?? 0) as int == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']! as int),
  );

  JournalTemplate copy() => JournalTemplate.fromMap(toMap());
}

/// 内置模板清单（REQ-09.1：≥4 套）。
final builtinTemplates = [
  JournalTemplate(
    id: 'builtin-daily-review',
    name: '每日复盘',
    title: '',
    content: '【今日亮点】\n\n\n【做得好的】\n\n\n【待改进】\n\n\n【明天想做的】\n',
    tags: ['复盘'],
    builtin: true,
  ),
  JournalTemplate(
    id: 'builtin-reading-notes',
    name: '读书笔记',
    title: '《书名》读书笔记',
    content: '📖 书名：\n✍️ 作者：\n\n【摘录】\n\n\n【想法】\n\n\n【行动】\n',
    tags: ['阅读'],
    builtin: true,
  ),
  JournalTemplate(
    id: 'builtin-travel',
    name: '旅行手账',
    title: '',
    content: '📍 地点：\n🌤️ 天气：\n\n【行程】\n\n\n【好吃的好玩的】\n\n\n【心情】\n',
    tags: ['旅行'],
    builtin: true,
  ),
  JournalTemplate(
    id: 'builtin-weekly',
    name: '周记',
    title: '',
    content: '【本周回顾】\n\n\n【本周心情】\n\n\n【下周计划】\n',
    tags: ['周记'],
    builtin: true,
  ),
  JournalTemplate(
    id: 'builtin-gratitude',
    name: '感恩清单',
    title: '',
    content: '今天值得感恩的三件小事：\n1. \n2. \n3. \n\n【想对自己说】\n',
    tags: ['感恩'],
    builtin: true,
  ),
];

/// 生成不冲突的新模板 id。
String newTemplateId() => 'tpl-${makeId()}';
