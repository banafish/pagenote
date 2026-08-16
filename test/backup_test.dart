import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pagenote/database/app_database.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/providers/journal_provider.dart';
import 'package:pagenote/services/backup_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  JournalEntry entry(String id,
      {DateTime? updatedAt, List<String> images = const []}) {
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
    await provider.saveEntry(entry('keep-local', updatedAt: DateTime(2026, 8, 16, 12, 0)));
    await provider.saveEntry(entry('update-me', updatedAt: DateTime(2026, 8, 1)));

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
    expect(
      provider.entries.map((e) => e.id).toSet(),
      {'from-backup-1', 'from-backup-2'},
    );

    await db.close();
  });
}
