import 'dart:io';
import 'dart:typed_data';

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
    final used = (await provider.importFromFile(fileOf(pngOf(40, 40), '在用.png')))!;
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
}
