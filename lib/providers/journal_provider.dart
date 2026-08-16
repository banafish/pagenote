import 'dart:math';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';

/// 手账数据仓库：维护全部条目并派生标签与统计数据。
class JournalProvider extends ChangeNotifier {
  JournalProvider({AppDatabase? database}) : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  List<JournalEntry> _backing = [];
  bool loaded = false;

  /// 全部条目，按日期倒序。
  List<JournalEntry> get entries => List.unmodifiable(_backing);

  /// 全部标签（按使用次数降序）。
  List<String> get allTags {
    final counts = <String, int>{};
    for (final e in entries) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList();
    tags.sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return tags;
  }

  int get totalCount => entries.length;

  /// 今日条数。
  int get todayCount => entries
      .where((e) => e.date == _dateKey(DateTime.now()))
      .length;

  /// 连续记录天数（自今天或昨天向前数）。
  int get streakDays {
    if (entries.isEmpty) return 0;
    final dates = entries.map((e) => e.date).toSet();
    var day = DateTime.now();
    if (!dates.contains(_dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!dates.contains(_dateKey(day))) return 0;
    }
    var streak = 0;
    while (dates.contains(_dateKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 本月条数。
  int get monthCount {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return entries.where((e) => e.date.startsWith(prefix)).length;
  }

  /// 心情分布。
  Map<Mood, int> get moodCounts {
    final counts = <Mood, int>{};
    for (final e in entries) {
      final m = e.mood;
      if (m != null) counts[m] = (counts[m] ?? 0) + 1;
    }
    return counts;
  }

  /// 最近 7 天每天的条数（含今天，顺序为旧→新）。
  List<int> get lastWeekCounts {
    final counts = List<int>.filled(7, 0);
    final dates = entries.map((e) => e.date).toList();
    for (var i = 0; i < 7; i++) {
      final day = DateTime.now().subtract(Duration(days: 6 - i));
      counts[i] = dates.where((d) => d == _dateKey(day)).length;
    }
    return counts;
  }

  /// 累计字数（按汉字/字母估算）。
  int get totalWords =>
      entries.fold(0, (sum, e) => sum + e.plainContent.replaceAll(RegExp(r'\s'), '').length);

  /// 心情最常出现的情绪，无记录时返回 null。
  Mood? get dominantMood {
    final counts = moodCounts;
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }

  Future<void> load() async {
    _backing = await _db.getAllEntries();
    loaded = true;
    notifyListeners();
  }

  Future<void> saveEntry(JournalEntry entry) async {
    if (entries.any((e) => e.id == entry.id)) {
      await _db.updateEntry(entry);
    } else {
      await _db.insertEntry(entry);
    }
    await load();
  }

  Future<void> toggleFavorite(String id) async {
    final entry = entries.firstWhere((e) => e.id == id);
    entry.isFavorite = !entry.isFavorite;
    entry.updatedAt = DateTime.now();
    await _db.updateEntry(entry);
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    await _db.deleteEntry(id);
    _backing.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  Future<List<JournalEntry>> search(String query) => _db.search(query);

  /// 生成不冲突的新条目 id。
  static String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xffffff);
    return '$ts-${rand.toRadixString(16).padLeft(6, '0')}';
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
