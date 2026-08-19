import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/providers/settings_provider.dart';

/// 素材面板：最近使用 / 收藏 / 搜索 / emoji 全集（REQ-17）与贴纸换色（REQ-19）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SettingsProvider> newSettings() async =>
      SettingsProvider(await SharedPreferences.getInstance());

  /// 把贴纸画到离屏位图，取原始 RGBA 字节。
  Future<Uint8List> renderSticker(String id, {int? tint, int px = 96}) async {
    final recorder = ui.PictureRecorder();
    StickerPainter(
      id,
      tint: tint,
    ).paint(ui.Canvas(recorder), ui.Size(px.toDouble(), px.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(px, px);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// 把位图里所有不透明像素压成单一颜色，作为「整体单色填充」的参照。
  Uint8List flattenToColor(Uint8List rgba, int argb) {
    final out = Uint8List.fromList(rgba);
    for (var i = 0; i < out.length; i += 4) {
      if (out[i + 3] == 0) continue;
      out[i] = (argb >> 16) & 0xFF;
      out[i + 1] = (argb >> 8) & 0xFF;
      out[i + 2] = argb & 0xFF;
    }
    return out;
  }

  /// 统计接近某颜色的像素数（容差内），用于判断轮廓墨色是否留存。
  int countNear(Uint8List rgba, int argb, {int tolerance = 20}) {
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    var n = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i + 3] < 200) continue;
      if ((rgba[i] - r).abs() <= tolerance &&
          (rgba[i + 1] - g).abs() <= tolerance &&
          (rgba[i + 2] - b).abs() <= tolerance) {
        n++;
      }
    }
    return n;
  }

  group('最近使用素材（REQ-17.1）', () {
    test('新用素材置顶、重复使用不产生第二条', () async {
      final settings = await newSettings();
      expect(settings.recentStickerKeys, isEmpty);

      await settings.pushRecentSticker('vec:flower');
      await settings.pushRecentSticker('emoji:🌸');
      expect(settings.recentStickerKeys, ['emoji:🌸', 'vec:flower']);

      await settings.pushRecentSticker('vec:flower');
      expect(settings.recentStickerKeys, [
        'vec:flower',
        'emoji:🌸',
      ], reason: '再次使用只调整顺序，不新增重复项');

      await settings.pushRecentSticker('');
      expect(settings.recentStickerKeys.length, 2, reason: '空 key 忽略');
    });

    test('超出上限后丢弃最旧的记录', () async {
      final settings = await newSettings();
      for (var i = 0; i < 40; i++) {
        await settings.pushRecentSticker('vec:s$i');
      }
      final recent = settings.recentStickerKeys;
      expect(recent.length, lessThanOrEqualTo(24));
      expect(recent.first, 'vec:s39');
      expect(recent, isNot(contains('vec:s0')), reason: '最旧的被挤出');
      expect(recent.toSet().length, recent.length, reason: '列表内无重复');
    });

    test('重启后仍读得到最近使用列表', () async {
      final settings = await newSettings();
      await settings.pushRecentSticker('vec:cat');
      await settings.pushRecentSticker('vec:star');

      final reopened = await newSettings();
      expect(reopened.recentStickerKeys, ['vec:star', 'vec:cat']);
    });
  });

  group('收藏素材（REQ-17.2）', () {
    test('收藏与取消收藏往返', () async {
      final settings = await newSettings();
      expect(settings.isFavoriteSticker('vec:cake'), isFalse);

      await settings.toggleFavoriteSticker('vec:cake');
      expect(settings.isFavoriteSticker('vec:cake'), isTrue);
      expect(settings.favoriteStickerKeys, ['vec:cake']);

      await settings.toggleFavoriteSticker('vec:bear');
      expect(settings.favoriteStickerKeys, [
        'vec:bear',
        'vec:cake',
      ], reason: '新收藏排在最前');

      await settings.toggleFavoriteSticker('vec:cake');
      expect(settings.isFavoriteSticker('vec:cake'), isFalse);
      expect(settings.favoriteStickerKeys, ['vec:bear']);
    });

    test('拖拽重排后的顺序持久化', () async {
      final settings = await newSettings();
      for (final key in ['vec:cat', 'vec:moon', 'vec:heart']) {
        await settings.toggleFavoriteSticker(key);
      }
      expect(settings.favoriteStickerKeys, [
        'vec:heart',
        'vec:moon',
        'vec:cat',
      ]);

      await settings.reorderFavoriteStickers([
        'vec:cat',
        'vec:heart',
        'vec:moon',
      ]);

      final reopened = await newSettings();
      expect(reopened.favoriteStickerKeys, [
        'vec:cat',
        'vec:heart',
        'vec:moon',
      ]);
    });
  });

  group('素材搜索（REQ-17.6）', () {
    test('矢量贴纸按中文关键词、名称、分类与 id 命中', () {
      final flower = stickerById('flower')!;
      expect(flower.matches('小花'), isTrue, reason: '素材名');
      expect(flower.matches('浪漫'), isTrue, reason: '中文关键词');
      expect(flower.matches('自然'), isTrue, reason: '分类名');
      expect(flower.matches('flower'), isTrue, reason: 'id');
      expect(flower.matches('FLOWER'), isTrue, reason: 'id 大小写不敏感');
      expect(flower.matches(' 花朵 '), isTrue, reason: '首尾空格被裁掉');
      expect(flower.matches(''), isTrue, reason: '空搜索词全量展示');

      expect(flower.matches('咖啡'), isFalse);
      expect(flower.matches('坦克'), isFalse);
    });

    test('搜索「甜点」命中美食类，且不误伤无关素材', () {
      final hits = vectorStickers.where((s) => s.matches('甜点')).toList();
      expect(hits, isNotEmpty);
      expect(hits.map((s) => s.id), contains('cake'));
      expect(hits.map((s) => s.id), isNot(contains('cat')));

      expect(
        vectorStickers.where((s) => s.matches('坦克')),
        isEmpty,
        reason: '词库里没有的词不应命中任何素材',
      );
    });

    test('自定义贴纸按名称、分组与关键词命中', () {
      final custom = CustomSticker(
        id: 'a' * 40,
        name: '手绘星星 Star',
        category: '我的',
        keywords: '涂鸦 手账 doodle',
      );
      expect(custom.matches('星星'), isTrue, reason: '素材名');
      expect(custom.matches('star'), isTrue, reason: '名称英文部分大小写不敏感');
      expect(custom.matches('STAR'), isTrue);
      expect(custom.matches('我的'), isTrue, reason: '分组名');
      expect(custom.matches('涂鸦'), isTrue, reason: '关键词');
      expect(custom.matches('DOODLE'), isTrue);
      expect(custom.matches(''), isTrue);

      expect(custom.matches('咖啡'), isFalse);
      expect(custom.matches('坦克'), isFalse);
      expect(custom.stickerKey, 'img:${'a' * 40}');
    });

    test('emoji 按中文检索词与字符本身命中', () {
      final blossom = emojiCategories.values
          .expand((list) => list)
          .firstWhere((e) => e.char == '🌸');
      expect(blossom.matches('樱花'), isTrue);
      expect(blossom.matches('🌸'), isTrue, reason: '直接粘贴字符也能搜到');
      expect(blossom.matches(''), isTrue);
      expect(blossom.matches('坦克'), isFalse);
    });
  });

  group('emoji 全集（REQ-17.7）', () {
    test('数量显著多于旧的 30 个硬编码列表', () {
      expect(
        stickerPalette.length,
        greaterThan(200),
        reason: '旧版仅 30 个 emoji，扩容后应有数百个',
      );
      expect(
        stickerPalette.length,
        emojiCategories.values.fold<int>(0, (sum, list) => sum + list.length),
        reason: '扁平列表即全部类目之和',
      );
    });

    test('各类目非空、类目名为中文', () {
      expect(emojiCategories.length, greaterThanOrEqualTo(8));
      for (final entry in emojiCategories.entries) {
        expect(entry.value, isNotEmpty, reason: '类目「${entry.key}」不得为空');
        expect(
          entry.key,
          matches(RegExp(r'^[一-龥]+$')),
          reason: '类目名「${entry.key}」应为中文',
        );
      }
    });

    test('全集无重复项，且每个 emoji 都带中文检索词', () {
      final chars = stickerPalette;
      expect(chars.toSet().length, chars.length, reason: '同一 emoji 不应出现在两个类目');

      for (final emoji in emojiCategories.values.expand((list) => list)) {
        expect(emoji.char, isNotEmpty);
        expect(
          emoji.keywords.trim(),
          isNotEmpty,
          reason: '「${emoji.char}」缺少检索词，搜索会漏掉它',
        );
        expect(
          emoji.keywords,
          matches(RegExp(r'[一-龥]')),
          reason: '「${emoji.char}」的检索词应含中文',
        );
      }
    });

    test('emoji 贴纸 key 恒可渲染', () {
      for (final char in stickerPalette.take(20)) {
        expect(isKnownStickerKey('$stickerKeyEmoji$char'), isTrue);
      }
    });
  });

  // 扩充后的量级下限：当前实际 1255 项 / 13 类目。
  // 一律用 greaterThan 而非等值断言 —— 以后继续加字不该把测试改红，
  // 但整批丢失（比如误删某个类目块）必须立刻暴露。
  group('emoji 扩充后的规模回归（REQ-17.7）', () {
    List<EmojiAsset> allEmoji() =>
        emojiCategories.values.expand((list) => list).toList();

    test('总量与类目数达到扩充后的量级', () {
      expect(
        stickerPalette.length,
        greaterThan(1000),
        reason: '扩充后应覆盖常用 Unicode 主体（当前 1255 项），跌回三位数说明有整块丢失',
      );
      expect(
        emojiCategories.length,
        greaterThanOrEqualTo(12),
        reason: '扩充后拆出了「身体」「服饰」等类目（当前 13 类），类目数不应回退',
      );
      for (final entry in emojiCategories.entries) {
        expect(
          entry.value.length,
          greaterThanOrEqualTo(10),
          reason: '类目「${entry.key}」只剩 ${entry.value.length} 项，太少就不值得单独占一个页签',
        );
      }
    });

    test('扁平列表与类目顺序严格一致', () {
      expect(stickerPalette, [
        for (final e in allEmoji()) e.char,
      ], reason: '面板按 stickerPalette 渲染、按类目分段跳转，两者顺序错位会跳错位置');
    });

    test('扩充后全集仍无重复字符', () {
      final seen = <String, String>{};
      final duplicated = <String>[];
      for (final entry in emojiCategories.entries) {
        for (final emoji in entry.value) {
          final previous = seen[emoji.char];
          if (previous != null) {
            duplicated.add('${emoji.char}（$previous / ${entry.key}）');
          } else {
            seen[emoji.char] = entry.key;
          }
        }
      }
      expect(
        duplicated,
        isEmpty,
        reason: '同一 emoji 出现在多个类目：${duplicated.join('、')}',
      );
      expect(seen.length, stickerPalette.length);
    });

    test('每个 emoji 都有多个中文检索词，且字符本身干净', () {
      final chinese = RegExp(r'[一-龥]');
      for (final emoji in allEmoji()) {
        expect(
          emoji.char.trim(),
          emoji.char,
          reason: '「${emoji.char}」的字符带了空白，贴到画布上会串位',
        );
        final words = emoji.keywords.split(RegExp(r'\s+'))
          ..removeWhere((w) => w.isEmpty);
        expect(
          words.length,
          greaterThanOrEqualTo(2),
          reason: '「${emoji.char}」只有 ${words.length} 个检索词，搜索命中率会明显下降',
        );
        // 允许夹带英文别名（如 🦹 的 boss），但中文词至少要有两个，
        // 否则中文搜索只剩一条命中路径，换个说法就搜不到了。
        expect(
          words.where((w) => chinese.hasMatch(w)).length,
          greaterThanOrEqualTo(2),
          reason: '「${emoji.char}」的中文检索词不足两个：${emoji.keywords}',
        );
      }
    });

    test('类目名仍为纯中文，且互不重复', () {
      final names = emojiCategories.keys.toList();
      expect(names.toSet().length, names.length, reason: '类目名重复，页签会撞车');
      for (final name in names) {
        expect(
          name,
          matches(RegExp(r'^[一-龥]+$')),
          reason: '类目名「$name」应为纯中文（面板页签直接显示它）',
        );
      }
    });

    test('扩充进来的每个 emoji 都是可渲染的合法贴纸 key', () {
      for (final char in stickerPalette) {
        expect(
          isKnownStickerKey('$stickerKeyEmoji$char'),
          isTrue,
          reason: '「$char」拼出的 key 不被识别，贴到手账上会变成缺失占位',
        );
      }
    });
  });

  group('贴纸换色（REQ-19）', () {
    test('tint 随画布序列化往返保留', () {
      final canvas = JournalCanvas(
        paperId: 'plain',
        elements: [
          StickerElement(key: 'vec:flower', tint: 0xFF3366CC),
          StickerElement(key: 'vec:cat'),
        ],
      );

      final restored = decodeCanvas(encodeCanvas(canvas))!;
      final stickers = restored.elements.whereType<StickerElement>().toList();
      expect(stickers.length, 2);
      expect(stickers.first.tint, 0xFF3366CC);
      expect(stickers.last.tint, isNull, reason: '未换色的贴纸不写入 tc 字段');
    });

    test('存量数据无 tc 字段时解码为原配色', () {
      const legacy =
          '{"paper":"plain","elements":['
          '{"t":"sticker","k":"vec:flower","x":0.3,"y":0.4,"w":0.2,"h":0.2}]}';
      final sticker = decodeCanvas(
        legacy,
      )!.elements.whereType<StickerElement>().single;
      expect(sticker.tint, isNull, reason: '存量手账不得因换色特性发生视觉突变');
      expect(sticker.key, 'vec:flower');
    });

    test('换色后的渲染结果与原配色不同', () async {
      final plain = await renderSticker('flower');
      final tinted = await renderSticker('flower', tint: 0xFF3366CC);
      expect(tinted.length, plain.length);
      expect(tinted, isNot(equals(plain)), reason: '选了颜色却没变化');
    });

    test('换色是色相迁移而非整体单色填充', () async {
      const tint = 0xFF3366CC;
      final tinted = await renderSticker('flower', tint: tint);
      final solid = flattenToColor(tinted, tint);
      expect(tinted, isNot(equals(solid)), reason: '若整体压成单色，多色层次与高光就没了');
    });

    test('轮廓墨色不被换色覆盖', () async {
      const ink = 0xFF6B5A48;
      final plain = await renderSticker('flower');
      final tinted = await renderSticker('flower', tint: 0xFF3366CC);
      final plainInk = countNear(plain, ink);
      expect(plainInk, greaterThan(0), reason: '小花本就有墨色轮廓');
      expect(
        countNear(tinted, ink),
        closeTo(plainInk, plainInk * 0.2),
        reason: '中性轮廓色应原样保留，五官与线条才认得出',
      );
    });

    test('缺失素材占位不受 tint 影响', () async {
      final plain = await renderSticker('__no_such_sticker__');
      final tinted = await renderSticker(
        '__no_such_sticker__',
        tint: 0xFF3366CC,
      );
      expect(tinted, equals(plain), reason: '占位框不该被染色，否则更难辨认');
    });
  });
}
