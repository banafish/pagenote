import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../services/backup_service.dart';
import '../utils/attachments.dart';
import '../utils/date_utils.dart';

/// 单日心情均分点（心情趋势，REQ-05）。
class DailyMood {
  const DailyMood(this.date, this.score);
  final String date;
  final double score;
}

/// 月度报告（REQ-10）。
class MonthlyReport {
  MonthlyReport({
    required this.year,
    required this.month,
    required this.count,
    required this.words,
    this.avgMood,
    required this.topTags,
    this.busiestWeekday,
    required this.prevCount,
  });

  final int year;
  final int month;
  final int count;
  final int words;
  final double? avgMood;
  final List<MapEntry<String, int>> topTags;

  /// 最常记录的星期（1–7，无数据为 null）。
  final int? busiestWeekday;
  final int prevCount;

  int get delta => count - prevCount;
  bool get hasData => count > 0;
}

/// 手账数据仓库：维护全部条目并派生标签与统计数据。
class JournalProvider extends ChangeNotifier {
  JournalProvider({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  /// 回收站保留天数（REQ-02.4）。
  static const trashRetentionDays = 30;

  List<JournalEntry> _backing = [];
  List<JournalEntry> _trashedBacking = [];
  bool loaded = false;

  /// 全部有效条目（不含回收站），按日期倒序。
  List<JournalEntry> get entries => List.unmodifiable(_backing);

  /// 回收站条目，按删除时间倒序。
  List<JournalEntry> get trashedEntries => List.unmodifiable(_trashedBacking);

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
  int get todayCount =>
      entries.where((e) => e.date == DateUtils2.dateKey(DateTime.now())).length;

  /// 连续记录天数（自今天或昨天向前数）。
  /// 可传入参考时间，供 WidgetContent 等需要确定性结果的场景使用。
  int streakDays([DateTime? now]) {
    if (entries.isEmpty) return 0;
    final dates = entries.map((e) => e.date).toSet();
    var day = now ?? DateTime.now();
    if (!dates.contains(DateUtils2.dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!dates.contains(DateUtils2.dateKey(day))) return 0;
    }
    var streak = 0;
    while (dates.contains(DateUtils2.dateKey(day))) {
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
      counts[i] = dates.where((d) => d == DateUtils2.dateKey(day)).length;
    }
    return counts;
  }

  /// 累计字数（按汉字/字母估算）。
  int get totalWords => entries.fold(
    0,
    (sum, e) => sum + e.plainContent.replaceAll(RegExp(r'\s'), '').length,
  );

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

  /// 那年今天（REQ-01）：去年及以前同月同日写过的手账，按年份分组（新→旧）。
  /// 当天补写的条目不属于历史，不会出现。
  Map<int, List<JournalEntry>> onThisDay([DateTime? now]) {
    final n = now ?? DateTime.now();
    final md =
        '${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    final map = <int, List<JournalEntry>>{};
    for (final e in entries) {
      if (e.date.length != 10) continue;
      final year = int.tryParse(e.date.substring(0, 4));
      if (year == null || year >= n.year) continue;
      if (e.date.substring(5) != md) continue;
      map.putIfAbsent(year, () => []).add(e);
    }
    final years = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final y in years) y: map[y]!};
  }

  /// 近 [days] 天每日心情均分（旧→新），仅含有心情记录的日期（REQ-05.1）。
  List<DailyMood> moodAverages(int days, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final first = today.subtract(Duration(days: days - 1));
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final e in entries) {
      final m = e.mood;
      if (m == null) continue;
      final day = DateUtils2.parseKey(e.date);
      if (day.isBefore(first) || day.isAfter(today)) continue;
      sums[e.date] = (sums[e.date] ?? 0) + m.score;
      counts[e.date] = (counts[e.date] ?? 0) + 1;
    }
    final result = <DailyMood>[];
    for (var i = days - 1; i >= 0; i--) {
      final key = DateUtils2.dateKey(today.subtract(Duration(days: i)));
      if (sums.containsKey(key)) {
        result.add(DailyMood(key, sums[key]! / counts[key]!));
      }
    }
    return result;
  }

  /// 活动出现次数（REQ-12.3 活动频率排行）。
  Map<String, int> get activityCounts {
    final counts = <String, int>{};
    for (final e in entries) {
      for (final a in e.activities) {
        counts[a] = (counts[a] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 各活动的平均心情分（做什么的时候心情最好，REQ-12.3）。
  Map<String, double> activityMoodScores() {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final e in entries) {
      final m = e.mood;
      if (m == null) continue;
      for (final a in e.activities) {
        sums[a] = (sums[a] ?? 0) + m.score;
        counts[a] = (counts[a] ?? 0) + 1;
      }
    }
    return {for (final a in counts.keys) a: sums[a]! / counts[a]!};
  }

  /// 月度报告（REQ-10.1）：篇数、总字数、心情均值、高频标签 TOP5、
  /// 最常记录的星期与对比上月增减。
  MonthlyReport monthlyReport(int year, int month) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    final monthEntries = entries
        .where((e) => e.date.startsWith(prefix))
        .toList();

    var words = 0;
    final moodScores = <double>[];
    final weekdayCounts = List<int>.filled(7, 0);
    final tagCounts = <String, int>{};
    for (final e in monthEntries) {
      words += e.plainContent.replaceAll(RegExp(r'\s'), '').length;
      if (e.mood != null) moodScores.add(e.mood!.score.toDouble());
      weekdayCounts[DateUtils2.parseKey(e.date).weekday - 1]++;
      for (final t in e.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }

    final tags = tagCounts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });

    int? busiestDay;
    var maxCount = 0;
    for (var i = 0; i < 7; i++) {
      if (weekdayCounts[i] > maxCount) {
        maxCount = weekdayCounts[i];
        busiestDay = i + 1;
      }
    }

    final prev = month == 1
        ? DateTime(year - 1, 12, 1)
        : DateTime(year, month - 1, 1);
    final prevPrefix = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
    final prevCount = entries
        .where((e) => e.date.startsWith(prevPrefix))
        .length;

    return MonthlyReport(
      year: year,
      month: month,
      count: monthEntries.length,
      words: words,
      avgMood: moodScores.isEmpty
          ? null
          : moodScores.reduce((a, b) => a + b) / moodScores.length,
      topTags: tags.take(5).toList(),
      busiestWeekday: maxCount > 0 ? busiestDay : null,
      prevCount: prevCount,
    );
  }

  Future<void> load() async {
    await purgeExpiredTrash();
    _backing = await _db.getAllEntries();
    _trashedBacking = await _db.getTrashedEntries();
    loaded = true;
    notifyListeners();
  }

  Future<void> saveEntry(JournalEntry entry) async {
    if (_backing.any((e) => e.id == entry.id) ||
        _trashedBacking.any((e) => e.id == entry.id)) {
      await _db.updateEntry(entry);
    } else {
      await _db.insertEntry(entry);
    }
    await load();
  }

  Future<void> toggleFavorite(String id) async {
    final entry = _backing.firstWhere((e) => e.id == id);
    entry.isFavorite = !entry.isFavorite;
    entry.updatedAt = DateTime.now();
    await _db.updateEntry(entry);
    notifyListeners();
  }

  /// 软删除：移入回收站并打上删除时间（REQ-02）。
  Future<void> softDelete(String id) async {
    final entry = _backing.firstWhere((e) => e.id == id);
    entry.deletedAt = DateTime.now();
    await _db.updateEntry(entry);
    _backing.removeWhere((e) => e.id == id);
    _trashedBacking.insert(0, entry);
    notifyListeners();
  }

  /// 恢复回收站条目。
  Future<void> restoreEntry(String id) async {
    final entry = _trashedBacking.firstWhere((e) => e.id == id);
    entry.deletedAt = null;
    entry.updatedAt = DateTime.now();
    await _db.updateEntry(entry);
    _trashedBacking.removeWhere((e) => e.id == id);
    await load();
  }

  /// 彻底删除单条（连同附件图片文件）。
  Future<void> permanentDelete(String id) async {
    final entry = _trashedBacking
        .where((e) => e.id == id)
        .firstOrNull; // 可能是有效条目被直接清理
    await _db.deleteEntry(id);
    _backing.removeWhere((e) => e.id == id);
    _trashedBacking.removeWhere((e) => e.id == id);
    if (entry != null) await _deleteAttachmentsOf(entry);
    notifyListeners();
  }

  /// 一键清空回收站（连同附件图片文件）。
  Future<void> emptyTrash() async {
    final toRemove = List<JournalEntry>.from(_trashedBacking);
    await _db.deleteAllTrashed();
    _trashedBacking.clear();
    for (final e in toRemove) {
      await _deleteAttachmentsOf(e);
    }
    notifyListeners();
  }

  /// 清理超期回收站条目（REQ-02.4：保留 30 天，启动时自动执行）。
  Future<void> purgeExpiredTrash({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final deadline = n.subtract(const Duration(days: trashRetentionDays));
    final expired = (await _db.getTrashedEntries())
        .where((e) => e.deletedAt != null && e.deletedAt!.isBefore(deadline))
        .toList();
    for (final e in expired) {
      await _db.deleteEntry(e.id);
      await _deleteAttachmentsOf(e);
    }
    if (expired.isNotEmpty && loaded) {
      _trashedBacking.removeWhere((e) => expired.any((x) => x.id == e.id));
      notifyListeners();
    }
  }

  Future<void> _deleteAttachmentsOf(JournalEntry entry) async {
    for (final path in entry.images) {
      await Attachments.delete(path);
    }
  }

  /// 导入备份（REQ-03.2）。合并模式按 id 去重、`updatedAt` 新者胜；
  /// 覆盖模式先清空全部条目与附件再导入。返回导入或更新的条目数。
  Future<int> importBackup(BackupData data, {required bool overwrite}) async {
    if (overwrite) {
      for (final e in [..._backing, ..._trashedBacking]) {
        await _deleteAttachmentsOf(e);
      }
      await _db.deleteAllEntries();
    }

    var changed = 0;
    for (final incoming in data.entries) {
      final mapped = incoming.copy();
      final newPaths = <String>[];
      final nameToNewPath = <String, String>{};
      for (final name in mapped.images) {
        final bytes = data.attachments[name];
        if (bytes != null) {
          final newPath = await Attachments.persistBytes(
            bytes,
            p.extension(name),
          );
          newPaths.add(newPath);
          nameToNewPath[name] = newPath;
        }
      }
      mapped.images = newPaths;
      // 画布上的照片元素路径按文件名同步重映射（跨设备附件路径不同）。
      mapped.canvas?.remapImagePaths((path) {
        final mapped2 = nameToNewPath[p.basename(path)];
        return mapped2 ?? path;
      });

      if (!overwrite) {
        final existing = [
          ..._backing,
          ..._trashedBacking,
        ].where((e) => e.id == mapped.id).firstOrNull;
        if (existing != null && !mapped.updatedAt.isAfter(existing.updatedAt)) {
          continue; // 本地较新，保留本地版本
        }
      }
      changed++;
      await _db.insertEntry(mapped);
    }
    await load();
    return changed;
  }

  Future<List<JournalEntry>> search(String query) => _db.search(query);

  /// 生成不冲突的新条目 id。
  static String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xffffff);
    return '$ts-${rand.toRadixString(16).padLeft(6, '0')}';
  }
}
