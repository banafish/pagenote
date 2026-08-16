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
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  })  : tags = tags ?? [],
        images = images ?? [];

  final String id;

  /// 手账所属日期，格式 yyyy-MM-dd。
  String date;
  String title;
  String content;
  Mood? mood;
  Weather? weather;
  List<String> tags;
  List<String> images;
  bool isFavorite;
  final DateTime createdAt;
  DateTime updatedAt;

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
        'isFavorite': isFavorite ? 1 : 0,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
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
        isFavorite: (map['isFavorite'] ?? 0) as int == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['createdAt']! as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updatedAt']! as int),
      );

  static List<String> _splitField(Object? value) {
    if (value == null || (value as String).isEmpty) return [];
    return value.split('\u001F');
  }

  JournalEntry copy() => JournalEntry.fromMap(toMap());
}
