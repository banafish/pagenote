import 'canvas_page.dart';
import 'decoration.dart';
import 'mood.dart';

/// 手账条目：一条手账记录。
class JournalEntry {
  JournalEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.content,
    this.mood,
    this.weather,
    List<String>? tags,
    List<String>? images,
    List<String>? activities,
    this.paper = '',
    List<Sticker>? stickers,
    this.canvas,
    this.isQuickNote = false,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : tags = tags ?? [],
       images = images ?? [],
       activities = activities ?? [],
       stickers = stickers ?? [];

  final String id;

  /// 手账所属日期，格式 yyyy-MM-dd。
  String date;
  String title;
  String content;
  Mood? mood;
  Weather? weather;
  List<String> tags;
  List<String> images;

  /// 当日活动名称列表（如运动、阅读），见 models/activity.dart。
  List<String> activities;

  /// 纸张样式 id（REQ-13），空串表示不装饰。
  String paper;

  /// 页面贴纸（REQ-13），见 models/decoration.dart。
  List<Sticker> stickers;

  /// 画布版面（元素树，REQ-13 完整版）：背景 + 元素列表。
  /// 保存过画布编辑后即为版面事实源；旧数据为 null,展示前用
  /// [synthesizeCanvas] 自动生成等价元素。
  JournalCanvas? canvas;

  /// 快速速记标记（REQ-16）：true 表示尚未整理的速记。
  bool isQuickNote;
  bool isFavorite;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 软删除时间（回收站，REQ-02）；null 表示未删除。
  DateTime? deletedAt;

  /// 正文纯文本摘要（去除空白换行）。
  String get plainContent => content.trim();

  Map<String, Object?> toMap() => {
    'id': id,
    'date': date,
    'title': title,
    'content': content,
    'mood': mood?.id,
    'weather': weather?.id,
    'tags': tags.join('\u001F'),
    'images': images.join('\u001F'),
    'activities': activities.join('\u001F'),
    'paper': paper,
    'stickers': encodeStickers(stickers),
    'canvas': encodeCanvas(canvas),
    'isQuickNote': isQuickNote ? 1 : 0,
    'isFavorite': isFavorite ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'deletedAt': deletedAt?.millisecondsSinceEpoch,
  };

  static JournalEntry fromMap(Map<String, Object?> map) => JournalEntry(
    id: map['id']! as String,
    date: map['date']! as String,
    title: (map['title'] ?? '') as String,
    content: (map['content'] ?? '') as String,
    mood: map['mood'] == null ? null : Mood.fromId(map['mood'] as String),
    weather: map['weather'] == null
        ? null
        : Weather.fromId(map['weather'] as String),
    tags: _splitField(map['tags']),
    images: _splitField(map['images']),
    activities: _splitField(map['activities']),
    paper: (map['paper'] ?? '') as String,
    stickers: decodeStickers((map['stickers'] ?? '') as String),
    canvas: decodeCanvas((map['canvas'] ?? '') as String),
    isQuickNote: (map['isQuickNote'] ?? 0) as int == 1,
    isFavorite: (map['isFavorite'] ?? 0) as int == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']! as int),
    deletedAt: map['deletedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['deletedAt']! as int),
  );

  static List<String> _splitField(Object? value) {
    if (value == null || (value as String).isEmpty) return [];
    return value.split('\u001F');
  }

  JournalEntry copy() => JournalEntry.fromMap(toMap());
}
