import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/utils/search_filter.dart';

JournalEntry _e(String id,
    {String date = '2026-08-10',
    String title = '',
    String content = '',
    Mood? mood,
    Weather? weather,
    List<String> tags = const [],
    List<String> images = const [],
    bool favorite = false}) {
  final now = DateTime(2026, 8, 16);
  return JournalEntry(
    id: id,
    date: date,
    title: title,
    content: content,
    mood: mood,
    weather: weather,
    tags: tags,
    images: images,
    isFavorite: favorite,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final entries = [
    _e('1',
        title: '晨跑五公里',
        content: '空气很好',
        mood: Mood.happy,
        weather: Weather.sunny,
        tags: ['运动'],
        images: ['/tmp/run.jpg']),
    _e('2',
        title: '读书笔记',
        content: '第一章读后感',
        mood: Mood.calm,
        weather: Weather.lightRain,
        tags: ['阅读', '日常'],
        favorite: true),
    _e('3',
        title: '雨天心情',
        content: '有点低落',
        mood: Mood.sad,
        weather: Weather.lightRain,
        date: '2026-08-14',
        tags: ['情绪']),
    _e('4',
        title: '上周的工作',
        content: '忙碌',
        date: '2026-08-03',
        mood: Mood.tired),
  ];

  test('仅用筛选条件、无关键词也能检索（REQ-06.4）', () {
    final filters = SearchFilters()..moods.add(Mood.happy);
    final result = filterEntries(entries, '', filters);
    expect(result.map((e) => e.id), ['1']);
  });

  test('关键词与筛选条件任意组合（REQ-06.2）', () {
    final filters = SearchFilters()..weathers.add(Weather.lightRain);
    // 关键词「读」+ 天气小雨 → 命中 2。
    expect(filterEntries(entries, '读', filters).map((e) => e.id), ['2']);
    // 心情 + 标签为 AND 组合：需同时满足。
    final f2 = SearchFilters()
      ..moods.addAll([Mood.sad, Mood.tired])
      ..tags.addAll(['情绪']);
    expect(filterEntries(entries, '', f2).map((e) => e.id), ['3'],
        reason: '条目 4 心情匹配但无标签，被标签条件排除');
    // 心情多选：sad 或 tired 均可命中。
    final f3 = SearchFilters()..moods.addAll([Mood.sad, Mood.tired]);
    expect(filterEntries(entries, '', f3).map((e) => e.id), ['3', '4']);
  });

  test('日期区间、只看收藏、只看有图', () {
    final range = SearchFilters()
      ..startDate = '2026-08-09'
      ..endDate = '2026-08-14';
    expect(filterEntries(entries, '', range).map((e) => e.id), ['1', '2', '3']);

    final fav = SearchFilters()..favoritesOnly = true;
    expect(filterEntries(entries, '', fav).map((e) => e.id), ['2']);

    final withImg = SearchFilters()..withImagesOnly = true;
    expect(filterEntries(entries, '', withImg).map((e) => e.id), ['1']);
  });

  test('无任何条件时不过滤', () {
    expect(filterEntries(entries, '', SearchFilters()).length, 4);
    expect(SearchFilters().isEmpty, isTrue);
    expect(
        (SearchFilters()..favoritesOnly = true).isEmpty, isFalse);
  });

  test('关键词大小写不敏感，覆盖标题/正文/标签', () {
    final list = [
      _e('a', title: 'Hello'),
      _e('b', content: 'world'),
      _e('c', tags: ['Flutter']),
    ];
    expect(filterEntries(list, 'hello', SearchFilters()).map((e) => e.id),
        ['a']);
    expect(filterEntries(list, 'WORLD', SearchFilters()).map((e) => e.id),
        ['b']);
    expect(filterEntries(list, 'flutter', SearchFilters()).map((e) => e.id),
        ['c']);
  });
}
