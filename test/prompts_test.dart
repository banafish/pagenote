import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagenote/data/prompts.dart';
import 'package:pagenote/providers/settings_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('问题库 ≥100 条且无重复（REQ-04.1）', () {
    expect(promptLibrary.length, greaterThanOrEqualTo(100));
    expect(promptLibrary.toSet().length, promptLibrary.length);
    for (final p in promptLibrary) {
      expect(p.trim(), isNotEmpty);
      expect(
        p.endsWith('？') || p.endsWith('。'),
        isTrue,
        reason: '问题应以中文标点收尾: $p',
      );
    }
  });

  test('同一天内问题确定不变，跨天分布均匀（REQ-04.1）', () {
    final a1 = promptForDate('2026-08-16');
    final a2 = promptForDate('2026-08-16');
    expect(a1, a2);

    // 覆盖一整年：绝大多数问题都会被用到（均匀哈希），
    // 且单条问题一年内平均出现 365/108 ≈ 3.4 次，放宽容忍到 10。
    final year = List.generate(
      365,
      (i) => promptForDate(_key(DateTime(2026, 1, 1).add(Duration(days: i)))),
    );
    final counts = <String, int>{};
    for (final p in year) {
      counts[p] = (counts[p] ?? 0) + 1;
    }
    expect(
      counts.length,
      greaterThan(promptLibrary.length * 0.85),
      reason: '一年内应覆盖 85% 以上的问题库',
    );
    expect(
      counts.values.reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(10),
      reason: '单条问题一年出现次数不应过度集中',
    );
  });

  test('换一条每日限 3 次，当日偏移稳定（REQ-04.2）', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    const today = '2026-08-16';

    final base = promptForDate(today);
    expect(settings.promptRefreshUsedToday(today), 0);

    expect(await settings.usePromptRefresh(today), true);
    expect(await settings.usePromptRefresh(today), true);
    expect(await settings.usePromptRefresh(today), true);
    expect(
      await settings.usePromptRefresh(today),
      isFalse,
      reason: '第 4 次换一条应被拒绝',
    );

    final after3 = promptForDate(today, settings.promptOffsetFor(today));
    expect(after3, isNot(equals(base)));
    // 重开 app（重新读取 prefs）后展示内容不变。
    final settings2 = SettingsProvider(await SharedPreferences.getInstance());
    expect(
      promptForDate(today, settings2.promptOffsetFor(today)),
      equals(after3),
    );
    expect(settings2.promptRefreshUsedToday(today), 3);
  });
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
