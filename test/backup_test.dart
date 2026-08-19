import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/services/backup_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  JournalEntry entry(
    String id, {
    DateTime? updatedAt,
    List<String> images = const [],
  }) {
    final ts = updatedAt ?? DateTime(2026, 8, 16, 10, 0);
    return JournalEntry(
      id: id,
      date: '2026-08-16',
      title: '标题$id',
      content: '内容$id',
      mood: Mood.happy,
      tags: ['备份'],
      images: images,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  test('导出 zip → 解析往返：条目字段与附件字节完整（REQ-03.1/2）', () async {
    // 准备一张真实临时图片。
    final tmpDir = await Directory.systemTemp.createTemp('pagenote-backup');
    final imgFile = File(p.join(tmpDir.path, 'photo.jpg'));
    await imgFile.writeAsBytes([1, 2, 3, 4, 5]);

    final withImage = entry('e1', images: [imgFile.path]);

    final zipBytes = await BackupService.instance.buildZip(
      entries: [withImage, entry('e2')],
      templates: [],
    );
    expect(zipBytes, isNotEmpty);

    final data = BackupService.instance.parseBackup(zipBytes);
    expect(data.entries.length, 2);
    expect(data.entries.first.mood, Mood.happy);
    expect(data.entries.first.tags, ['备份']);
    // images 已转为相对附件名。
    expect(data.entries.first.images, ['photo.jpg']);
    expect(data.attachments['photo.jpg'], [1, 2, 3, 4, 5]);

    await tmpDir.delete(recursive: true);
  });

  test('校验非法备份文件（REQ-03.2）', () async {
    final service = BackupService.instance;

    expect(
      () => service.parseBackup(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<BackupFormatException>()),
      reason: '非 zip 内容',
    );

    // 一个不含 entries.json 的 zip。
    final bytes = ZipEncoder().encodeBytes(Archive());
    expect(
      () => service.parseBackup(bytes),
      throwsA(isA<BackupFormatException>()),
      reason: '缺少 entries.json',
    );
  });

  test('合并导入：按 id 去重、updatedAt 新者胜（REQ-03.2）', () async {
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.saveEntry(
      entry('keep-local', updatedAt: DateTime(2026, 8, 16, 12, 0)),
    );
    await provider.saveEntry(
      entry('update-me', updatedAt: DateTime(2026, 8, 1)),
    );

    final data = BackupData(
      entries: [
        // 本地较新 → 保留本地。
        entry('keep-local', updatedAt: DateTime(2026, 8, 10)),
        // 备份较新 → 采用备份。
        entry('update-me', updatedAt: DateTime(2026, 8, 15)),
        // 新条目 → 插入。
        entry('brand-new', updatedAt: DateTime(2026, 8, 14)),
      ],
      templates: [],
      attachments: {},
    );

    final changed = await provider.importBackup(data, overwrite: false);
    expect(changed, 2, reason: 'update-me + brand-new 被写入');

    final all = provider.entries;
    expect(all.length, 3);
    final updated = all.firstWhere((e) => e.id == 'update-me');
    expect(updated.updatedAt, DateTime(2026, 8, 15));
    final kept = all.firstWhere((e) => e.id == 'keep-local');
    expect(kept.updatedAt, DateTime(2026, 8, 16, 12, 0));

    await db.close();
  });

  test('覆盖导入：清空后全量写入（REQ-03.2）', () async {
    final db = AppDatabase.inMemory();
    final provider = JournalProvider(database: db);
    await provider.saveEntry(entry('old-1'));
    await provider.saveEntry(entry('old-2'));
    expect(provider.totalCount, 2);

    final data = BackupData(
      entries: [entry('from-backup-1'), entry('from-backup-2')],
      templates: [],
      attachments: {},
    );
    final changed = await provider.importBackup(data, overwrite: true);
    expect(changed, 2);
    expect(provider.totalCount, 2);
    expect(provider.entries.map((e) => e.id).toSet(), {
      'from-backup-1',
      'from-backup-2',
    });

    await db.close();
  });

  // ------------------ FIX-02：builtin 不可伪造 + 恢复/安装分离 ------------------

  /// 手工拼一条 templates JSON（模拟外部改造过的包，不经 toMap）。
  Map<String, Object?> templateMap(
    String id, {
    required String name,
    required bool builtin,
    DateTime? updatedAt,
  }) {
    final ts = (updatedAt ?? DateTime(2026, 8, 16)).millisecondsSinceEpoch;
    return {
      'id': id,
      'name': name,
      'title': '',
      'content': '正文$id',
      'tags': '',
      'builtin': builtin ? 1 : 0,
      'canvas': '',
      'originId': null,
      'lastUsedAt': null,
      'sortIndex': 0,
      'createdAt': ts,
      'updatedAt': ts,
    };
  }

  /// 只含 entries.json 的最小备份包。
  Uint8List zipOf(List<Map<String, Object?>> templates) {
    final manifest = {
      'app': 'pagenote',
      'format': BackupService.formatVersion,
      'exportedAt': '2026-08-16T00:00:00.000',
      'entries': const <Object?>[],
      'templates': templates,
    };
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'entries.json',
          Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
        ),
      );
    return ZipEncoder().encodeBytes(archive);
  }

  List<JournalTemplate> restored(List<Map<String, Object?>> templates) =>
      BackupService.instance.parseBackup(zipOf(templates)).templates;

  test('伪造 builtin: 1 的包，导入后模板仍可删除（FIX-02.1/4）', () async {
    // id 不在本机内置清单里，却自称内置。
    final parsed = restored([
      templateMap('tpl-forged', name: '伪装成内置', builtin: true),
    ]).single;
    expect(parsed.builtin, isFalse, reason: '文件里的自称一律不采信');

    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();
    await provider.importTemplates([parsed], overwrite: false);

    final imported = provider.byId('tpl-forged');
    expect(imported, isNotNull);
    expect(imported!.builtin, isFalse);
    expect(provider.userTemplates.map((t) => t.id), contains('tpl-forged'));

    await provider.deleteTemplate('tpl-forged');
    expect(provider.byId('tpl-forged'), isNull, reason: '删得掉才算修好');

    await db.close();
  });

  test('内置模板经备份往返后 builtin 仍为 true（FIX-02.1）', () async {
    final builtin = builtinTemplates.first;
    final zipBytes = await BackupService.instance.buildZip(
      entries: [],
      templates: [builtin],
    );
    final roundTrip = BackupService.instance
        .parseBackup(zipBytes)
        .templates
        .single;
    expect(roundTrip.id, builtin.id);
    expect(roundTrip.builtin, isTrue, reason: '恢复不得把内置模板降级为可删');

    // 反向伪造：内置 id 却写 builtin: 0，同样以本机清单为准。
    final downgraded = restored([
      templateMap(builtin.id, name: builtin.name, builtin: false),
    ]).single;
    expect(downgraded.builtin, isTrue);
  });

  test('安装分享包：重分配 id、原 id 落 originId、同名保留两者（FIX-02.2/3）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    final incoming = restored([
      templateMap('tpl-friend', name: '朋友的模板', builtin: true),
      templateMap('tpl-friend-2', name: '朋友的模板', builtin: false),
    ]);
    final installed = await provider.installTemplates(incoming);

    expect(installed.length, 2);
    expect(
      installed.map((t) => t.id).toSet().intersection({
        'tpl-friend',
        'tpl-friend-2',
      }),
      isEmpty,
      reason: 'id 一律重新分配',
    );
    expect(provider.byId('tpl-friend'), isNull);
    expect(installed.map((t) => t.originId).toList(), [
      'tpl-friend',
      'tpl-friend-2',
    ]);
    expect(installed.every((t) => !t.builtin), isTrue);
    // 同名默认保留两者，后者自动加后缀。
    expect(installed.map((t) => t.name).toList(), ['朋友的模板', '朋友的模板 (2)']);

    // 分享包里若含一份内置模板，安装后同样降级为可删的用户模板。
    final source = builtinTemplates.first;
    final fromBuiltin = (await provider.installTemplates([
      source.copy(),
    ])).single;
    expect(fromBuiltin.builtin, isFalse);
    expect(fromBuiltin.id, isNot(source.id));
    expect(fromBuiltin.originId, source.id);
    await provider.deleteTemplate(fromBuiltin.id);
    expect(provider.byId(fromBuiltin.id), isNull);
    expect(provider.byId(source.id)!.builtin, isTrue, reason: '本机内置本身不受影响');

    await db.close();
  });

  test('恢复备份：保留原 id、updatedAt 新者胜、覆盖模式清空（FIX-02.3）', () async {
    final db = AppDatabase.inMemory();
    final provider = TemplateProvider(database: db);
    await provider.load();

    await provider.importTemplates(
      restored([
        templateMap(
          'tpl-shared',
          name: '旧名',
          builtin: false,
          updatedAt: DateTime(2026, 8, 1),
        ),
      ]),
      overwrite: false,
    );
    // 与安装语义相反：id 原样保留，也不写 originId。
    expect(provider.byId('tpl-shared'), isNotNull);
    expect(provider.byId('tpl-shared')!.name, '旧名');
    expect(provider.byId('tpl-shared')!.originId, isNull);

    // 更旧的版本不覆盖本地。
    await provider.importTemplates(
      restored([
        templateMap(
          'tpl-shared',
          name: '更旧的名',
          builtin: false,
          updatedAt: DateTime(2026, 7, 1),
        ),
      ]),
      overwrite: false,
    );
    expect(provider.byId('tpl-shared')!.name, '旧名');

    // 更新的版本覆盖本地，且不会因同 id 重复落库。
    await provider.importTemplates(
      restored([
        templateMap(
          'tpl-shared',
          name: '新名',
          builtin: false,
          updatedAt: DateTime(2026, 8, 20),
        ),
      ]),
      overwrite: false,
    );
    expect(provider.byId('tpl-shared')!.name, '新名');
    expect(provider.userTemplates.length, 1);

    // 覆盖模式：清空后只剩包内模板 + 重新补种的内置模板。
    await provider.importTemplates(
      restored([templateMap('tpl-only', name: '覆盖后唯一', builtin: false)]),
      overwrite: true,
    );
    expect(provider.userTemplates.map((t) => t.id).toList(), ['tpl-only']);
    expect(provider.builtinTemplates.length, builtinTemplates.length);

    await db.close();
  });
}
