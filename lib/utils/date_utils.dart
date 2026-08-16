import 'package:intl/intl.dart';

/// 日期格式化工具。
class DateUtils2 {
  DateUtils2._();

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseKey(String key) => DateTime.parse(key);

  /// 「今天」「昨天」或「M月d日 · 周X」，跨年附加年份。
  static String friendlyDate(String key) {
    final d = parseKey(key);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    final base = '${d.month}月${d.day}日 · 周${_weekdays[d.weekday - 1]}';
    return d.year == now.year ? base : '${d.year}年$base';
  }

  static String weekdayOf(String key) {
    final d = parseKey(key);
    return '周${_weekdays[d.weekday - 1]}';
  }

  static String monthDay(String key) {
    final d = parseKey(key);
    return '${d.month}/${d.day}';
  }

  static String fullDate(String key) {
    final d = parseKey(key);
    return '${d.year}年${d.month}月${d.day}日 · 周${_weekdays[d.weekday - 1]}';
  }

  static String monthTitle(DateTime d) => '${d.year}年${d.month}月';

  static String ym(DateTime d) => DateFormat('yyyy-MM').format(d);

  static int daysInMonth(DateTime d) {
    final next = d.month == 12
        ? DateTime(d.year + 1, 1, 1)
        : DateTime(d.year, d.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }
}
