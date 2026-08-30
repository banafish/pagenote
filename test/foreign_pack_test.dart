import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/services/foreign_pack_service.dart';
import 'package:pagenote/services/share_pack_service.dart';
import 'package:pagenote/utils/sticker_store.dart';
// ignore: depend_on_referenced_packages
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'share_pack_test.dart' show useTempDocuments;

/// 外部素材包兼容导入（REQ-29）：免抠图 zip 等外部压缩包自动转换成
/// 纯贴纸包，复用分享包的预览与落库链路；拾页自己的包与备份包不受影响。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---------------- 构构件 ----------------

  Uint8List pngOf(int seed) {
    final image = img.Image(width: 8, height: 8, numChannels: 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        image.setPixelRgba(x, y, (x * 9 + seed) % 256, y * 7 % 256, seed, 255);
      }
    }
    return img.encodePng(image);
  }

  Uint8List jpegOf(int seed) {
    final image = img.Image(width: 8, height: 8, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(seed * 30 % 256, 120, 160));
    return Uint8List.fromList(img.encodeJpg(image));
  }

  ArchiveFile bytesFile(String name, List<int> bytes) =>
      ArchiveFile.bytes(name, Uint8List.fromList(bytes));

  Uint8List zipOf(List<ArchiveFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// 断言抛出的是给用户看的中文提示（REQ-29.5）。
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

  // ================= 自动识别与转换 =================

  group('外部包识别与转换（REQ-29.1）', () {
    test('免抠图 zip 转成纯贴纸包：素材名来自文件名，包名来自压缩包名', () {
      final cat = pngOf(1);
      final tape = jpegOf(2);
      final bytes = zipOf([
        bytesFile('手绘小猫.png', cat),
        bytesFile('格纹胶带.jpg', tape),
        bytesFile('说明.txt', utf8.encode('本包素材仅供手账拼贴使用')),
      ]);

      final pack = SharePackService.instance.parsePackAuto(
        bytes,
        sourceName: '秋日贴纸合集.zip',
      );

      expect(pack.isForeign, isTrue, reason: '没有拾页格式特征，走外部包转换');
      expect(pack.templates, isEmpty);
      expect(pack.stickers, isNotEmpty);
      expect(pack.name, '秋日贴纸合集', reason: '包名取来源文件名主干');
      expect(pack.author, '');
      expect(pack.packId, startsWith('foreign-'));
      // 素材名 = 文件名主干（去扩展名），扩展名保留真实格式。
      final byName = {for (final s in pack.stickers) s.name: s};
      expect(byName.keys.toSet(), {'手绘小猫', '格纹胶带'});
      expect(byName['手绘小猫']!.ext, '.png');
      expect(byName['格纹胶带']!.ext, '.jpg');
      // 字节按 `<sha1><ext>` 索引，与贴纸落盘命名对齐（REQ-20.2），
      // 导入页据此逐张取字节。
      expect(
        pack.stickerBytes.keys.toSet(),
        {
          '${StickerStore.idOf(cat)}.png',
          '${StickerStore.idOf(tape)}.jpg',
        },
      );
      expect(pack.stickerBytes['${StickerStore.idOf(cat)}.png'], cat);
      // 非图片条目不进素材清单。
      expect(pack.stickers.length, 2);
    });

    test('顶层目录名兜底包名，子目录名作旧分组字段', () {
      final a = pngOf(3);
      final b = pngOf(4);
      final bytes = zipOf([
        bytesFile('秋日贴纸/风景/a.png', a),
        bytesFile('秋日贴纸/人物/b.png', b),
      ]);

      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.name, '秋日贴纸', reason: '没有来源文件名时用唯一的顶层目录名');
      final categories = {for (final s in pack.stickers) s.name: s.category};
      expect(categories['a'], '风景', reason: '直接子目录名透传给旧分组字段');
      expect(categories['b'], '人物');
    });

    test('根目录平铺的图退回默认分组', () {
      final bytes = zipOf([bytesFile('a.png', pngOf(5))]);
      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.stickers.single.category, '我的');
    });

    test('同一张图重复出现按内容去重（REQ-20.2 同一套语义）', () {
      final same = pngOf(6);
      final bytes = zipOf([
        bytesFile('风景/01.png', same),
        bytesFile('备用/01.png', same),
      ]);
      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.stickers, hasLength(1));
      expect(pack.stickerBytes, hasLength(1));
    });

    test('系统垃圾条目与非图片文件全部忽略', () {
      final a = pngOf(7);
      final bytes = zipOf([
        bytesFile('贴纸/01.png', a),
        bytesFile('__MACOSX/贴纸/._01.png', pngOf(8)),
        bytesFile('贴纸/.DS_Store', const [1, 2, 3]),
        bytesFile('Thumbs.db', const [4, 5]),
        bytesFile('desktop.ini', const [6]),
        bytesFile('.hidden/secret.png', pngOf(9)),
        bytesFile('readme.md', utf8.encode('# 素材包')),
      ]);
      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.stickers.map((s) => s.name), ['01']);
    });

    test('嵌套 zip 展开后继续扫描，内层坏条目跳过不拒包', () {
      final a = pngOf(10);
      final inner = zipOf([
        bytesFile('../evil.png', pngOf(11)),
        bytesFile('内层贴纸/02.png', a),
      ]);
      final outer = zipOf([
        bytesFile('inner.zip', inner),
        bytesFile('外层直接放/03.png', pngOf(12)),
      ]);

      final pack = SharePackService.instance.parsePackAuto(outer);
      final names = pack.stickers.map((s) => s.name).toSet();
      expect(names, {'02', '03'}, reason: '嵌套包要展开，`..` 条目要跳过');
      expect(
        names.any((n) => n.contains('evil')),
        isFalse,
        reason: '路径穿越条目一个都不能进清单',
      );
    });
  });

  // ================= 自动分流（REQ-29.2） =================

  group('入口自动分流', () {
    test('拾页分享包不受影响：模板原样解析（REQ-21 兼容回归）', () async {
      final cat = pngOf(13);
      final catSticker = CustomSticker(
        id: StickerStore.idOf(cat),
        name: '手绘猫',
      );
      final native = await SharePackService.instance.buildPack(
        packName: '拾页的包',
        author: '阿拾',
        templates: const [],
        stickers: [catSticker],
        stickerBytes: {catSticker.fileName: cat},
      );

      final pack = SharePackService.instance.parsePackAuto(
        native,
        sourceName: 'whatever.zip',
      );
      expect(pack.isForeign, isFalse);
      expect(pack.name, '拾页的包', reason: '包名来自 pack.json 而不是来源文件名');
      expect(pack.author, '阿拾');
      expect(pack.packId, startsWith('pack-'));
      expect(pack.stickers.single.name, '手绘猫');
    });

    test('别的应用恰好也叫 pack.json：仍按外部包兜底转换', () {
      final a = pngOf(14);
      final bytes = zipOf([
        bytesFile('pack.json', utf8.encode('{"app": "another-app"}')),
        bytesFile('assets/01.png', a),
      ]);
      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.isForeign, isTrue);
      expect(pack.stickers, hasLength(1));
    });

    test('拾页备份包给出指路提示，不把照片导成贴纸', () {
      final bytes = zipOf([
        bytesFile('entries.json', utf8.encode('{"app": "pagenote"}')),
        bytesFile('attachments/trip.jpg', jpegOf(15)),
      ]);
      expectReadable(
        () => SharePackService.instance.parsePackAuto(bytes),
        keyword: '备份',
      );
    });

    test('包内没有图片：给可读的中文错误而不是静默空包', () {
      final bytes = zipOf([
        bytesFile('readme.txt', utf8.encode('只有文字')),
        bytesFile('字体.ttf', List.generate(64, (i) => i)),
      ]);
      expectReadable(
        () => SharePackService.instance.parsePackAuto(bytes),
        keyword: '图片',
      );
    });

    test('RAR / 7z 给出明确指引（REQ-29.5）', () {
      const rar = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];
      expectReadable(
        () => SharePackService.instance.parsePackAuto(Uint8List.fromList([
          ...rar,
          ...List.filled(64, 0),
        ])),
        keyword: 'RAR',
      );
      const sevenZip = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C];
      expectReadable(
        () => SharePackService.instance.parsePackAuto(Uint8List.fromList([
          ...sevenZip,
          ...List.filled(64, 0),
        ])),
        keyword: '7z',
      );
    });

    test('损坏的 zip 仍是可读中文错误（REQ-21.10 兼容回归）', () {
      expectReadable(
        () => SharePackService.instance.parsePackAuto(
          Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
      );
    });
  });

  // ================= 条目名编码还原（REQ-29.3） =================

  group('文件名编码还原', () {
    test('GBK 乱码（archive 退回的逐字节形式）还原成中文', () {
      final gbkBytes = gbk.encode('秋日贴纸');
      final mojibake = String.fromCharCodes(gbkBytes);
      expect(mojibake, isNot('秋日贴纸'), reason: '前置：archive 读 GBK 名就是这种乱码');
      expect(ForeignPackService.recoverEntryName(mojibake), '秋日贴纸');
    });

    test('百分号编码的文件名还原成中文', () {
      expect(
        ForeignPackService.recoverEntryName('%E7%A7%8B%E6%97%A5.png'.replaceAll('.png', '')),
        '秋日',
      );
    });

    test('正常 UTF-8 中文名、ASCII 名原样返回，不被误改', () {
      expect(ForeignPackService.recoverEntryName('秋日贴纸'), '秋日贴纸');
      expect(ForeignPackService.recoverEntryName('sticker_01'), 'sticker_01');
      // 拿不准的字节序列宁可不还原，也不能抛异常。
      expect(
        ForeignPackService.recoverEntryName(String.fromCharCodes([0x81, 0x40])),
        isA<String>(),
      );
    });

    test('百分号编码的条目名在真实 zip 里还原（端到端）', () {
      final bytes = zipOf([bytesFile('%E7%A7%8B%E6%97%A5.png', pngOf(16))]);
      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.stickers.single.name, '秋日');
    });

    test('真实 WinRAR 式 GBK 打包的 zip 端到端（fixture 回归）', () {
      // test/fixtures/foreign_gbk.zip：手工构造的无 UTF-8 标志 zip，
      // 条目名为原始 GBK 字节——Windows 压缩工具打包中文素材包的真实形态。
      final fixture = File(
        'test/fixtures/foreign_gbk.zip',
      ).readAsBytesSync();
      final pack = SharePackService.instance.parsePackAuto(fixture);

      expect(pack.isForeign, isTrue);
      expect(pack.name, '贴纸素材', reason: '唯一顶层目录名兜底包名，且完成 GBK 还原');
      final byName = {for (final s in pack.stickers) s.name: s};
      expect(byName.keys.toSet(), {'可爱小猫', '柴犬'});
      expect(byName['可爱小猫']!.category, '贴纸素材', reason: '目录段同样还原');
      expect(pack.stickers, hasLength(2), reason: '__MACOSX 垃圾条目被过滤');
    });
  });

  // ================= 落库与重复导入（REQ-29.4） =================

  group('落库与重复导入', () {
    useTempDocuments();

    Future<CustomStickerProvider> newProvider() async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final provider = CustomStickerProvider(database: db);
      await provider.load();
      return provider;
    }

    test('逐张 importFromBytes 落库，id 与解析端的内容寻址一致', () async {
      final provider = await newProvider();
      final a = pngOf(17);
      final bytes = zipOf([bytesFile('小猫.png', a)]);
      final pack = SharePackService.instance.parsePackAuto(bytes);

      final ids = <String>[];
      for (final s in pack.stickers) {
        final saved = await provider.importFromBytes(
          pack.stickerBytes[s.fileName]!,
          name: s.name,
          category: s.category,
          ext: s.ext,
          packId: (await provider.ensureImportedPack(
            name: pack.name,
            author: pack.author,
            originId: pack.packId,
          )).id,
        );
        if (saved != null) ids.add(saved.id);
      }

      expect(ids, [StickerStore.idOf(a)], reason: '字节未超限，sha1 原样成为贴纸 id');
      expect(provider.packs.single.name, '外部素材包', reason: '没有来源文件名时用兜底包名');
      expect(provider.packs.single.originId, startsWith('foreign-'));
      expect(provider.stickersOfPack(provider.packs.single.id), hasLength(1));
    });

    test('同一个外部压缩包重复导入归位到同一个包', () async {
      final provider = await newProvider();
      final a = pngOf(18);
      final zipBytes = zipOf([bytesFile('01.png', a)]);

      final first = SharePackService.instance.parsePackAuto(
        zipBytes,
        sourceName: '秋日贴纸.zip',
      );
      final second = SharePackService.instance.parsePackAuto(
        zipBytes,
        sourceName: '改名之后.zip',
      );

      expect(first.packId, second.packId, reason: '身份只由内容决定，跟文件名无关');
      final pack = await provider.ensureImportedPack(
        name: first.name,
        originId: first.packId,
      );
      final again = await provider.ensureImportedPack(
        name: second.name,
        originId: second.packId,
      );
      expect(again.id, pack.id, reason: '同一个包不重复建');
      expect(pack.name, '秋日贴纸', reason: '首次导入的包名保留');
    });

    test('超限的图在落盘闸被跳过，其余素材照常导入（NFR-06 兼容回归）', () async {
      final provider = await newProvider();
      // 头部声明 20000×20000 的 PNG：解包端识别不出真假，落盘闸负责拦下。
      final raw = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4, numChannels: 4)),
      );
      final view = ByteData.sublistView(raw);
      view.setUint32(16, 20000);
      view.setUint32(20, 20000);
      final good = pngOf(19);
      final bytes = zipOf([
        bytesFile('bomb.png', raw),
        bytesFile('good.png', good),
      ]);

      final pack = SharePackService.instance.parsePackAuto(bytes);
      expect(pack.stickers, hasLength(2), reason: '解包只搬运字节，不替落盘闸做主');

      final saved = <String>[];
      for (final s in pack.stickers) {
        final sticker = await provider.importFromBytes(
          pack.stickerBytes[s.fileName]!,
          name: s.name,
          ext: s.ext,
        );
        if (sticker != null) saved.add(sticker.name);
      }
      expect(saved, ['good'], reason: '一张坏图不能中断整包导入');
    });
  });
}
