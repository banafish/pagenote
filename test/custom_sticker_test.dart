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
import 'package:pagenote/services/backup_restore.dart';
import 'package:pagenote/services/backup_service.dart';
import 'package:pagenote/utils/pack_cover_store.dart';
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

  test('带包导入命中去重：未分组贴纸归位回包,已挪进其它包的不被抢回（v8）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final bytes = pngOf(48, 48, seed: 6);
    final sticker = (await provider.importFromFile(fileOf(bytes, '印章.png')))!;
    expect(sticker.packId, isNull, reason: '相册导入默认未分组');

    // 未分组的贴纸随分享包导出又导回：去重命中,但归位进包而不是留在未分组。
    final pack = await provider.ensureImportedPack(name: '印章包', originId: 'pack-x');
    final again = await provider.importFromBytes(
      bytes,
      name: '印章',
      packId: pack.id,
    );
    expect(again!.id, sticker.id, reason: '同 sha1 仍是同一条记录');
    expect(again.packId, pack.id, reason: '先前散落在未分组的贴纸归位回包');
    expect(provider.stickers.length, 1, reason: '归位不是重复入库');
    expect(provider.ungroupedStickers, isEmpty);
    expect(provider.stickersOfPack(pack.id).single.id, sticker.id);

    // 归位要落库才算数：重读后仍在包里。
    final reopened = await newProvider(database: db);
    expect(reopened.byId(sticker.id)!.packId, pack.id);

    // 用户挪进其它包后再次导回：已有的归属优先于导入包的落位。
    final mine = (await provider.createPack('我的私藏'))!;
    await provider.moveStickerToPack(sticker.id, mine.id);
    final third = await provider.importFromBytes(
      bytes,
      name: '印章',
      packId: pack.id,
    );
    expect(third!.packId, mine.id, reason: '已有的归属优先于导入包的落位');
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

  test('重命名 / 删除往返，删除后文件与记录都不在（REQ-20.4）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final sticker = (await provider.importFromFile(
      fileOf(pngOf(48, 48), '原名.png'),
    ))!;
    final path = StickerStore.pathOf(sticker.id, sticker.ext);
    expect(File(path).existsSync(), isTrue);

    await provider.rename(sticker.id, '新名字');
    expect(provider.byId(sticker.id)!.name, '新名字');

    // 重新读库确认落盘。
    final reopened = await newProvider(database: db);
    expect(reopened.stickers.single.name, '新名字');

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
    // 分组字段（旧版功能）随备份清单原样往返。
    final sticker = (await provider.importFromBytes(
      pngOf(72, 72),
      name: '备份素材',
      category: '手绘',
    ))!;
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

  test('素材包全周期：建包 / 移入移出 / 解散保留素材 / 删包连素材（v7）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final a = (await provider.importFromFile(fileOf(pngOf(40, 40), '甲.png')))!;
    final b = (await provider.importFromFile(
      fileOf(pngOf(40, 40, seed: 3), '乙.png'),
    ))!;
    expect(provider.ungroupedStickers.length, 2, reason: '相册导入默认未分组');

    final pack = (await provider.createPack(' 旅行包 '))!;
    expect(pack.name, '旅行包', reason: '包名去掉首尾空白');
    await provider.moveStickerToPack(a.id, pack.id);
    await provider.moveStickerToPack(b.id, pack.id);
    expect(provider.stickersOfPack(pack.id).length, 2);
    expect(provider.ungroupedStickers, isEmpty);
    expect(provider.packById(pack.id)!.name, '旅行包');

    // 重新读库确认归属落盘。
    final reopened = await newProvider(database: db);
    expect(reopened.packs.single.id, pack.id);
    expect(reopened.byId(a.id)!.packId, pack.id);
    expect(reopened.stickersOfPack(pack.id).length, 2);

    // 移回未分组后再解散：素材与文件都保留，只剩包记录消失。
    await provider.moveStickerToPack(a.id, null);
    await provider.renamePack(pack.id, '空包');
    await provider.dissolvePack(pack.id);
    expect(provider.packs, isEmpty);
    expect(provider.byId(b.id), isNotNull, reason: '解散不动素材');
    expect(provider.byId(b.id)!.packId, isNull);
    expect(
      File(StickerStore.pathOf(b.id, b.ext)).existsSync(),
      isTrue,
      reason: '解散不动文件',
    );

    // 删包则连素材带文件一起清。
    final pack2 = (await provider.createPack('待删包'))!;
    await provider.moveStickerToPack(a.id, pack2.id);
    await provider.moveStickerToPack(b.id, pack2.id);
    await provider.deletePack(pack2.id);
    expect(provider.stickers, isEmpty);
    expect(provider.packs, isEmpty);
    expect(File(StickerStore.pathOf(a.id, a.ext)).existsSync(), isFalse);
    final afterDelete = await newProvider(database: db);
    expect(afterDelete.stickers, isEmpty);
    expect(afterDelete.packs, isEmpty);
  });

  test('ensureImportedPack：同一分享包重复导入归位到同一本地包（v7）', () async {
    final provider = await newProvider();
    final first = await provider.ensureImportedPack(
      name: '春日贴纸',
      author: '阿ban',
      originId: 'pack-abc',
    );
    final again = await provider.ensureImportedPack(
      name: '春日贴纸',
      author: '阿ban',
      originId: 'pack-abc',
    );
    expect(again.id, first.id, reason: 'originId 相同即同一包，不建重复包');
    expect(provider.packs.length, 1);
    expect(provider.packs.single.author, '阿ban');

    // 老包没有 pack.json id（originId 为 null）时不去重，各建各的。
    final legacy1 = await provider.ensureImportedPack(name: '老包');
    final legacy2 = await provider.ensureImportedPack(name: '老包');
    expect(legacy1.id, isNot(legacy2.id));
    expect(
      (await provider.ensureImportedPack(name: '  ')).name,
      '未命名素材包',
      reason: '空包名退回默认名，仍可落位',
    );
  });

  test('ensurePackOriginId：手工包首次整包导出时分配稳定分享 id 并落库（v8）', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final provider = await newProvider(database: db);
    final manual = (await provider.createPack('手工包'))!;
    expect(manual.originId, isNull, reason: '手工包在首次导出前没有分享 id');

    final first = await provider.ensurePackOriginId(manual.id);
    final second = await provider.ensurePackOriginId(manual.id);
    expect(first, startsWith('pack-'));
    expect(second, first, reason: '分配过就稳定，后续导出复用同一个 id');

    // 落了库才作数：重读后仍是同一个 id，接收方按它归位回这个包。
    final reopened = await newProvider(database: db);
    expect(await reopened.ensurePackOriginId(manual.id), first);

    // 导入来的包保持包内原 id，不会被改写。
    final imported = await provider.ensureImportedPack(
      name: '朋友包',
      originId: 'pack-friend',
    );
    expect(await provider.ensurePackOriginId(imported.id), 'pack-friend');
  });

  test('备份包带上素材包清单，恢复侧 ensurePacksExist 重建后 packId 有落位（v7）', () async {
    final provider = await newProvider();
    final sticker = (await provider.importFromFile(
      fileOf(pngOf(48, 48), '包内素材.png'),
    ))!;
    final pack = (await provider.createPack('备份的包', author: '作者'))!;
    await provider.moveStickerToPack(sticker.id, pack.id);

    final zip = await BackupService.instance.buildZip(
      entries: const [],
      templates: const [],
      customStickers: provider.stickers,
      stickerBytes: await provider.exportBytes(),
      stickerPacks: provider.packs,
    );
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.findFile('sticker_packs.json'), isNotNull, reason: '包清单入包');

    final data = BackupService.instance.parseBackup(zip);
    expect(data.stickerPacks.single.id, pack.id);
    expect(data.stickerPacks.single.author, '作者');
    expect(data.customStickers.single.packId, pack.id);

    // 恢复侧：先重建包记录再落贴纸，归属不丢（覆盖恢复路径）。
    final restored = await newProvider();
    await restored.clearAll();
    await restored.ensurePacksExist(data.stickerPacks);
    await restored.importFromBytes(
      data.stickerBytes[sticker.fileName]!,
      name: sticker.name,
      category: sticker.category,
      ext: sticker.ext,
      packId: sticker.packId,
    );
    expect(restored.packs.single.id, pack.id);
    expect(restored.stickers.single.packId, pack.id);

    // 老备份没有包清单：降级为空，贴纸全部未分组，不得抛异常。
    final legacy = await BackupService.instance.buildZip(
      entries: const [],
      templates: const [],
      customStickers: provider.stickers,
      stickerBytes: await provider.exportBytes(),
    );
    expect(
      ZipDecoder().decodeBytes(legacy).findFile('sticker_packs.json'),
      isNull,
    );
    final bare = BackupService.instance.parseBackup(legacy);
    expect(bare.stickerPacks, isEmpty);
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

  test('包封面：上传落 pack_covers/，更换与移除清理旧文件（REQ-27.2/27.3/27.8）', () async {
    final provider = await newProvider();
    final pack = (await provider.createPack('封面包'))!;

    final coverOrNull = await PackCoverStore.importFromBytes(
      pngOf(64, 64, seed: 11),
    );
    expect(coverOrNull, isNotNull);
    final cover = coverOrNull!;
    await provider.setPackCover(pack.id, cover);
    expect(provider.packById(pack.id)!.coverPath, cover);
    // 与贴纸的 stickers/ 分目录存放，不污染自定义贴纸索引。
    expect(p.basename(PackCoverStore.pathOf(cover)), cover);
    expect(
      await File(PackCoverStore.pathOf(cover)).exists(),
      isTrue,
      reason: '封面文件应真实落盘',
    );
    expect(
      p.basename(p.dirname(PackCoverStore.pathOf(cover))),
      'pack_covers',
    );

    // 更换封面：旧文件清理，DB 指向新文件。
    final nextOrNull = await PackCoverStore.importFromBytes(
      pngOf(64, 64, seed: 12),
    );
    final next = nextOrNull!;
    await provider.setPackCover(pack.id, next);
    expect(await File(PackCoverStore.pathOf(cover)).exists(), isFalse);
    expect(provider.packById(pack.id)!.coverPath, next);

    // 移除封面：置空并清理文件。
    await provider.setPackCover(pack.id, null);
    expect(provider.packById(pack.id)!.coverPath, isNull);
    expect(await File(PackCoverStore.pathOf(next)).exists(), isFalse);
  });

  test('解散与删除包时封面文件一并清理（REQ-27.8）', () async {
    final provider = await newProvider();
    final dissolved = (await provider.createPack('要解散的包'))!;
    final deleted = (await provider.createPack('要删除的包'))!;
    final coverA =
        (await PackCoverStore.importFromBytes(pngOf(48, 48, seed: 21)))!;
    final coverB =
        (await PackCoverStore.importFromBytes(pngOf(48, 48, seed: 22)))!;
    await provider.setPackCover(dissolved.id, coverA);
    await provider.setPackCover(deleted.id, coverB);

    await provider.dissolvePack(dissolved.id);
    expect(await File(PackCoverStore.pathOf(coverA)).exists(), isFalse);
    await provider.deletePack(deleted.id);
    expect(await File(PackCoverStore.pathOf(coverB)).exists(), isFalse);
  });

  test('封面尺寸闸与压缩：巨图拒收、超限压到上限内（REQ-27.4、NFR-14）', () async {
    // 单边超过解码上限的图直接拒，不做压缩挽救（NFR-06 同一套闸）。
    expect(await PackCoverStore.importFromBytes(pngOf(8600, 20)), isNull);
    // 长边超 1024 的正常图压缩落盘，长边进上限。
    final stored =
        (await PackCoverStore.importFromBytes(pngOf(2000, 1000)))!;
    final saved = await File(PackCoverStore.pathOf(stored)).readAsBytes();
    final decoded = img.decodeImage(saved)!;
    expect(decoded.width, lessThanOrEqualTo(PackCoverStore.maxEdge));
    expect(decoded.height, lessThanOrEqualTo(PackCoverStore.maxEdge));
  });

  test('备份带包封面：pack_covers/ 入包，恢复按文件名重映射（REQ-27.7）', () async {
    final provider = await newProvider();
    final pack = (await provider.createPack('有封面的包'))!;
    await provider.importFromBytes(
      pngOf(30, 30, seed: 31),
      name: '贴纸',
      packId: pack.id,
    );
    final cover =
        (await PackCoverStore.importFromBytes(pngOf(64, 64, seed: 32)))!;
    await provider.setPackCover(pack.id, cover);

    final zip = await BackupService.instance.buildZip(
      entries: const [],
      templates: const [],
      customStickers: provider.stickers,
      stickerBytes: await provider.exportBytes(),
      stickerPacks: provider.packs,
      packCoverBytes: await provider.exportCoverBytes(),
    );
    expect(
      ZipDecoder().decodeBytes(zip).findFile('pack_covers/$cover'),
      isNotNull,
      reason: '封面文件入包',
    );
    final data = BackupService.instance.parseBackup(zip);
    expect(data.packCoverBytes.keys, {cover});

    // 覆盖恢复：包记录重建、封面按落盘后的文件名重映射、贴纸归位。
    final restored = await newProvider();
    final counts = await restoreStickerAssets(restored, data, overwrite: true);
    expect(counts.saved, 1);
    final restoredPack = restored.packById(pack.id);
    expect(restoredPack, isNotNull);
    expect(restoredPack!.coverPath, isNotNull, reason: '封面应恢复');
    expect(
      await File(PackCoverStore.pathOf(restoredPack.coverPath!)).exists(),
      isTrue,
    );

    // 老备份没有 pack_covers/：恢复后封面为空，回落占位样式，不得抛异常。
    final legacy = BackupService.instance.parseBackup(
      await BackupService.instance.buildZip(
        entries: const [],
        templates: const [],
        customStickers: provider.stickers,
        stickerBytes: await provider.exportBytes(),
        stickerPacks: provider.packs,
      ),
    );
    final bareRestored = await newProvider();
    await restoreStickerAssets(bareRestored, legacy, overwrite: true);
    expect(bareRestored.packById(pack.id)!.coverPath, isNull);
  });
}
