import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/canvas_page.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart';
import '../utils/journal_id.dart';

/// 分享包损坏、格式不符或超出安全上限（REQ-21.10）。
/// message 直接上屏，必须是可读中文。
class SharePackFormatException implements Exception {
  SharePackFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 从分享包解析出的数据（附录：pack.json + templates.json + stickers.json + assets/）。
///
/// 与 [BackupData] 的信任级别不同：这里的一切都来自他人文件，
/// 模板一律走 [JournalTemplate.fromExternalMap]，安装时再重新分配 id（FIX-02）。
class SharePackData {
  SharePackData({
    required this.name,
    required this.author,
    required this.templates,
    required this.stickers,
    required this.stickerBytes,
  });

  /// 包名（pack.json 的 name）。
  final String name;

  /// 来源署名（pack.json 的 author）；可为空串。
  final String author;

  final List<JournalTemplate> templates;

  /// 自定义贴纸清单；老包没有 stickers.json 时为空（NFR-07）。
  final List<CustomSticker> stickers;

  /// 贴纸文件名（`<sha1><ext>`）→ 字节内容，取自包内 assets/ 目录。
  final Map<String, Uint8List> stickerBytes;
}

/// 素材 / 模板分享包（REQ-21）：独立于备份包的分发格式。
///
/// 与备份包的区别见需求文档判断二——内容不可信、动作语义是「安装」而非「恢复」。
/// 两种包靠顶层结构区分：备份包是 entries.json，分享包是 pack.json（附录约束 1）。
class SharePackService {
  SharePackService._();

  static final SharePackService instance = SharePackService._();

  static const formatVersion = 1;
  static const _packFileName = 'pack.json';
  static const _templatesFileName = 'templates.json';
  static const _stickersFileName = 'stickers.json';
  static const _assetsDir = 'assets/';

  /// 单包体积上限（NFR-06）。
  static const maxPackBytes = 20 * 1024 * 1024;

  /// 解包上限（NFR-06 防解压炸弹）：包内条目数与解压后总字节。
  /// 分享包的典型体积是数 KB～数百 KB，上限取得比备份包紧得多。
  static const maxArchiveFiles = 2000;
  static const maxUnpackedBytes = 64 * 1024 * 1024;

  /// Windows 盘符开头的绝对路径（NFR-06 条目名消毒）。
  static final _driveLetter = RegExp(r'^[a-zA-Z]:');

  /// 文件名里不能出现的字符（Windows 保留字符与控制字符），导出时统一换成下划线。
  static final _unsafeFileChars = RegExp('[\\/:*?"<>|\x00-\x1f]');

  /// 组装分享包 zip 字节（REQ-21.1/21.2）。
  ///
  /// 模板画布内的照片路径一律清空只留占位框——REQ-21.4「不得包含任何本机绝对路径」
  /// 是硬约束，不能只靠调用方自觉，因此这里对副本再清一遍，
  /// 且不影响调用方内存里的模板对象。
  Future<Uint8List> buildPack({
    required String packName,
    required String author,
    required List<JournalTemplate> templates,
    List<CustomSticker> stickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
  }) async {
    final templateMaps = <Map<String, Object?>>[];
    for (final t in templates) {
      final canvas = t.canvas;
      if (canvas == null || !canvas.hasImagePaths) {
        templateMaps.add(t.toMap());
        continue;
      }
      final cleaned = canvas.clone()..clearImagePaths();
      templateMaps.add({...t.toMap(), 'canvas': encodeCanvas(cleaned)});
    }

    final meta = <String, Object?>{
      'app': 'pagenote',
      'format': formatVersion,
      'kind': _kindOf(templates.isNotEmpty, stickers.isNotEmpty),
      'id': 'pack-${makeId()}',
      'name': packName,
      'author': author,
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'counts': {'templates': templates.length, 'stickers': stickers.length},
    };

    const encoder = JsonEncoder.withIndent('  ');
    final archive = Archive()
      ..addFile(_jsonFile(_packFileName, encoder.convert(meta)))
      ..addFile(_jsonFile(_templatesFileName, encoder.convert(templateMaps)));
    if (stickers.isNotEmpty) {
      final maps = [for (final s in stickers) s.toMap()];
      archive.addFile(_jsonFile(_stickersFileName, encoder.convert(maps)));
    }
    stickerBytes.forEach((name, bytes) {
      archive.addFile(ArchiveFile.bytes('$_assetsDir$name', bytes));
    });

    return ZipEncoder().encodeBytes(archive);
  }

  /// 导出分享包到用户选择的位置（REQ-21.5）。
  /// Windows：系统保存对话框；Android：写入临时文件后拉起系统分享。
  /// 返回导出文件路径，用户取消返回 null。
  Future<String?> exportPack({
    required String packName,
    required String author,
    required List<JournalTemplate> templates,
    List<CustomSticker> stickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
  }) async {
    final bytes = await buildPack(
      packName: packName,
      author: author,
      templates: templates,
      stickers: stickers,
      stickerBytes: stickerBytes,
    );
    // 文件名含包名与日期（REQ-21.5）；扩展名固定 .zip，
    // 自创扩展名会让微信 / QQ 的「用其他应用打开」失效。
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final safeName = packName.replaceAll(_unsafeFileChars, '_').trim();
    final name = '拾页素材包-${safeName.isEmpty ? '未命名' : safeName}-$date.zip';
    const zipGroup = XTypeGroup(label: '素材包', extensions: ['zip']);

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

  /// 解析并校验分享包（REQ-21.10）：非法内容抛 [SharePackFormatException]。
  ///
  /// 闸门顺序：单包体积 → 解压 → 条目数 / 条目名 / 解压总体积
  /// → pack.json → app 认亲 → format 版本，任一未过一条都不写进库（NFR-07）。
  SharePackData parsePack(Uint8List bytes) {
    if (bytes.lengthInBytes > maxPackBytes) {
      final mb = maxPackBytes ~/ (1024 * 1024);
      throw SharePackFormatException('素材包体积过大（超过 $mb MB），已拒绝导入');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw SharePackFormatException('这不是有效的拾页素材包（无法解压）');
    }
    _guardArchive(archive);

    final packFile = archive.findFile(_packFileName);
    if (packFile == null) {
      throw SharePackFormatException('这不是拾页素材包（缺少 pack.json）');
    }

    final Map<String, Object?> meta;
    try {
      meta = (jsonDecode(utf8.decode(packFile.content as List<int>)) as Map)
          .cast<String, Object?>();
    } catch (_) {
      throw SharePackFormatException('素材包已损坏（pack.json 无法解析）');
    }
    if (meta['app'] != 'pagenote') {
      throw SharePackFormatException('这不是拾页导出的素材包');
    }
    // 高版本包不做部分导入，直接整包拒绝（NFR-07）。
    final format = meta['format'];
    if (format is int && format > formatVersion) {
      throw SharePackFormatException('该素材包需要更新版本的拾页');
    }

    List<JournalTemplate> templates;
    try {
      // 外部文件里的 builtin 自称一律不采信（FIX-02.1）。
      templates = [
        for (final raw in _jsonArray(archive, _templatesFileName))
          JournalTemplate.fromExternalMap((raw as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      throw SharePackFormatException('素材包中的模板数据格式不正确');
    }

    // stickers.json 是可选项：纯模板包与老包都没有，降级为空（NFR-07）。
    List<CustomSticker> stickers;
    try {
      stickers = [
        for (final raw in _jsonArray(archive, _stickersFileName))
          CustomSticker.fromMap((raw as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      throw SharePackFormatException('素材包中的贴纸数据格式不正确');
    }

    final stickerBytes = <String, Uint8List>{};
    for (final f in archive) {
      if (!f.isFile || !f.name.startsWith(_assetsDir)) continue;
      final name = p.basename(f.name);
      if (name.isEmpty) continue;
      stickerBytes[name] = Uint8List.fromList(f.content as List<int>);
    }

    return SharePackData(
      name: (meta['name'] ?? '') as String,
      author: (meta['author'] ?? '') as String,
      templates: templates,
      stickers: stickers,
      stickerBytes: stickerBytes,
    );
  }

  /// 包内容类型（附录设计约束 1）。
  static String _kindOf(bool hasTemplates, bool hasStickers) {
    if (hasTemplates && hasStickers) return 'mixed';
    return hasStickers ? 'sticker' : 'template';
  }

  static ArchiveFile _jsonFile(String name, String json) =>
      ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(json)));

  /// 读取包内的裸 JSON 数组；文件不存在按空数组处理。
  static List<Object?> _jsonArray(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) return const [];
    return jsonDecode(utf8.decode(file.content as List<int>)) as List<Object?>;
  }

  /// 解包前的安全校验（NFR-06）：条目数、解压后总体积与条目名合法性。
  /// 体积取自 zip 头部记录的原始大小，无需真正解压即可判断。
  void _guardArchive(Archive archive) {
    if (archive.length > maxArchiveFiles) {
      throw SharePackFormatException('素材包内容过多（超过 $maxArchiveFiles 项），已拒绝导入');
    }
    var total = 0;
    for (final f in archive) {
      if (!_isSafeEntryName(f.name)) {
        throw SharePackFormatException('素材包包含非法路径「${f.name}」，已拒绝导入');
      }
      total += f.size;
      if (total > maxUnpackedBytes) {
        final mb = maxUnpackedBytes ~/ (1024 * 1024);
        throw SharePackFormatException('素材包解压后体积过大（超过 $mb MB），已拒绝导入');
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
