import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/canvas_page.dart';
import '../models/journal_entry.dart';
import '../models/sticker_assets.dart';
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
    this.customStickers = const [],
    this.stickerBytes = const {},
    this.stickerPacks = const [],
  });

  final List<JournalEntry> entries;
  final List<JournalTemplate> templates;
  final Map<String, Uint8List> attachments;

  /// 自定义图片贴纸清单（REQ-20.6）；旧备份没有该项时为空。
  final List<CustomSticker> customStickers;

  /// 贴纸文件名（`<sha1><ext>`）→ 字节内容（REQ-20.6）。
  final Map<String, Uint8List> stickerBytes;

  /// 素材包清单（v7）；旧备份没有该项时为空，贴纸全部落未分组。
  final List<StickerPack> stickerPacks;
}

/// 数据导出与导入（REQ-03）：单个 zip，内含 entries.json 与 attachments/ 目录。
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const formatVersion = 1;
  static const _entriesFileName = 'entries.json';
  static const _stickersFileName = 'stickers.json';
  static const _packsFileName = 'sticker_packs.json';

  /// 解包上限（NFR-06 防解压炸弹）：包内条目数与解压后总字节。
  static const _maxArchiveFiles = 20000;
  static const _maxUnpackedBytes = 1024 * 1024 * 1024;

  /// Windows 盘符开头的绝对路径（NFR-06 条目名消毒）。
  static final _driveLetter = RegExp(r'^[a-zA-Z]:');

  /// 组装备份 zip 字节。图片按文件名放入 attachments/ 目录，
  /// 条目的 images 字段转为相对附件名，便于跨设备导入。
  /// 模板画布内的照片一并入包，路径同样转为纯文件名（FIX-01.2）。
  /// [customStickers] 与 [stickerBytes] 为自定义图片贴纸（REQ-20.6），
  /// 后者由 CustomStickerProvider.exportBytes 提供。
  Future<Uint8List> buildZip({
    required List<JournalEntry> entries,
    required List<JournalTemplate> templates,
    List<CustomSticker> customStickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
    List<StickerPack> stickerPacks = const [],
  }) async {
    final archive = Archive();
    final attachmentBytes = <String, Uint8List>{};

    final entryMaps = <Map<String, Object?>>[];
    for (final e in entries) {
      final imageNames = <String>[];
      // 画布上的照片元素与 images 列一并打包（photos on canvas）。
      final canvasImages = e.canvas?.images ?? const <ImageElement>[];
      for (final path in [
        ...e.images,
        for (final img in canvasImages)
          if (img.path.isNotEmpty) img.path,
      ]) {
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

    // 模板画布内的照片一并入包，并把路径改写为纯文件名（FIX-01.2）：
    // 导出内容不得留下任何本机绝对路径。
    final templateMaps = <Map<String, Object?>>[];
    for (final t in templates) {
      final canvas = t.canvas;
      if (canvas == null || !canvas.hasImagePaths) {
        templateMaps.add(t.toMap());
        continue;
      }
      final packed = <String>{};
      for (final img in canvas.images) {
        if (img.path.isEmpty) continue;
        final name = p.basename(img.path);
        final file = File(img.path);
        if (await file.exists()) {
          attachmentBytes.putIfAbsent(name, () => file.readAsBytesSync());
          packed.add(name);
        }
      }
      // 只改序列化用的副本，内存里的模板对象保持本机路径。
      // 文件已丢失的照片退化为占位框，与导入端的重映射一致。
      final packedCanvas = canvas.clone();
      packedCanvas.remapImagePaths((path) {
        final name = p.basename(path);
        return packed.contains(name) ? name : '';
      });
      templateMaps.add({...t.toMap(), 'canvas': encodeCanvas(packedCanvas)});
    }

    final manifest = {
      'app': 'pagenote',
      'format': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'entries': entryMaps,
      'templates': templateMaps,
    };
    final json = const JsonEncoder.withIndent('  ').convert(manifest);
    archive.addFile(
      ArchiveFile.bytes(
        _entriesFileName,
        Uint8List.fromList(utf8.encode(json)),
      ),
    );
    attachmentBytes.forEach((name, bytes) {
      archive.addFile(ArchiveFile.bytes('attachments/$name', bytes));
    });

    // 自定义图片贴纸随备份导出（REQ-20.6）：清单 + stickers/ 下的位图。
    if (customStickers.isNotEmpty) {
      final maps = [for (final s in customStickers) s.toMap()];
      final stickersJson = const JsonEncoder.withIndent('  ').convert(maps);
      archive.addFile(
        ArchiveFile.bytes(
          _stickersFileName,
          Uint8List.fromList(utf8.encode(stickersJson)),
        ),
      );
    }
    stickerBytes.forEach((name, bytes) {
      archive.addFile(ArchiveFile.bytes('stickers/$name', bytes));
    });

    // 素材包清单（v7）：恢复时按它先重建包记录，贴纸的 packId 才有落位。
    if (stickerPacks.isNotEmpty) {
      final packsJson = const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final p in stickerPacks) p.toMap()]);
      archive.addFile(
        ArchiveFile.bytes(
          _packsFileName,
          Uint8List.fromList(utf8.encode(packsJson)),
        ),
      );
    }

    final encoder = ZipEncoder();
    return encoder.encodeBytes(archive);
  }

  /// 导出备份到用户选择的位置。
  /// Windows：系统保存对话框；Android：写入临时文件后拉起分享。
  /// 返回导出文件路径，用户取消返回 null。
  Future<String?> exportBackup({
    required List<JournalEntry> entries,
    required List<JournalTemplate> templates,
    List<CustomSticker> customStickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
    List<StickerPack> stickerPacks = const [],
  }) async {
    final bytes = await buildZip(
      entries: entries,
      templates: templates,
      customStickers: customStickers,
      stickerBytes: stickerBytes,
      stickerPacks: stickerPacks,
    );
    final name =
        'pagenote-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip';
    const zipGroup = XTypeGroup(label: '备份', extensions: ['zip']);

    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], fileNameOverrides: [name]),
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
    _guardArchive(archive);

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
    final stickerBytes = <String, Uint8List>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = p.basename(f.name);
      if (name.isEmpty) continue;
      // 条目附件与自定义贴纸位图分属两个目录（REQ-20.6）。
      if (f.name.startsWith('attachments/')) {
        attachments[name] = Uint8List.fromList(f.content as List<int>);
      } else if (f.name.startsWith('stickers/')) {
        stickerBytes[name] = Uint8List.fromList(f.content as List<int>);
      }
    }

    List<JournalEntry> entries;
    try {
      entries = (manifest['entries'] as List)
          .map(
            (raw) => JournalEntry.fromMap((raw as Map).cast<String, Object?>()),
          )
          .toList();
    } catch (_) {
      throw BackupFormatException('备份中的手账数据格式不正确');
    }

    List<JournalTemplate> templates;
    try {
      // 外部文件里的 builtin 自称一律不采信，由本机内置清单推导（FIX-02.1）。
      templates = (manifest['templates'] as List? ?? [])
          .map(
            (raw) => JournalTemplate.fromExternalMap(
              (raw as Map).cast<String, Object?>(),
            ),
          )
          .toList();
    } catch (_) {
      throw BackupFormatException('备份中的模板数据格式不正确');
    }

    // 自定义贴纸清单（REQ-20.6）：旧备份没有 stickers.json，降级为空。
    List<CustomSticker> customStickers;
    try {
      final stickersFile = archive.findFile(_stickersFileName);
      final raw = stickersFile == null
          ? const []
          : jsonDecode(utf8.decode(stickersFile.content as List<int>)) as List;
      customStickers = [
        for (final m in raw)
          CustomSticker.fromMap((m as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      throw BackupFormatException('备份中的自定义贴纸数据格式不正确');
    }

    // 素材包清单（v7）：旧备份没有 sticker_packs.json，降级为空。
    List<StickerPack> stickerPacks;
    try {
      final packsFile = archive.findFile(_packsFileName);
      final raw = packsFile == null
          ? const []
          : jsonDecode(utf8.decode(packsFile.content as List<int>)) as List;
      stickerPacks = [
        for (final m in raw)
          StickerPack.fromMap((m as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      throw BackupFormatException('备份中的素材包数据格式不正确');
    }

    return BackupData(
      entries: entries,
      templates: templates,
      attachments: attachments,
      customStickers: customStickers,
      stickerBytes: stickerBytes,
      stickerPacks: stickerPacks,
    );
  }

  /// 解包前的安全校验（NFR-06）：条目数、解压后总体积与条目名合法性。
  /// 体积取自 zip 头部记录的原始大小，无需真正解压即可判断。
  void _guardArchive(Archive archive) {
    if (archive.length > _maxArchiveFiles) {
      throw BackupFormatException('备份文件内容过多（超过 $_maxArchiveFiles 项），已拒绝导入');
    }
    var total = 0;
    for (final f in archive) {
      if (!_isSafeEntryName(f.name)) {
        throw BackupFormatException('备份文件包含非法路径「${f.name}」，已拒绝导入');
      }
      total += f.size;
      if (total > _maxUnpackedBytes) {
        final mb = _maxUnpackedBytes ~/ (1024 * 1024);
        throw BackupFormatException('备份文件解压后体积过大（超过 $mb MB），已拒绝导入');
      }
    }
  }

  /// 条目名是否安全（NFR-06 防路径穿越）：拒绝绝对路径与 `..` 回溯。
  static bool _isSafeEntryName(String name) {
    if (name.isEmpty) return false;
    final normalized = name.replaceAll('\\', '/');
    if (normalized.startsWith('/') || _driveLetter.hasMatch(normalized)) {
      return false;
    }
    return !normalized.split('/').contains('..');
  }
}
