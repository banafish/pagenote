import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/services/backup_service.dart';

/// 把文档目录指向临时目录：Attachments / StickerStore 的落盘都走这里，
/// 测试不得污染真实文档目录。
class _TempDocuments extends PathProviderPlatform {
  _TempDocuments(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// 路径在 JSON 文本里的形态（Windows 的反斜杠会被转义）。
String _jsonText(String path) {
  final quoted = jsonEncode(path);
  return quoted.substring(1, quoted.length - 1);
}

void main() {
  late Directory documents;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    documents = await Directory.systemTemp.createTemp('pagenote-tpl-docs');
    PathProviderPlatform.instance = _TempDocuments(documents.path);
  });

  tearDownAll(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  JournalEntry photoEntry() => JournalEntry(
    id: 'e-photo',
    date: '2026-08-18',
    title: '有照片的一天',
    content: '正文',
    tags: ['旅行'],
    createdAt: DateTime(2026, 8, 18),
    updatedAt: DateTime(2026, 8, 18),
  );

  /// 一张照片 + 一段文字 + 一个贴纸的画布。
  JournalCanvas photoCanvas(String path) => JournalCanvas(
    elements: [
      TextElement(text: '标题', role: 'title'),
      ImageElement(path: path),
      StickerElement(key: 'vec:star'),
    ],
  );

  test('内置模板 ≥4 套且 load 自动补种（REQ-09.1）', () async {
    expect(builtinTemplates.length, greaterThanOrEqualTo(4));
    expect(
      builtinTemplates.map((t) => t.name),
      containsAll(['每日复盘', '读书笔记', '旅行手账', '周记']),
    );

    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();
    expect(provider.builtinTemplates.length, builtinTemplates.length);

    // 删除内置模板的行后再次 load，应重新补种。
    await db.deleteAllTemplates();
    await provider.load();
    expect(provider.builtinTemplates.length, builtinTemplates.length);

    await db.close();
  });

  test('另存为模板 / 重命名 / 删除（内置不可删）（REQ-09.3）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final entry = JournalEntry(
      id: 'e1',
      date: '2026-08-16',
      title: '我的模板标题',
      content: '【分节】\n',
      tags: ['自定义'],
      createdAt: DateTime(2026, 8, 16),
      updatedAt: DateTime(2026, 8, 16),
    );
    final saved = await provider.saveFromEntry(entry, '我的模板');
    expect(provider.userTemplates.length, 1);
    expect(saved.title, '我的模板标题');
    expect(saved.tags, ['自定义']);
    expect(saved.builtin, isFalse);

    // 重命名。
    saved.name = '改名后';
    await provider.saveTemplate(saved);
    expect(provider.userTemplates.single.name, '改名后');

    // 删除自建模板。
    await provider.deleteTemplate(saved.id);
    expect(provider.userTemplates, isEmpty);

    // 内置模板不可删。
    final builtin = provider.builtinTemplates.first;
    await provider.deleteTemplate(builtin.id);
    expect(
      provider.templates.where((t) => t.id == builtin.id).single,
      isNotNull,
    );

    await db.close();
  });

  test('模板导入：合并去重与覆盖（REQ-09.4）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final incoming = [
      JournalTemplate(
        id: 'tpl-x',
        name: '备份模板',
        content: '内容',
        updatedAt: DateTime(2026, 8, 16),
      ),
      // 与内置同 id 的较旧版本 → 不覆盖。
      builtinTemplates.first.copy()
        ..name = '被篡改的内置名'
        ..updatedAt = DateTime(2020, 1, 1),
    ];

    await provider.importTemplates(incoming, overwrite: false);
    expect(
      provider.templates.where((t) => t.id == 'tpl-x').single.name,
      '备份模板',
    );
    expect(provider.builtinTemplates.first.name, isNot('被篡改的内置名'));

    // 覆盖导入后重新补种内置模板。
    await provider.importTemplates([], overwrite: true);
    expect(provider.builtinTemplates.length, builtinTemplates.length);
    expect(provider.userTemplates, isEmpty);

    await db.close();
  });

  test('另存为模板默认清空照片路径，只留占位框（FIX-01.1）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final canvas = photoCanvas(r'C:\Users\somebody\Documents\attachments\a.jpg');
    final saved = await provider.saveFromEntry(
      photoEntry(),
      '默认模板',
      canvas: canvas,
    );

    final savedCanvas = saved.canvas!;
    expect(savedCanvas.elements.length, canvas.elements.length, reason: '占位框保留，元素数量不变');
    expect(savedCanvas.images.single.path, '');
    expect(savedCanvas.hasImagePaths, isFalse);
    // 只清副本，调用方手里的画布不受影响。
    expect(canvas.images.single.path, isNotEmpty);

    await db.close();
  });

  test('另存为模板勾选保留照片时路径不变（FIX-01.2）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    const path = r'C:\Users\somebody\Documents\attachments\a.jpg';
    final saved = await provider.saveFromEntry(
      photoEntry(),
      '保留照片模板',
      canvas: photoCanvas(path),
      keepPhotos: true,
    );

    expect(saved.canvas!.images.single.path, path);
    expect(saved.canvas!.hasImagePaths, isTrue);

    await db.close();
  });

  test('带照片模板导出 → 导入：路径重映射且包内不含绝对路径（FIX-01）', () async {
    final tmpDir = await Directory.systemTemp.createTemp('pagenote-tpl');
    final photo = File(p.join(tmpDir.path, 'canvas-photo.jpg'));
    await photo.writeAsBytes([9, 8, 7, 6]);

    final db = AppDatabase.inMemory();
    final source = TemplateProvider(database: db);
    await source.load();
    final saved = await source.saveFromEntry(
      photoEntry(),
      '带照片模板',
      canvas: photoCanvas(photo.path),
      keepPhotos: true,
    );

    final zipBytes = await BackupService.instance.buildZip(
      entries: [],
      templates: [saved],
    );

    // 核心断言：包内 entries.json 不得留下任何本机绝对路径。
    final manifest = utf8.decode(
      ZipDecoder().decodeBytes(zipBytes).findFile('entries.json')!.content
          as List<int>,
    );
    expect(manifest, isNot(contains(_jsonText(photo.path))));
    expect(manifest, isNot(contains(_jsonText(tmpDir.path))));
    expect(manifest, contains('canvas-photo.jpg'), reason: '照片改写为纯文件名');

    final data = BackupService.instance.parseBackup(zipBytes);
    expect(data.attachments['canvas-photo.jpg'], [9, 8, 7, 6]);

    // 换一台设备导入：照片重新落到本机附件目录。
    // sqflite 的 :memory: 按路径单例，第二个库必须落到独立文件。
    final otherDb = AppDatabase.atPath(p.join(tmpDir.path, 'other.db'));
    final target = TemplateProvider(database: otherDb);
    await target.load();
    await target.importTemplates(
      data.templates,
      overwrite: false,
      attachments: data.attachments,
    );

    final imported = target.userTemplates.single;
    final canvas = imported.canvas!;
    expect(canvas.elements.length, 3, reason: '文字与贴纸一并还原');
    final path = canvas.images.single.path;
    expect(path, isNotEmpty, reason: '模板可正常渲染照片');
    expect(path, isNot(photo.path), reason: '已重映射到本机附件目录');
    expect(p.isWithin(documents.path, path), isTrue);
    expect(File(path).readAsBytesSync(), [9, 8, 7, 6]);

    await db.close();
    await otherDb.close();
    await tmpDir.delete(recursive: true);
  });

  test('附件缺失时模板照片退化为占位框（FIX-01.3）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final incoming = JournalTemplate(
      id: 'tpl-photo',
      name: '外来模板',
      canvas: photoCanvas('canvas-photo.jpg'),
      updatedAt: DateTime(2026, 8, 18),
    );
    await provider.importTemplates([incoming], overwrite: false);

    final canvas = provider.userTemplates.single.canvas!;
    expect(canvas.elements.length, 3);
    expect(canvas.images.single.path, '', reason: '不保留外来的路径字符串');
    expect(canvas.hasImagePaths, isFalse);

    await db.close();
  });
}
