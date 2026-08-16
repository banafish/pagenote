import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/journal_entry.dart';
import '../models/template.dart';

/// 备份文件损坏或格式不符。
class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 从备份包解析出的数据：images 存附件文件名（相对名），
/// attachments 为文件名 → 字节内容。
class BackupData {
  BackupData({
    required this.entries,
    required this.templates,
    required this.attachments,
  });

  final List<JournalEntry> entries;
  final List<JournalTemplate> templates;
  final Map<String, Uint8List> attachments;
}

/// 数据导出与导入（REQ-03）：单个 zip，内含 entries.json 与 attachments/ 目录。
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const formatVersion = 1;
  static const _entriesFileName = 'entries.json';

  /// 组装备份 zip 字节。图片按文件名放入 attachments/ 目录，
  /// 条目的 images 字段转为相对附件名，便于跨设备导入。
  Future<Uint8List> buildZip({
    required List<JournalEntry> entries,
    required List<JournalTemplate> templates,
  }) async {
    final archive = Archive();
    final attachmentBytes = <String, Uint8List>{};

    final entryMaps = <Map<String, Object?>>[];
    for (final e in entries) {
      final imageNames = <String>[];
      for (final path in e.images) {
        final name = p.basename(path);
        final file = File(path);
        if (await file.exists()) {
          attachmentBytes.putIfAbsent(name, () => file.readAsBytesSync());
          if (!imageNames.contains(name)) imageNames.add(name);
        }
      }
      final map = e.toMap();
      entryMaps.add({...map, 'images': imageNames.join('\u001F')});
    }

    final manifest = {
      'app': 'pagenote',
      'format': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'entries': entryMaps,
      'templates': [for (final t in templates) t.toMap()],
    };
    final json = const JsonEncoder.withIndent('  ').convert(manifest);
    archive.addFile(ArchiveFile.bytes(
        _entriesFileName, Uint8List.fromList(utf8.encode(json))));
    attachmentBytes.forEach((name, bytes) {
      archive.addFile(ArchiveFile.bytes('attachments/$name', bytes));
    });

    final encoder = ZipEncoder();
    return encoder.encodeBytes(archive);
  }

  /// 导出备份到用户选择的位置。
  /// Windows：系统保存对话框；Android：写入临时文件后拉起分享。
  /// 返回导出文件路径，用户取消返回 null。
  Future<String?> exportBackup({
    required List<JournalEntry> entries,
    required List<JournalTemplate> templates,
  }) async {
    final bytes = await buildZip(entries: entries, templates: templates);
    final name =
        'pagenote-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip';
    const zipGroup = XTypeGroup(label: '备份', extensions: ['zip']);

    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: [name],
        ),
      );
      return file.path;
    }

    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [zipGroup],
    );
    if (location == null) return null;
    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 选择并读取备份文件，返回 null 表示用户取消。
  Future<BackupData?> pickAndReadBackup() async {
    const zipGroup = XTypeGroup(label: '备份', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: const [zipGroup]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return parseBackup(bytes);
  }

  /// 解析并校验备份（REQ-03.2）：非法内容抛 [BackupFormatException]。
  BackupData parseBackup(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw BackupFormatException('这不是有效的拾页备份文件（无法解压）');
    }

    final entriesFile = archive.findFile(_entriesFileName);
    if (entriesFile == null) {
      throw BackupFormatException('备份文件缺少 entries.json，无法导入');
    }

    final Map<String, Object?> manifest;
    try {
      manifest =
          jsonDecode(utf8.decode(entriesFile.content as List<int>))
              as Map<String, Object?>;
    } catch (_) {
      throw BackupFormatException('备份数据已损坏（entries.json 无法解析）');
    }
    if (manifest['app'] != 'pagenote') {
      throw BackupFormatException('这不是拾页导出的备份文件');
    }

    final attachments = <String, Uint8List>{};
    for (final f in archive) {
      if (f.isFile && f.name.startsWith('attachments/') && f.name.length > 13) {
        final name = f.name.substring('attachments/'.length);
        attachments[name] = Uint8List.fromList(f.content as List<int>);
      }
    }

    List<JournalEntry> entries;
    try {
      entries = (manifest['entries'] as List)
          .map((raw) => JournalEntry.fromMap(
              (raw as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      throw BackupFormatException('备份中的手账数据格式不正确');
    }

    List<JournalTemplate> templates;
    try {
      templates = (manifest['templates'] as List? ?? [])
          .map((raw) => JournalTemplate.fromMap(
              (raw as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      throw BackupFormatException('备份中的模板数据格式不正确');
    }

    return BackupData(
      entries: entries,
      templates: templates,
      attachments: attachments,
    );
  }
}
