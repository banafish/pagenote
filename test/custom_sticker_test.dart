import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/custom_sticker_provider.dart';
import 'package:pagenote/services/backup_service.dart';
import 'package:pagenote/utils/sticker_store.dart';

void main() {
  late Directory documents;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    documents = await Directory.systemTemp.createTemp('pagenote-sticker-docs');
    // 落盘全部改指临时目录，不污染真实文档目录。
    StickerStore.documentsDir = () async => documents.path;
  });

  setUp(() async {
    await StickerStore.clearAll();
  });

  tearDown(() {
    // 全局单例，不复位会污染其它用例的渲染判定。
    CustomStickerIndex.instance.replaceAll({}, {});
  });

  tearDownAll(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  /// 每个用例一套独立的库，用完即关。
  Future<CustomStickerProvider> newProvider({AppDatabase? database}) async {
    final db = database ?? AppDatabase.inMemory();
    if (database == null) addTearDown(db.close);
    final provider = CustomStickerProvider(database: db);
    await provider.load();
    return provider;
  }

  /// 生成一张带渐变纹理的 PNG（避免依赖外部素材文件）。
  Uint8List pngOf(int width, int height, {int seed = 0}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(
          x,
          y,
          (x * 3 + seed) % 256,
          (y * 5 + seed) % 256,
          (x + y + seed) % 256,
          255,
        );
      }
    }
    return img.encodePng(image);
  }

  XFile fileOf(Uint8List bytes, String name) =>
      XFile.fromData(bytes, path: p.join(Directory.systemTemp.path, name));

  /// 白底 + 中心色块的 PNG，用于去白底断言（REQ-20.3）。
  Uint8List whiteBlockPng(int size) {
    final image = img.Image(width: size, height: size, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      image,
      x1: size ~/ 4,
      y1: size ~/ 4,
      x2: size - size ~/ 4 - 1,
      y2: size - size ~/ 4 - 1,
      color: img.ColorRgba8(220, 90, 90, 255),
    );
    return img.encodePng(image);
  }

  /// 噪点 PNG：长边不超限但体积超 2MB，用来打中按体积压缩那条分支。
  Uint8List noisePng(int size) {
    final random = math.Random(7);
    final image = img.Image(width: size, height: size, numChannels: 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        image.setPixelRgba(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
          255,
        );
      }
    }
    return img.encodePng(image);
  }

  Future<List<File>> storedFiles() async {
    final dir = await StickerStore.ensureDir();
    return dir.listSync().whereType<File>().toList();
  }

  test('同一图片导入两次只落一条记录一个文件（REQ-20.2）', () async {
    final provider = await newProvider();
    final bytes = pngOf(64, 64);

    final first = await provider.importFromFile(fileOf(bytes, '小猫.png'));
    final second = await provider.importFromFile(fileOf(bytes, '小猫副本.png'));

    expect(first, isNotNull);
    expect(second!.id, first!.id, reason: '内容寻址：sha1 相同即同一素材');
    expect(provider.stickers.length, 1);
    expect(provider.stickers.single.name, '小猫', reason: '沿用首次导入的名字');
    expect((await storedFiles()).length, 1);

    // 换一张图片才会新增。
    final other = await provider.importFromFile(
      fileOf(pngOf(64, 64, seed: 9), '小狗.png'),
    );
    expect(other!.id, isNot(first.id));
    expect(provider.stickers.length, 2);
    expect((await storedFiles()).length, 2);
  });

  test('超限图片导入后自动压缩到长边 1024px / 2MB 内（REQ-20.5）', () async {
    final provider = await newProvider();
    final sticker = await provider.importFromFile(
      fileOf(pngOf(2400, 800), '大图.png'),
    );

    expect(sticker, isNotNull);
    final bytes = await StickerStore.readBytes(sticker!.id, sticker.ext);
    expect(bytes, isNotNull);
    expect(bytes!.length, lessThanOrEqualTo(StickerStore.maxBytes));

    final decoded = img.decodeImage(bytes)!;
    expect(decoded.width, lessThanOrEqualTo(StickerStore.maxEdge));
    expect(decoded.height, lessThanOrEqualTo(StickerStore.maxEdge));
    expect(decoded.width, StickerStore.maxEdge, reason: '长边缩到上限而非更小');
    expect(decoded.height, closeTo(1024 * 800 / 2400, 1), reason: '等比缩放');
  });

  test('重命名 / 分组 / 删除往返，删除后文件与记录都不在（REQ-20.4）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final sticker = (await provider.importFromFile(
      fileOf(pngOf(48, 48), '原名.png'),
    ))!;
    final path = StickerStore.pathOf(sticker.id, sticker.ext);
    expect(File(path).existsSync(), isTrue);

    await provider.rename(sticker.id, '新名字');
    await provider.setCategory(sticker.id, '旅行');
    expect(provider.byId(sticker.id)!.name, '新名字');
    expect(provider.categories, ['旅行']);

    // 重新读库确认落盘。
    final reopened = await newProvider(database: db);
    expect(reopened.stickers.single.name, '新名字');
    expect(reopened.stickers.single.category, '旅行');

    await reopened.delete(sticker.id);
    expect(reopened.stickers, isEmpty);
    expect(reopened.byId(sticker.id), isNull);
    expect(File(path).existsSync(), isFalse, reason: '文件一并删除');

    final afterDelete = await newProvider(database: db);
    expect(afterDelete.stickers, isEmpty);
  });

  test('被手账或模板引用的素材判定为占用（REQ-20.4 删除二次确认）', () async {
    final provider = await newProvider();
    final used = (await provider.importFromFile(
      fileOf(pngOf(40, 40), '在用.png'),
    ))!;
    final free = (await provider.importFromFile(
      fileOf(pngOf(40, 40, seed: 3), '闲置.png'),
    ))!;

    final entry = JournalEntry(
      id: 'e-1',
      date: '2026-08-19',
      title: '贴了自定义贴纸',
      content: '正文',
      canvas: JournalCanvas(
        elements: [StickerElement(key: '$stickerKeyImage${used.id}')],
      ),
      createdAt: DateTime(2026, 8, 19),
      updatedAt: DateTime(2026, 8, 19),
    );
    final template = JournalTemplate(
      id: 'tpl-1',
      name: '带自定义贴纸的模板',
      canvas: JournalCanvas(
        elements: [StickerElement(key: '$stickerKeyImage${free.id}')],
      ),
    );

    expect(provider.isReferenced(used.id, [entry], []), isTrue);
    expect(provider.isReferenced(free.id, [entry], []), isFalse);
    expect(provider.isReferenced(free.id, [], [template]), isTrue);
    expect(provider.isReferenced(used.id, [], []), isFalse);
  });

  test('导入后全局索引可取到路径，渲染端据此判定素材存在（REQ-20.1）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final sticker = (await provider.importFromFile(
      fileOf(pngOf(56, 56), '索引.png'),
    ))!;

    final path = CustomStickerIndex.instance.pathOf(sticker.id);
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(p.isWithin(documents.path, path), isTrue, reason: '落在文档目录内');
    expect(CustomStickerIndex.instance.nameOf(sticker.id), '索引');
    expect(isKnownStickerKey(sticker.stickerKey), isTrue);

    // 重启后由 load 重建索引。
    CustomStickerIndex.instance.replaceAll({}, {});
    expect(isKnownStickerKey(sticker.stickerKey), isFalse);
    await newProvider(database: db);
    expect(CustomStickerIndex.instance.pathOf(sticker.id), path);
    expect(isKnownStickerKey(sticker.stickerKey), isTrue);

    // 删除后索引同步失效，引用处退化为缺失占位（FIX-03）。
    await provider.delete(sticker.id);
    expect(CustomStickerIndex.instance.pathOf(sticker.id), isNull);
    expect(isKnownStickerKey(sticker.stickerKey), isFalse);
  });

  test('备份包带上自定义贴纸清单与位图，解析回程可还原（REQ-20.6）', () async {
    final provider = await newProvider();
    final sticker = (await provider.importFromFile(
      fileOf(pngOf(72, 72), '备份素材.png'),
    ))!;
    await provider.setCategory(sticker.id, '手绘');
    final saved = (await StickerStore.readBytes(sticker.id, sticker.ext))!;

    final entry = JournalEntry(
      id: 'e-backup',
      date: '2026-08-19',
      title: '带自定义贴纸',
      content: '正文',
      canvas: JournalCanvas(
        elements: [StickerElement(key: sticker.stickerKey)],
      ),
      createdAt: DateTime(2026, 8, 19),
      updatedAt: DateTime(2026, 8, 19),
    );

    // 自动备份与手动导出走的是同一个 buildZip，取值必须带上这两个参数。
    final zip = await BackupService.instance.buildZip(
      entries: [entry],
      templates: const [],
      customStickers: provider.stickers,
      stickerBytes: await provider.exportBytes(),
    );

    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.findFile('stickers.json'), isNotNull, reason: '清单入包');
    expect(
      archive.findFile('stickers/${sticker.fileName}'),
      isNotNull,
      reason: '位图放在 stickers/ 下，文件名即 <sha1><ext>',
    );

    final data = BackupService.instance.parseBackup(zip);
    expect(data.customStickers.single.id, sticker.id);
    expect(data.customStickers.single.name, '备份素材');
    expect(data.customStickers.single.category, '手绘');
    expect(data.stickerBytes[sticker.fileName], saved, reason: '字节原样回程');
    expect(
      data.entries.single.canvas!.stickerKeys,
      contains(sticker.stickerKey),
      reason: '引用与素材同包，导入后不成占位框',
    );

    // 漏传这两个参数就是 REQ-20.6 那个 bug 的形态：包里没有贴纸，
    // 解析端降级为空（旧备份同此路径，不得抛异常）。
    final without = await BackupService.instance.buildZip(
      entries: [entry],
      templates: const [],
    );
    expect(ZipDecoder().decodeBytes(without).findFile('stickers.json'), isNull);
    final bare = BackupService.instance.parseBackup(without);
    expect(bare.customStickers, isEmpty);
    expect(bare.stickerBytes, isEmpty);
  });

  test('去白底导入：白底透明、色块保留，与原图各成一份素材（REQ-20.3）', () async {
    final provider = await newProvider();
    final raw = whiteBlockPng(64);

    // 面板侧的真实链路：先抠白，再包成内存 XFile 走同一条压缩落盘。
    final cut = await StickerStore.removeWhiteBackground(raw);
    final cutSticker = (await provider.importFromFile(
      XFile.fromData(cut, path: '印章去白.png', mimeType: 'image/png'),
    ))!;
    final plain = (await provider.importFromFile(fileOf(raw, '印章.png')))!;

    expect(cutSticker.id, isNot(plain.id), reason: '抠白改了内容，是另一份素材');
    expect(provider.stickers.length, 2);
    expect((await storedFiles()).length, 2);

    final decoded = img.decodeImage(
      (await StickerStore.readBytes(cutSticker.id, cutSticker.ext))!,
    )!;
    for (final xy in const [
      [0, 0],
      [63, 0],
      [0, 63],
      [63, 63],
    ]) {
      expect(decoded.getPixel(xy[0], xy[1]).a, 0, reason: '四角白底抠成全透明');
    }
    final center = decoded.getPixel(32, 32);
    expect(center.a, 255, reason: '中心色块保持不透明');
    expect(center.r, 220);
    expect(center.g, 90);

    // 未勾选去白底的那份四角仍是不透明白，两条链路互不干扰。
    final origin = img.decodeImage(
      (await StickerStore.readBytes(plain.id, plain.ext))!,
    )!;
    expect(origin.getPixel(0, 0).a, 255);
    expect(origin.getPixel(0, 0).r, 255);
  });

  test('压缩判定：超限图被压到上限内，小图原样落盘（REQ-20.5）', () async {
    final provider = await newProvider();

    /// 面板提示「已压缩为 W×H」所依据的信息：数据层未回传结构体，
    /// 只能比对源字节与落盘结果反推，此处按同一口径断言。
    Future<({bool shrunk, int width, int height, int bytes})> receiptOf(
      Uint8List source,
      String name,
    ) async {
      final sticker = await provider.importFromFile(fileOf(source, name));
      expect(sticker, isNotNull, reason: '$name 应能解码');
      final saved = (await StickerStore.readBytes(sticker!.id, sticker.ext))!;
      final after = img.decodeImage(saved)!;
      final before = img.decodeImage(source)!;
      return (
        shrunk: after.width != before.width || after.height != before.height,
        width: after.width,
        height: after.height,
        bytes: saved.length,
      );
    }

    final long = await receiptOf(pngOf(2000, 1200), '超长边.png');
    expect(long.shrunk, isTrue);
    expect(long.width, lessThanOrEqualTo(StickerStore.maxEdge));
    expect(long.height, lessThanOrEqualTo(StickerStore.maxEdge));
    expect(long.bytes, lessThanOrEqualTo(StickerStore.maxBytes));

    // 长边没超但体积超 2MB，也要压（噪点图压缩率低，正好打中这条分支）。
    final source = noisePng(900);
    expect(
      source.length,
      greaterThan(StickerStore.maxBytes),
      reason: '用例前提：这张噪点图本身超 2MB',
    );
    final heavy = await receiptOf(source, '噪点.png');
    expect(heavy.shrunk, isTrue);
    expect(heavy.width, lessThan(900));
    expect(heavy.bytes, lessThanOrEqualTo(StickerStore.maxBytes));

    final small = await receiptOf(pngOf(200, 120, seed: 5), '小图.png');
    expect(small.shrunk, isFalse, reason: '未超限不动尺寸');
    expect(small.width, 200);
    expect(small.height, 120);
    expect(small.bytes, lessThanOrEqualTo(StickerStore.maxBytes));
  });

  test('包内伪造的扩展名不能写出素材目录（NFR-06 路径消毒）', () async {
    // stickers.json 里的 ext 与 zip 条目名是两回事，不经条目名校验，
    // 直接拼进文件名就能用 ../ 逃出 stickers/ 覆盖任意文件。
    final provider = await newProvider();
    final bytes = pngOf(80, 60, seed: 9);
    final saved = await provider.importFromBytes(
      bytes,
      name: '越权素材',
      ext: '/../../越权.png',
    );

    expect(saved, isNotNull, reason: '扩展名非法只降级为 .png，不该整张丢弃');
    expect(saved!.ext, '.png');
    // 落盘位置必须仍在素材目录内，文档目录里不能凭空多出文件。
    final stickerDir = await StickerStore.ensureDir();
    final escaped = File(p.join(documents.path, '越权.png'));
    expect(await escaped.exists(), isFalse, reason: '不得写到素材目录之外');
    expect(
      p.equals(
        p.dirname(StickerStore.pathOf(saved.id, saved.ext)),
        stickerDir.path,
      ),
      isTrue,
    );
    expect(
      await File(StickerStore.pathOf(saved.id, saved.ext)).exists(),
      isTrue,
    );

    // 读路径与写路径用同一套消毒，存量记录里的脏 ext 也能取回字节。
    expect(await StickerStore.readBytes(saved.id, '/../../越权.png'), isNotNull);
    expect(StickerStore.safeExt('.PNG'), '.PNG');
    expect(StickerStore.safeExt(''), '.png');
    expect(StickerStore.safeExt(r'..\evil'), '.png');
  });
}
