import '../models/journal_entry.dart';
import '../models/mood.dart';

/// 搜索筛选条件（REQ-06）：心情/天气/标签多选、日期区间、
/// 只看收藏、只看有图，可与关键词任意组合。
class SearchFilters {
  SearchFilters();

  final Set<Mood> moods = {};
  final Set<Weather> weathers = {};
  final Set<String> tags = {};

  /// 日期区间（yyyy-MM-dd，含端点；null 表示不限）。
  String? startDate;
  String? endDate;
  bool favoritesOnly = false;
  bool withImagesOnly = false;

  bool get isEmpty =>
      moods.isEmpty &&
      weathers.isEmpty &&
      tags.isEmpty &&
      startDate == null &&
      endDate == null &&
      !favoritesOnly &&
      !withImagesOnly;

  bool matches(JournalEntry e) {
    if (moods.isNotEmpty && (e.mood == null || !moods.contains(e.mood))) {
      return false;
    }
    if (weathers.isNotEmpty &&
        (e.weather == null || !weathers.contains(e.weather))) {
      return false;
    }
    if (tags.isNotEmpty && !tags.any(e.tags.contains)) {
      return false;
    }
    if (startDate != null && e.date.compareTo(startDate!) < 0) return false;
    if (endDate != null && e.date.compareTo(endDate!) > 0) return false;
    if (favoritesOnly && !e.isFavorite) return false;
    if (withImagesOnly && e.images.isEmpty) return false;
    return true;
  }

  SearchFilters clone() {
    final copy = SearchFilters()
      ..startDate = startDate
      ..endDate = endDate
      ..favoritesOnly = favoritesOnly
      ..withImagesOnly = withImagesOnly;
    copy.moods.addAll(moods);
    copy.weathers.addAll(weathers);
    copy.tags.addAll(tags);
    return copy;
  }
}

/// 组合筛选：关键词（标题/正文/标签，任意命中）+ 结构化筛选条件。
/// 关键词为空、仅用筛选条件时同样生效（REQ-06.4）。
List<JournalEntry> filterEntries(
  List<JournalEntry> entries,
  String query,
  SearchFilters filters,
) {
  final q = query.trim().toLowerCase();
  return entries.where((e) {
    if (q.isNotEmpty) {
      final title = e.title.toLowerCase();
      final content = e.content.toLowerCase();
      final tags = e.tags.map((t) => t.toLowerCase()).toList();
      if (!title.contains(q) &&
          !content.contains(q) &&
          !tags.any((t) => t.contains(q))) {
        return false;
      }
    }
    return filters.matches(e);
  }).toList();
}
