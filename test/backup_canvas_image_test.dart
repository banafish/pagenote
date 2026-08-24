import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/services/backup_service.dart';
import 'package:pagenote/utils/attachments.dart';

class _TempDocuments extends PathProviderPlatform {
  _TempDocuments(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory documents;
  late Directory sourceImages;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    documents = await Directory.systemTemp.createTemp('pagenote-cnv-docs');
    sourceImages = await Directory.systemTemp.createTemp('pagenote-cnv-src');
    PathProviderPlatform.instance = _TempDocuments(documents.path);
  });

  tearDownAll(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
    if (await sourceImages.exists()) {
      await sourceImages.delete(recursive: true);
    }
  });

  /// 一张真实源图片，返回其本机绝对路径。
  Future<String> makeSourceImage(String name, List<int> bytes) async {
    final file = File(p.join(sourceImages.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  JournalEntry entryWithCanvas(List<String> imagePaths) {
    final canvas = JournalCanvas(elements: [
      TextElement(text: '标题', role: 'title'),
      for (final path in imagePaths) ImageElement(path: path),
    ]);
    return JournalEntry(
      id: 'e1',
      date: '2026-08-20',
      title: '标题',
      content: '正文',
      images: imagePaths.take(1).toList(),
      canvas: canvas,
      createdAt: DateTime(2026, 8, 20),
      updatedAt: DateTime(2026, 8, 20),
    );
  }

  test('导出净化：条目画布只留纯文件名，不含本机绝对路径', () async {
    final imgPath = await makeSourceImage('aaa111.jpg', [1, 2, 3]);
    final zipBytes = await BackupService.instance.buildZip(
      entries: [entryWithCanvas([imgPath])],
      templates: [],
    );

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('entries.json')!.content as List<int>),
    ) as Map<String, Object?>;
    final entryMap = (manifest['entries'] as List).single
        as Map<String, Object?>;
    final canvasJson = entryMap['canvas'] as String;

    expect(canvasJson.contains(sourceImages.path), isFalse,
        reason: '画布序列化不得携带本机绝对路径（跨平台重映射会整片失联）');
    expect(canvasJson, contains('aaa111.jpg'), reason: '打包成功的照片保留纯文件名');
    expect(archive.findFile('attachments/aaa111.jpg'), isNotNull);
  });

  test('完整往返：images 列表与画布照片导入后全部落地并重映射', () async {
    final imgA = await makeSourceImage('aaa222.jpg', [1, 2, 3]);
    final imgB = await makeSourceImage('bbb333.png', [4, 5, 6]);
    final zipBytes = await BackupService.instance.buildZip(
      entries: [entryWithCanvas([imgA, imgB])],
      templates: [],
    );

    final data = BackupService.instance.parseBackup(zipBytes);
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.importBackup(data, overwrite: true);

    final restored = provider.entries.single;
    for (final path in restored.images) {
      expect(File(path).existsSync(), isTrue);
      expect(path.startsWith(documents.path), isTrue, reason: '应落在新的附件目录');
    }
    final canvasPaths = restored.canvas!.images.map((e) => e.path).toList();
    expect(canvasPaths.length, 2);
    for (final path in canvasPaths) {
      expect(path.contains(sourceImages.path), isFalse,
          reason: '导入后不得残留导出机的路径');
      expect(File(path).existsSync(), isTrue, reason: '画布照片应已落地');
    }
    await db.close();
  });

  test('旧版备份跨平台导入：Windows 绝对路径的画布照片也能重映射', () async {
    // 旧版 app 导出的包里，条目 images 字段已是纯文件名，
    // 但画布内仍是导出机的绝对路径。POSIX 端 p.basename 不认反斜杠，
    // 曾导致 Windows 备份导入手机后画布照片全部失联。
    const fileName = 'legacy444.jpg';
    final manifest = {
      'app': 'pagenote',
      'format': BackupService.formatVersion,
      'exportedAt': '2026-08-01T00:00:00.000',
      'entries': [
        {
          'id': 'legacy-1',
          'date': '2026-08-01',
          'title': '旧备份',
          'content': '',
          'mood': null,
          'weather': null,
          'tags': '',
          'images': fileName,
          'activities': '',
          'paper': '',
          'stickers': '',
          'canvas': jsonEncode({
            'id': 'cv1',
            'paper': 'plain',
            'h': 4 / 3,
            'elements': [
              {
                'id': 'el1',
                'x': 0.5,
                'y': 0.5,
                'w': 0.4,
                'h': 0.3,
                'r': 0.0,
                'o': 1.0,
                't': 'image',
                'p': r'C:\Users\someone\Pictures\camera\' + fileName,
                'm': 'none',
                'rad': 0.03,
              },
            ],
          }),
          'isQuickNote': 0,
          'isFavorite': 0,
          'createdAt':
              DateTime(2026, 8, 1).millisecondsSinceEpoch,
          'updatedAt':
              DateTime(2026, 8, 1).millisecondsSinceEpoch,
          'deletedAt': null,
        },
      ],
      'templates': <Object?>[],
    };
    final archive = Archive()
      ..addFile(ArchiveFile.bytes(
        'entries.json',
        Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      ))
      ..addFile(ArchiveFile.bytes(
        'attachments/$fileName',
        Uint8List.fromList([7, 8, 9]),
      ));
    final zipBytes = ZipEncoder().encodeBytes(archive);

    final data = BackupService.instance.parseBackup(zipBytes);
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.importBackup(data, overwrite: true);

    final restored = provider.entries.single;
    final canvasPath = restored.canvas!.images.single.path;
    expect(canvasPath.contains('someone'), isFalse,
        reason: '导出机伪造的路径必须被按文件名重映射掉');
    expect(File(canvasPath).existsSync(), isTrue, reason: '画布照片按文件名落地');
    await db.close();
  });

  test('附件字节缺失时画布保留原路径不误清（同机重复导入场景）', () async {
    final data = BackupData(entries: [
      entryWithCanvas([])..canvas!.elements.add(ImageElement(path: '/gone/x.jpg')),
    ], templates: [], attachments: {});
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.importBackup(data, overwrite: true);

    final restored = provider.entries.single;
    // 文件在导出机上就已丢失 → 导入端无从落地；保留原路径交由
    // 渲染端按文件存在性退化，不做破坏性清空。
    expect(restored.canvas!.images.single.path, '/gone/x.jpg');
    await db.close();
  });

  test('Attachments.baseName 分隔符无关', () {
    expect(Attachments.baseName(r'C:\a\b\c.jpg'), 'c.jpg');
    expect(Attachments.baseName('/data/app/c.png'), 'c.png');
    expect(Attachments.baseName('plain.gif'), 'plain.gif');
  });
}
