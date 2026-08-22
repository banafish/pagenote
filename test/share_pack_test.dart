import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/app_fonts.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/pages/pack_actions.dart'
    show referencedStickerIds, templateWithoutPhotos;
import 'package:pagenote/providers/custom_sticker_provider.dart';
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
      // pack.json 的 id 原样带回，导入端据此做同包去重（v7）。
      expect(pack.packId, isNotNull);
      expect(pack.packId, startsWith('pack-'));
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

    test('整包导出复用包的稳定 id,不传则现场生成（v8）', () async {
      // 整包导出传包的 originId：包无论经几手转发，接收方都按它归位到同一个包。
      final bytes = await SharePackService.instance.buildPack(
        packName: '稳定身份包',
        author: '',
        templates: [templateOf('tpl-stable', name: '模板')],
        packId: 'pack-stable-id',
      );
      expect(packJsonOf(bytes)['id'], 'pack-stable-id');
      expect(
        SharePackService.instance.parsePack(bytes).packId,
        'pack-stable-id',
      );

      // 散选内容拼的临时包没有持续身份，每次导出都是新 id。
      final adhoc1 = await SharePackService.instance.buildPack(
        packName: '散选包',
        author: '',
        templates: [templateOf('tpl-pick', name: '模板')],
      );
      final adhoc2 = await SharePackService.instance.buildPack(
        packName: '散选包',
        author: '',
        templates: [templateOf('tpl-pick', name: '模板')],
      );
      final id1 = packJsonOf(adhoc1)['id']! as String;
      final id2 = packJsonOf(adhoc2)['id']! as String;
      expect(id1, isNot(id2));
      expect(id1, startsWith('pack-'));
    });

    test('包封面 cover.png 可选往返，格式不升版（REQ-27.6）', () async {
      final cover = pngOf(7);
      // 整包导出带上封面：写入顶层 cover.png，format 仍是 1。
      final withCover = await SharePackService.instance.buildPack(
        packName: '有封面包',
        author: '',
        templates: [templateOf('tpl-cover', name: '模板')],
        packId: 'pack-cover',
        coverBytes: cover,
      );
      expect(namesOf(withCover), contains('cover.png'));
      expect(packJsonOf(withCover)['format'], 1, reason: '附录中本就可选，不升版');
      final parsed = SharePackService.instance.parsePack(withCover);
      expect(parsed.coverBytes, cover);

      // 不带封面：老包与散选包没有 cover.png，解析端为 null（NFR-07 降级）。
      final bare = await SharePackService.instance.buildPack(
        packName: '无封面包',
        author: '',
        templates: [templateOf('tpl-bare', name: '模板')],
      );
      expect(namesOf(bare), isNot(contains('cover.png')));
      expect(SharePackService.instance.parsePack(bare).coverBytes, isNull);
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

    test('模板随包落位：installTemplates 挂 packId（v8）', () async {
      final provider = await newProvider();
      final pack = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-in-pack', name: '包内模板')]),
      );
      final installed = await provider.installTemplates(
        pack.templates,
        packId: 'pack-local-1',
      );
      expect(installed.single.packId, 'pack-local-1');
      expect(
        provider.templatesOfPack('pack-local-1').single.originId,
        'tpl-in-pack',
      );
      expect(provider.userTemplates.single.packId, 'pack-local-1');
    });

    test('同一分享包重复导入：模板按 originId 原位更新,不重复装（v8）', () async {
      final provider = await newProvider();
      final first = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-v1', name: '朋友的模板')]),
      );
      final installed = (await provider.installTemplates(
        first.templates,
        packId: 'pack-a',
      )).single;
      // 用户把模板改成自己的标签，并留下使用记录与手动排序。
      installed
        ..name = '我的复盘'
        ..lastUsedAt = DateTime(2026, 8, 1)
        ..sortIndex = 5;
      await provider.saveTemplate(installed);

      // 同一个包的新版本：包内 id（originId）不变，内容更新。
      final upgraded = templateMap('tpl-v1', name: '朋友的模板')
        ..['content'] = '新版本正文';
      final second = SharePackService.instance.parsePack(
        rawPack(templates: [upgraded]),
      );
      final updated = (await provider.installTemplates(
        second.templates,
        packId: 'pack-a',
      )).single;

      expect(provider.userTemplates.length, 1, reason: '同一个模板原位更新');
      expect(updated.id, installed.id, reason: '本地 id 稳定,套用记录不丢');
      expect(updated.content, '新版本正文', reason: '内容换成包内新版本');
      expect(updated.name, '我的复盘', reason: '名字是用户自己的标签,不跟包走');
      expect(updated.lastUsedAt, DateTime(2026, 8, 1), reason: '使用记录保留');
      expect(updated.sortIndex, 5, reason: '手动排序保留');
      expect(updated.packId, 'pack-a');
    });

    test('先前散落的同一模板在重复导入时归位回包（v8 升级存量场景）', () async {
      final provider = await newProvider();
      // v8 之前导入的模板：originId 有记录,但没有包归属。
      final legacy = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-old', name: '老包模板')]),
      );
      final scattered = (await provider.installTemplates(
        legacy.templates,
      )).single;
      expect(scattered.packId, isNull);

      // 升级后重复导入同一个包：归位回包,不改名不加后缀。
      final again = (await provider.installTemplates(
        legacy.templates,
        packId: 'pack-back',
      )).single;
      expect(again.id, scattered.id);
      expect(again.packId, 'pack-back', reason: '未分组的同一模板归位回包');
      expect(again.name, '老包模板', reason: '归位不是重装,不动名字');
      expect(provider.userTemplates.length, 1);
    });

    test('用户挪进其它包的模板不被重复导入抢回（v8）', () async {
      final provider = await newProvider();
      final pack = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-mine', name: '挪走的模板')]),
      );
      final installed = (await provider.installTemplates(
        pack.templates,
        packId: 'pack-a',
      )).single;
      installed.packId = 'pack-b';
      await provider.saveTemplate(installed);

      final again = (await provider.installTemplates(
        pack.templates,
        packId: 'pack-a',
      )).single;
      expect(again.id, installed.id);
      expect(again.packId, 'pack-b', reason: '已有的归属优先于导入包的落位');
    });

    test('复制出的副本不继承 originId / packId,不跟随包更新（v8）', () async {
      final provider = await newProvider();
      final pack = SharePackService.instance.parsePack(
        rawPack(templates: [templateMap('tpl-dup', name: '可复制的模板')]),
      );
      final installed = (await provider.installTemplates(
        pack.templates,
        packId: 'pack-a',
      )).single;
      final copy = await provider.duplicateTemplate(installed);
      expect(copy.originId, isNull, reason: '副本是用户自己的新模板');
      expect(copy.packId, isNull);
      expect(provider.userTemplates.length, 2);

      // 包更新只碰原件,副本保持独立,也不会被误判成重复。
      final upgraded = templateMap('tpl-dup', name: '可复制的模板')
        ..['content'] = '新版本正文';
      final second = SharePackService.instance.parsePack(
        rawPack(templates: [upgraded]),
      );
      await provider.installTemplates(second.templates, packId: 'pack-a');
      expect(provider.userTemplates.length, 2, reason: '副本不参与 originId 去重');
      expect(provider.byId(copy.id)!.content, '正文tpl-dup');
      expect(provider.byId(installed.id)!.content, '新版本正文');
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

  // ================= 安装素材时的尺寸闸（NFR-06） =================

  group('分享包素材落盘的尺寸闸（NFR-06）', () {
    useTempDocuments();

    /// 每个用例一套独立的贴纸库。
    Future<CustomStickerProvider> newStickerProvider() async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final provider = CustomStickerProvider(database: db);
      await provider.load();
      return provider;
    }

    /// 图像层的解压炸弹：文件只有几百字节，头里却声明 20000×20000
    /// （解码成 RGBA 约 1.6GB）。改 IHDR 的宽高后补回该块的 CRC32，
    /// 得到一个头部完全合法、只有真去解码才会炸的文件。
    /// PNG 块布局：8..11 长度，12..15 类型 `IHDR`，16..28 数据（宽 4 + 高 4 + …），29..32 CRC。
    Uint8List bombPng() {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4, numChannels: 4)),
      );
      final view = ByteData.sublistView(bytes);
      view.setUint32(16, 20000);
      view.setUint32(20, 20000);
      view.setUint32(29, getCrc32(bytes.sublist(12, 29)));
      return bytes;
    }

    /// 一张真实可解码的大图：色块填充，解码后 600 万像素，
    /// 编码后只有几十 KB，不至于让整包撞上 maxPackBytes 把闸门测歪。
    Uint8List bigPng(int width, int height) {
      final image = img.Image(width: width, height: height, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(240, 235, 220, 255));
      for (var i = 0; i < 6; i++) {
        img.fillRect(
          image,
          x1: i * 400,
          y1: i * 200,
          x2: i * 400 + 360,
          y2: i * 200 + 160,
          color: img.ColorRgba8(30 + i * 30, 90, 160, 255),
        );
      }
      return img.encodePng(image);
    }

    /// 素材目录里实际存在的文件名。
    Future<Set<String>> storedNames() async {
      final dir = await StickerStore.ensureDir();
      return {
        for (final f in dir.listSync().whereType<File>()) p.basename(f.path),
      };
    }

    test('声明尺寸极大的图被解码前拒绝且不落盘，同包其余贴纸照常导入（NFR-06）', () async {
      final provider = await newStickerProvider();
      final bombBytes = bombPng();
      final goodBytes = pngOf(11);
      final bomb = stickerOf(bombBytes, '解压炸弹');
      final good = stickerOf(goodBytes, '正常贴纸');

      final packed = await SharePackService.instance.buildPack(
        packName: '夹带炸弹的包',
        author: '陌生人',
        templates: [
          templateOf(
            'tpl-bomb',
            name: '引用了炸弹的模板',
            elements: [StickerElement(key: bomb.stickerKey)],
          ),
        ],
        stickers: [bomb, good],
        stickerBytes: {bomb.fileName: bombBytes, good.fileName: goodBytes},
      );

      // 打包与解包只搬运字节，这道闸在落盘那一步（NFR-06）。
      final pack = SharePackService.instance.parsePack(packed);
      expect(pack.stickerBytes[bomb.fileName], bombBytes);

      // 导入页的循环：逐张 importFromBytes，返回 null 即这一张被跳过。
      final saved = <String, CustomSticker?>{};
      for (final s in pack.stickers) {
        saved[s.name] = await provider.importFromBytes(
          pack.stickerBytes[s.fileName]!,
          name: s.name,
        );
      }

      expect(saved['解压炸弹'], isNull, reason: '超出解码上限的图必须在解码前就被拒');
      expect(saved['正常贴纸'], isNotNull, reason: '一张坏图不能中断整包导入');
      expect(provider.stickers.map((s) => s.id).toList(), [good.id]);
      expect(await storedNames(), {good.fileName}, reason: '被拒的图一个字节都不许落盘');

      // 模板照常安装，被拒的贴纸退化为缺失占位（FIX-03），而不是让整包失败。
      final templates = await newProvider();
      final installed = await templates.installTemplates(pack.templates);
      expect(installed.single.canvas!.stickerKeys, {bomb.stickerKey});
    });

    test(
      '包里 3000×2000 的贴纸落盘前被压到 REQ-20.5 的上限内（NFR-06）',
      () async {
        final provider = await newStickerProvider();
        final bigBytes = bigPng(3000, 2000);
        final big = stickerOf(bigBytes, '朋友的大图');

        final packed = await SharePackService.instance.buildPack(
          packName: '大图包',
          author: '',
          templates: const [],
          stickers: [big],
          stickerBytes: {big.fileName: bigBytes},
        );
        expect(
          packed.lengthInBytes,
          lessThan(SharePackService.maxPackBytes),
          reason: '包本身没超限，确保命中的是落盘归一化这道闸',
        );

        final pack = SharePackService.instance.parsePack(packed);
        final saved = await provider.importFromBytes(
          pack.stickerBytes[big.fileName]!,
          name: big.name,
        );
        expect(saved, isNotNull, reason: '尺寸在解码上限内，应压缩后导入而不是跳过');

        final stored = File(
          StickerStore.pathOf(saved!.id, saved.ext),
        ).readAsBytesSync();
        expect(stored.length, lessThanOrEqualTo(StickerStore.maxBytes));
        final decoded = img.decodeImage(stored)!;
        expect(decoded.width, lessThanOrEqualTo(StickerStore.maxEdge));
        expect(decoded.height, lessThanOrEqualTo(StickerStore.maxEdge));
        expect(decoded.width, StickerStore.maxEdge, reason: '长边压到上限，等比缩放');
        expect(decoded.height, 683, reason: '3:2 等比缩放后的短边');
        expect(saved.id, StickerStore.idOf(stored), reason: 'id 恒等于落盘字节的 sha1');
        // 分享包来的大图不再原样落盘，sha1 必然改变，模板里的 img:<sha1>
        // 引用随之退化为缺失占位（FIX-03）。本应用 exportPack 产出的包走不到这条路：
        // 导出前素材已经在 REQ-20.5 的上限内。
        expect(saved.id, isNot(big.id));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  // ================= 分享包携带模板照片 =================

  group('分享包携带模板照片（FIX-01.2）', () {
    useTempDocuments();

    late Directory album;
    late File photo;
    late Uint8List photoBytes;

    setUp(() async {
      album = await Directory.systemTemp.createTemp('pagenote-album');
      photoBytes = pngOf(12);
      photo = File(p.join(album.path, 'trip.png'));
      await photo.writeAsBytes(photoBytes);
    });

    tearDown(() async {
      if (await album.exists()) await album.delete(recursive: true);
    });

    JournalTemplate photoTemplate() => templateOf(
      'tpl-with-photo',
      name: '带照片的模板',
      elements: [
        ImageElement(path: photo.path),
        TextElement(text: '旅行记录'),
      ],
    );

    /// 本机痕迹：盘符、照片目录全路径与其中的路径片段、当前用户名。
    void expectClean(String text) {
      expect(
        text,
        isNot(matches(RegExp(r'[A-Za-z]:[\\/]'))),
        reason: '不得出现 Windows 盘符',
      );
      expect(text, isNot(contains(album.path)));
      for (final segment in p.split(album.path)) {
        if (segment.length > 3 && !segment.contains(':')) {
          expect(text, isNot(contains(segment)), reason: '路径片段「$segment」泄漏了');
        }
      }
      final user = Platform.environment['USERNAME'] ?? '';
      if (user.length > 2) expect(text, isNot(contains(user)));
    }

    test('开关关闭（默认）：照片不入包，画布只剩占位框（FIX-01.1）', () async {
      final packed = await SharePackService.instance.buildPack(
        packName: '模板包',
        author: '',
        templates: [photoTemplate()],
      );

      expect(
        namesOf(packed).where((n) => n.startsWith('photos/')),
        isEmpty,
        reason: '默认不带私人照片，包内不该出现 photos/',
      );
      expectClean(textOf(packed));

      final pack = SharePackService.instance.parsePack(packed);
      expect(pack.photoBytes, isEmpty);
      final canvas = pack.templates.single.canvas!;
      expect(canvas.hasImagePaths, isFalse, reason: '路径一律清空');
      expect(canvas.images.length, 1, reason: '占位框本身要保留');
    });

    test('开关打开：照片作为附件入包，安装时重映射到本机新路径（FIX-01.2/01.3）', () async {
      final local = photoTemplate();
      final packed = await SharePackService.instance.buildPack(
        packName: '带照片的模板包',
        author: '阿拾',
        templates: [local],
        includePhotos: true,
      );

      expect(namesOf(packed), contains('photos/trip.png'));
      // REQ-21.4 仍是硬约束：照片进了包，文本条目里也不许留下本机绝对路径。
      expectClean(textOf(packed));
      // 调用方内存里的模板对象不受影响，本机路径还在。
      expect(local.canvas!.images.single.path, photo.path);

      final pack = SharePackService.instance.parsePack(packed);
      expect(pack.photoBytes.keys.toSet(), {'trip.png'});
      expect(pack.photoBytes['trip.png'], photoBytes, reason: '照片字节原样往返');
      expect(
        pack.templates.single.canvas!.images.single.path,
        'trip.png',
        reason: '包内只留纯文件名，由导入端重映射',
      );

      final provider = await newProvider();
      final installed = await provider.installTemplates(
        pack.templates,
        attachments: pack.photoBytes,
      );
      final path = provider
          .byId(installed.single.id)!
          .canvas!
          .images
          .single
          .path;
      expect(path, isNot(photo.path), reason: '落到本机附件目录，而不是导出方的路径');
      expect(p.isAbsolute(path), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), photoBytes);
    });
  });

  // ================= 素材 id 稳定性 =================

  group('内置素材与模板 id 稳定性（NFR-08）', () {
    // NFR-08：已发布的素材 / 模板 id **只能新增，不得重命名或删除**。
    // 存量用户的手账画布里存的是 `vec:<id>`，套用记录里存的是模板 id，
    // 改名或删除会让老手账的贴纸变成缺失占位、模板引用直接断链。
    //
    // 本用例失败即意味着破坏了存量用户数据的素材引用：
    // - 新增了 id → 允许，把新 id 补进下面的快照即可；
    // - 删除或改名 → 必须停下来，不能靠改快照把测试「修好」。
    const publishedStickerIds = <String>{
      // 自然
      'flower', 'sun', 'moon', 'cloud', 'rainbow', 'star', 'leaf', 'clover',
      // 美食
      'coffee', 'cake', 'icecream', 'cherry',
      'strawberry', 'watermelon', 'candy', 'donut',
      // 生活
      'book', 'camera', 'mail', 'gift', 'bow', 'candle', 'music', 'mug',
      // 可爱
      'cat', 'butterfly', 'bird', 'bear', 'heart', 'smiley', 'balloon', 'flag',
    };

    const publishedTemplateIds = <String>{
      'builtin-today',
      'builtin-daily-review',
      'builtin-reading-notes',
      'builtin-travel',
      'builtin-weekly',
      'builtin-gratitude',
    };

    test('内置矢量贴纸 id 只增，不删不改名（NFR-08）', () {
      final ids = vectorStickers.map((s) => s.id).toList();
      expect(ids.length, ids.toSet().length, reason: 'id 必须唯一，重名会让同一引用指向两张图');
      expect(
        ids.toSet(),
        containsAll(publishedStickerIds),
        reason: '少了任何一个 id，存量手账里的 vec:<id> 就会变成缺失占位',
      );
      // key 前缀同样是引用的一部分，不能顺手改。
      expect(stickerKeyVector, 'vec:');
      expect(stickerKeyImage, 'img:');
      expect(stickerKeyEmoji, 'emoji:');
    });

    test('内置模板 id 只增，不删不改名（NFR-08）', () {
      expect(
        builtinTemplateIds.length,
        builtinTemplates.length,
        reason: 'id 必须唯一',
      );
      expect(
        builtinTemplateIds,
        containsAll(publishedTemplateIds),
        reason: '少了任何一个 id，套用过该模板的手账与内置补种逻辑都会错乱',
      );
      // builtin 标志的唯一可信来源就是这份清单（FIX-02）。
      for (final id in publishedTemplateIds) {
        expect(isBuiltinTemplateId(id), isTrue);
      }
    });
  });
}

/// 把文档目录指向临时目录：StickerStore 与 Attachments 的落盘都走这里，
/// 测试不得污染真实文档目录。只在需要落盘的分组内调用。
void useTempDocuments() {
  late Directory documents;
  late Future<String> Function() previousDocs;
  late PathProviderPlatform previousPlatform;

  setUpAll(() async {
    documents = await Directory.systemTemp.createTemp('pagenote-pack-docs');
    previousDocs = StickerStore.documentsDir;
    previousPlatform = PathProviderPlatform.instance;
    StickerStore.documentsDir = () async => documents.path;
    PathProviderPlatform.instance = _TempDocuments(documents.path);
  });

  setUp(() async {
    await StickerStore.clearAll();
  });

  tearDownAll(() async {
    StickerStore.documentsDir = previousDocs;
    PathProviderPlatform.instance = previousPlatform;
    if (await documents.exists()) await documents.delete(recursive: true);
  });
}

class _TempDocuments extends PathProviderPlatform {
  _TempDocuments(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
