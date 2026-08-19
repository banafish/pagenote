import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/app_fonts.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/pages/template_manager_page.dart'
    show referencedStickerIds, templateWithoutPhotos;
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/services/share_pack_service.dart';
import 'package:pagenote/utils/sticker_store.dart';

/// 分享包（REQ-21）与不可信文件 / 版本兼容（NFR-06、NFR-07）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    // 全局单例，不复位会污染其它用例的引用完整性判定。
    CustomStickerIndex.instance.replaceAll({}, {});
  });

  // ---------------- 构造件 ----------------

  /// 一张真实的小 PNG（分享包只搬运字节，但不依赖任何外部素材文件）。
  Uint8List pngOf(int seed) {
    final image = img.Image(width: 8, height: 8, numChannels: 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        image.setPixelRgba(x, y, (x * 9 + seed) % 256, y * 7 % 256, seed, 255);
      }
    }
    return img.encodePng(image);
  }

  /// 内容寻址的自定义贴纸：id 就是字节 sha1，与 REQ-20 的落盘一致。
  CustomSticker stickerOf(Uint8List bytes, String name) =>
      CustomSticker(id: StickerStore.idOf(bytes), name: name);

  JournalTemplate templateOf(
    String id, {
    required String name,
    String paperId = 'plain',
    List<CanvasElement> elements = const [],
  }) => JournalTemplate(
    id: id,
    name: name,
    canvas: JournalCanvas(paperId: paperId, elements: List.of(elements)),
  );

  Future<TemplateProvider> newProvider() async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = TemplateProvider(database: db);
    await provider.load();
    return provider;
  }

  // ---------------- 拆包用的小工具 ----------------

  Archive open(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

  Set<String> namesOf(Uint8List bytes) => {for (final f in open(bytes)) f.name};

  Map<String, Object?> packJsonOf(Uint8List bytes) {
    final file = open(bytes).findFile('pack.json');
    expect(file, isNotNull, reason: '附录：包元信息固定放 pack.json');
    return (jsonDecode(utf8.decode(file!.content as List<int>)) as Map)
        .cast<String, Object?>();
  }

  /// 条目名 + 所有文本条目拼成一整块，用于搜本机路径痕迹（REQ-21.4）。
  String textOf(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final f in open(bytes)) {
      buffer.writeln(f.name);
      if (f.name.endsWith('.json')) {
        buffer.writeln(utf8.decode(f.content as List<int>));
      }
    }
    return buffer.toString();
  }

  /// 断言抛出的是给用户看的中文提示，而不是裸异常（REQ-21.10）。
  void expectReadable(void Function() action, {String? keyword}) {
    Object? caught;
    try {
      action();
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<SharePackFormatException>(), reason: '应转成可读错误：$caught');
    final message = (caught! as SharePackFormatException).message;
    expect(message, matches(RegExp(r'[一-龥]')), reason: '「$message」应为可读中文');
    if (keyword != null) expect(message, contains(keyword));
  }

  // ---------------- 手工拼包（模拟外部 / 恶意文件） ----------------

  ArchiveFile jsonFile(String name, Object? value) => ArchiveFile.bytes(
    name,
    Uint8List.fromList(utf8.encode(jsonEncode(value))),
  );

  /// 手工拼一条 templates.json 记录，不经 toMap，模拟外部改造过的包。
  Map<String, Object?> templateMap(
    String id, {
    required String name,
    JournalCanvas? canvas,
    Map<String, Object?> extra = const {},
  }) {
    const ts = 1755000000000;
    return {
      'id': id,
      'name': name,
      'title': '',
      'content': '正文$id',
      'tags': '',
      'builtin': 0,
      'canvas': encodeCanvas(canvas),
      'originId': null,
      'lastUsedAt': null,
      'sortIndex': 0,
      'createdAt': ts,
      'updatedAt': ts,
      ...extra,
    };
  }

  /// 不经服务打包路径的分享包，按附录结构手工拼装。
  Uint8List rawPack({
    int? format,
    String kind = 'template',
    List<Map<String, Object?>> templates = const [],
    List<Map<String, Object?>> stickers = const [],
    bool withStickersFile = true,
    Map<String, Object?> extraMeta = const {},
    List<ArchiveFile> extraFiles = const [],
  }) {
    final meta = <String, Object?>{
      'app': 'pagenote',
      'format': format ?? SharePackService.formatVersion,
      'kind': kind,
      'id': 'pack-test',
      'name': '测试包',
      'author': '阿拾',
      'version': 1,
      'createdAt': '2026-08-18T10:00:00.000',
      'counts': {'templates': templates.length, 'stickers': stickers.length},
      ...extraMeta,
    };
    final archive = Archive()
      ..addFile(jsonFile('pack.json', meta))
      ..addFile(jsonFile('templates.json', templates));
    if (withStickersFile) archive.addFile(jsonFile('stickers.json', stickers));
    for (final f in extraFiles) {
      archive.addFile(f);
    }
    return ZipEncoder().encodeBytes(archive);
  }

  // ================= 打包 → 解包往返 =================

  group('打包与解包往返（REQ-21.1/21.2/21.5）', () {
    test('模板与贴纸原样往返，包名署名不丢（REQ-21.1/21.2）', () async {
      final catBytes = pngOf(1);
      final tapeBytes = pngOf(2);
      final cat = stickerOf(catBytes, '手绘猫');
      final tape = stickerOf(tapeBytes, '格纹胶带');

      final bytes = await SharePackService.instance.buildPack(
        packName: '秋日旅行模板集',
        author: '阿拾',
        templates: [
          templateOf(
            'tpl-a',
            name: '秋日跨页',
            paperId: 'sakura',
            elements: [StickerElement(key: cat.stickerKey)],
          ),
          templateOf('tpl-b', name: '车票拼贴'),
        ],
        stickers: [cat, tape],
        stickerBytes: {cat.fileName: catBytes, tape.fileName: tapeBytes},
      );

      final pack = SharePackService.instance.parsePack(bytes);
      expect(pack.name, '秋日旅行模板集');
      expect(pack.author, '阿拾');
      expect(pack.templates.length, 2);
      expect(pack.templates.map((t) => t.name).toList(), ['秋日跨页', '车票拼贴']);
      expect(pack.templates.first.canvas!.paperId, 'sakura');
      expect(pack.templates.first.canvas!.stickerKeys, {cat.stickerKey});
      expect(pack.stickers.length, 2);
      expect(pack.stickers.map((s) => s.id).toList(), [cat.id, tape.id]);
      expect(pack.stickers.first.name, '手绘猫');
      // 位图按 `<sha1><ext>` 索引，与 CustomSticker.fileName 对齐。
      expect(pack.stickerBytes.keys.toSet(), {cat.fileName, tape.fileName});
      expect(pack.stickerBytes[cat.fileName], catBytes);
      expect(namesOf(bytes), containsAll(['pack.json', 'templates.json']));
      expect(namesOf(bytes), contains('assets/${cat.fileName}'));

      final meta = packJsonOf(bytes);
      expect(meta['app'], 'pagenote', reason: '与备份包一样用 app 认亲');
      expect(meta['format'], SharePackService.formatVersion);
      expect(meta['name'], '秋日旅行模板集');
      expect((meta['counts']! as Map)['templates'], 2);
      expect((meta['counts']! as Map)['stickers'], 2);
    });

    test('kind 按内容取 template / sticker / mixed（附录设计约束 1）', () async {
      final bytes = pngOf(3);
      final sticker = stickerOf(bytes, '小花');
      final template = templateOf('tpl-only', name: '纯模板');

      Future<String> kindOf({
        List<JournalTemplate> templates = const [],
        List<CustomSticker> stickers = const [],
      }) async {
        final packed = await SharePackService.instance.buildPack(
          packName: '测试包',
          author: '',
          templates: templates,
          stickers: stickers,
          stickerBytes: {for (final s in stickers) s.fileName: bytes},
        );
        return packJsonOf(packed)['kind']! as String;
      }

      expect(await kindOf(templates: [template]), 'template');
      expect(await kindOf(stickers: [sticker]), 'sticker');
      expect(await kindOf(templates: [template], stickers: [sticker]), 'mixed');
    });

    test('模板引用到的贴纸随包带上，调用方没勾也在（REQ-21.3）', () async {
      final usedBytes = pngOf(4);
      final pickedBytes = pngOf(5);
      final used = stickerOf(usedBytes, '被模板引用的贴纸');
      final picked = stickerOf(pickedBytes, '用户勾选的贴纸');

      final template = templateOf(
        'tpl-ref',
        name: '引用了贴纸的模板',
        elements: [StickerElement(key: used.stickerKey)],
      );

      // 导出入口的取件规则：用户勾选 ∪ 画布引用（REQ-21.3）。
      final ids = {
        picked.id,
        ...referencedStickerIds([template]),
      };
      expect(ids, {picked.id, used.id}, reason: '画布里的 img:<sha1> 要能被挖出来');

      final all = [used, picked];
      final bytesOf = {used.fileName: usedBytes, picked.fileName: pickedBytes};
      final packed = await SharePackService.instance.buildPack(
        packName: '带素材的模板包',
        author: '',
        templates: [template],
        stickers: [
          for (final s in all)
            if (ids.contains(s.id)) s,
        ],
        stickerBytes: {
          for (final e in bytesOf.entries)
            if (ids.contains(p.basenameWithoutExtension(e.key))) e.key: e.value,
        },
      );

      expect(
        namesOf(packed),
        containsAll(['assets/${used.fileName}', 'assets/${picked.fileName}']),
        reason: '接收方要开箱即用',
      );
      final pack = SharePackService.instance.parsePack(packed);
      expect(pack.stickerBytes[used.fileName], usedBytes);
      expect(pack.stickers.map((s) => s.id), containsAll([used.id, picked.id]));
    });

    test('包内不含任何本机绝对路径（REQ-21.4）', () async {
      final dir = await Directory.systemTemp.createTemp('pagenote-pack');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final photo = File(p.join(dir.path, 'trip.jpg'));
      await photo.writeAsBytes(pngOf(6));

      JournalTemplate withPhoto() => templateOf(
        'tpl-photo',
        name: '带照片的模板',
        elements: [
          ImageElement(path: photo.path),
          TextElement(text: '旅行记录'),
        ],
      );

      /// 本机痕迹：盘符、临时目录全路径、当前用户名。
      void expectClean(String text) {
        expect(
          text,
          isNot(matches(RegExp(r'[A-Za-z]:[\\/]'))),
          reason: '不得出现 Windows 盘符',
        );
        expect(text, isNot(contains(dir.path)));
        for (final segment in p.split(dir.path)) {
          if (segment.length > 3 && !segment.contains(':')) {
            expect(text, isNot(contains(segment)), reason: '路径片段「$segment」泄漏了');
          }
        }
        final user = Platform.environment['USERNAME'] ?? '';
        if (user.length > 2) expect(text, isNot(contains(user)));
      }

      // 导出入口的规则：照片不进包，只留占位框（FIX-01 + REQ-21.4）。
      final viaEntry = await SharePackService.instance.buildPack(
        packName: '模板包',
        author: '',
        templates: [templateWithoutPhotos(withPhoto())],
        stickers: const [],
        stickerBytes: const {},
      );
      expectClean(textOf(viaEntry));

      // 兜底：调用方忘了清，打包本身也不许把绝对路径写进包。
      final raw = await SharePackService.instance.buildPack(
        packName: '模板包',
        author: '',
        templates: [withPhoto()],
        stickers: const [],
        stickerBytes: const {},
      );
      expectClean(textOf(raw));
      // 本机模板对象不受影响，画布里的照片还在。
      final local = withPhoto();
      await SharePackService.instance.buildPack(
        packName: '模板包',
        author: '',
        templates: [local],
        stickers: const [],
        stickerBytes: const {},
      );
      expect(local.canvas!.hasImagePaths, isTrue);
    });
  });

  // ================= 导入安装 =================

  group('导入安装（REQ-21.8）', () {
    test('重分配 id、originId 记原 id、builtin 恒 false、同名保留两者（REQ-21.8）', () async {
      final provider = await newProvider();
      final bytes = rawPack(
        templates: [
          templateMap('tpl-friend', name: '朋友的模板'),
          templateMap('tpl-friend-2', name: '朋友的模板'),
          // 自称内置的模板，安装后同样只能是可删的用户模板。
          templateMap('tpl-fake', name: '伪装成内置', extra: {'builtin': 1}),
        ],
      );

      final pack = SharePackService.instance.parsePack(bytes);
      expect(pack.templates.every((t) => !t.builtin), isTrue, reason: '自称不采信');

      final installed = await provider.installTemplates(pack.templates);
      expect(installed.length, 3);
      expect(
        installed.map((t) => t.id).toSet().intersection({
          'tpl-friend',
          'tpl-friend-2',
          'tpl-fake',
        }),
        isEmpty,
        reason: 'id 一律重新分配',
      );
      expect(installed.map((t) => t.originId).toList(), [
        'tpl-friend',
        'tpl-friend-2',
        'tpl-fake',
      ]);
      expect(installed.every((t) => !t.builtin), isTrue);
      expect(installed.map((t) => t.name).toList(), [
        '朋友的模板',
        '朋友的模板 (2)',
        '伪装成内置',
      ]);
      expect(provider.userTemplates.length, 3);
      // 装进来的模板必须删得掉。
      await provider.deleteTemplate(installed.first.id);
      expect(provider.byId(installed.first.id), isNull);
    });

    test('开启覆盖同名时替换已有模板（REQ-21.8）', () async {
      final provider = await newProvider();
      final first = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-v1', name: '朋友的模板')]),
      );
      final old = (await provider.installTemplates(first.templates)).single;
      expect(provider.userTemplates.length, 1);

      final second = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-v2', name: '朋友的模板')]),
      );
      final fresh = (await provider.installTemplates(
        second.templates,
        overwriteSameName: true,
      )).single;

      expect(provider.userTemplates.length, 1, reason: '覆盖而不是并存');
      expect(fresh.name, '朋友的模板', reason: '覆盖时不加后缀');
      expect(provider.byId(old.id), isNull);
      expect(provider.byId(fresh.id)!.originId, 'tpl-v2');
      expect(fresh.builtin, isFalse);
    });
  });

  // ================= 格式版本兼容 =================

  group('格式版本兼容（NFR-07）', () {
    test('format 高于本机：提示更新版本且一条都不写进库（NFR-07）', () async {
      final provider = await newProvider();
      final before = provider.userTemplates.length;
      final bytes = rawPack(
        format: SharePackService.formatVersion + 1,
        templates: [
          templateMap('tpl-future', name: '未来模板'),
          templateMap('tpl-future-2', name: '未来模板二'),
        ],
      );

      expectReadable(
        () => SharePackService.instance.parsePack(bytes),
        keyword: '更新版本',
      );
      expect(provider.userTemplates.length, before, reason: '不做部分导入');
      expect(provider.byId('tpl-future'), isNull);
    });

    test('低版本包与未知字段能正常读取（NFR-07）', () {
      final bytes = rawPack(
        // 附录草案的 format: 1，高版本必须能读。
        format: 1,
        templates: [
          templateMap(
            'tpl-old',
            name: '老包里的模板',
            canvas: JournalCanvas(paperId: 'grid'),
            extra: {'futureField': '未来才有的字段'},
          ),
        ],
        // 老包没有的可选项：stickers.json 整个缺失。
        withStickersFile: false,
        extraMeta: {'futureMeta': 42},
      );

      final pack = SharePackService.instance.parsePack(bytes);
      expect(pack.templates.single.name, '老包里的模板');
      expect(pack.templates.single.canvas!.paperId, 'grid');
      expect(pack.stickers, isEmpty);
      expect(pack.stickerBytes, isEmpty);
      expect(pack.name, '测试包');
    });
  });

  // ================= 不可信文件 =================

  group('不可信文件（NFR-06）', () {
    test('条目名含 .. 或绝对路径的包被拒绝（NFR-06 防路径穿越）', () {
      for (final name in [
        '../evil.png',
        'assets/../../evil.png',
        r'C:\Windows\evil.png',
        '/etc/passwd',
      ]) {
        expectReadable(
          () => SharePackService.instance.parsePack(
            rawPack(extraFiles: [ArchiveFile.bytes(name, pngOf(7))]),
          ),
        );
      }
    });

    test('解压后总体积超限的包被拒绝（NFR-06 防解压炸弹）', () {
      const chunk = 1024 * 1024;
      // 同一块缓冲反复入包：声明体积上去了，测试自身内存不涨。
      final zeros = Uint8List(chunk);
      final count = SharePackService.maxUnpackedBytes ~/ chunk + 1;
      final bytes = rawPack(
        extraFiles: [
          for (var i = 0; i < count; i++)
            ArchiveFile.bytes('assets/pad$i.bin', zeros),
        ],
      );
      expect(
        bytes.lengthInBytes,
        lessThan(SharePackService.maxPackBytes),
        reason: '压缩后仍在单包上限内，确保命中的是解压体积这道闸',
      );
      expectReadable(() => SharePackService.instance.parsePack(bytes));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('条目数超限的包被拒绝（NFR-06）', () {
      final one = Uint8List(1);
      final bytes = rawPack(
        extraFiles: [
          for (var i = 0; i <= SharePackService.maxArchiveFiles; i++)
            ArchiveFile.bytes('assets/tiny$i.bin', one),
        ],
      );
      expectReadable(() => SharePackService.instance.parsePack(bytes));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('单包超过 20MB 被拒绝（NFR-06）', () {
      expect(
        SharePackService.maxPackBytes,
        20 * 1024 * 1024,
        reason: 'NFR-06 定的单包上限',
      );
      // 存储方式入包，压不下去，得到一个体积真的超限的合法 zip。
      final big = ArchiveFile.bytes(
        'assets/big.bin',
        Uint8List(SharePackService.maxPackBytes),
      )..compression = CompressionType.none;
      final bytes = rawPack(extraFiles: [big]);
      expect(bytes.lengthInBytes, greaterThan(SharePackService.maxPackBytes));

      expectReadable(
        () => SharePackService.instance.parsePack(bytes),
        keyword: '${SharePackService.maxPackBytes ~/ (1024 * 1024)}',
      );
    });

    test('损坏或不相干的文件抛可读中文错误（REQ-21.10 / NFR-06）', () {
      // 根本不是 zip。
      expectReadable(
        () => SharePackService.instance.parsePack(
          Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      // 是 zip 但没有 pack.json。
      expectReadable(
        () => SharePackService.instance.parsePack(
          ZipEncoder().encodeBytes(
            Archive()..addFile(jsonFile('templates.json', const [])),
          ),
        ),
      );
      // 备份包不是分享包：顶层是 entries.json（技术要点：两种包必须分得开）。
      expectReadable(
        () => SharePackService.instance.parsePack(
          ZipEncoder().encodeBytes(
            Archive()..addFile(
              jsonFile('entries.json', {
                'app': 'pagenote',
                'format': 1,
                'entries': const [],
                'templates': const [],
              }),
            ),
          ),
        ),
      );
      // pack.json 存在但内容是坏的。
      expectReadable(
        () => SharePackService.instance.parsePack(
          ZipEncoder().encodeBytes(
            Archive()..addFile(ArchiveFile.string('pack.json', '{ 不是 json')),
          ),
        ),
      );
    });
  });

  // ================= 引用完整性 =================

  group('引用完整性（REQ-21.7）', () {
    test('未知贴纸 / 纸张 / 字体如实报数（REQ-21.7）', () async {
      final catBytes = pngOf(8);
      final cat = stickerOf(catBytes, '手绘猫');
      const strangeKey = 'vec:__no_such_sticker__';

      final bytes = await SharePackService.instance.buildPack(
        packName: '缺素材的包',
        author: '',
        templates: [
          templateOf(
            'tpl-missing',
            name: '缺素材模板',
            paperId: '__no_such_paper__',
            elements: [
              StickerElement(key: cat.stickerKey),
              StickerElement(key: strangeKey),
              TextElement(text: '标题', fontFamily: '__no_such_font__'),
            ],
          ),
        ],
        stickers: [cat],
        stickerBytes: {cat.fileName: catBytes},
      );

      final pack = SharePackService.instance.parsePack(bytes);
      final report = checkMissingAssets(
        pack.templates,
        hasPaper: (id) => paperById(id) != null,
        hasFont: (family) => fontByFamily(family) != null,
      );
      // 包内贴纸此刻还没落库，全局索引查不到，因此三类各计一项。
      expect(report.count, 4);
      expect(report.stickerKeys, {cat.stickerKey, strangeKey});
      expect(report.paperIds, {'__no_such_paper__'});
      expect(report.fontFamilies, {'__no_such_font__'});
      for (final label in report.labels) {
        expect(label, matches(RegExp(r'[一-龥]')), reason: '「$label」应为中文可读');
      }

      // 预览页的算法：减去随包带来的贴纸后，只剩真正装不上的三项。
      final provided = {for (final s in pack.stickers) s.stickerKey};
      final real = report.stickerKeys.where((k) => !provided.contains(k));
      expect(real, {strangeKey});
    });
  });
}
