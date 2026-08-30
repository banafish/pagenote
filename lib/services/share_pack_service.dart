import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/canvas_page.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart';
import '../storage/stored_files.dart';
import '../storage/user_file.dart';
import '../utils/attachments.dart' show Attachments;
import '../utils/journal_id.dart';
import '../utils/platforms.dart';
import 'foreign_pack_service.dart';

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
    this.packId,
    this.photoBytes = const {},
    this.coverBytes,
    this.isForeign = false,
  });

  /// 包名（pack.json 的 name）。
  final String name;

  /// 来源署名（pack.json 的 author）；可为空串。
  final String author;

  /// 包内 pack.json 的 id（导出方生成）；老包可能没有。
  /// 导入端以它做溯源去重：同一个包重复导入归位到同一本地包。
  final String? packId;

  final List<JournalTemplate> templates;

  /// 自定义贴纸清单；老包没有 stickers.json 时为空（NFR-07）。
  final List<CustomSticker> stickers;

  /// 贴纸文件名（`<sha1><ext>`）→ 字节内容，取自包内 assets/ 目录。
  final Map<String, Uint8List> stickerBytes;

  /// 模板画布照片的文件名 → 字节内容，取自包内 photos/ 目录（FIX-01.2）。
  /// 导出方未勾选「保留照片」时为空。
  /// 调用方直接把它交给 `TemplateProvider.installTemplates` 的 attachments 参数，
  /// 由那边按文件名落盘并重映射为本机路径（FIX-01.3）。
  final Map<String, Uint8List> photoBytes;

  /// 包封面 cover.png 的原始字节（REQ-27.5，附录中的可选字段）；
  /// 老包与不带封面的包为 null。这是不可信字节，落盘前仍要过
  /// PackCoverStore 的解码尺寸闸与压缩（NFR-06 / NFR-14）。
  final Uint8List? coverBytes;

  /// 是否为外部格式转换来的包（REQ-29）：无 pack.json，从免抠图 zip 等
  /// 外部压缩包转换而来，只有贴纸没有模板。预览页据此展示来源标识。
  final bool isForeign;
}

/// 移动端导出去向（REQ-21.5）：直接存进用户挑的文件夹，或拉起系统分享。
enum PackExportDestination {
  /// 系统文件选择器里挑文件夹，zip 直接落盘到所选位置。
  saveToFolder,

  /// 写入临时文件后交给系统分享面板（微信 / QQ 等）。
  systemShare,
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
  static const _coverFileName = 'cover.png';
  static const _assetsDir = 'assets/';
  static const _photosDir = 'photos/';

  /// 单包体积上限（NFR-06）。
  static const maxPackBytes = 20 * 1024 * 1024;

  /// 外部素材包的单包上限（REQ-29）：免抠图 zip 普遍比拾页包大一个量级，
  /// 按分享包的 20MB 拦会把大部分外部包挡在门外。原始字节本身不落盘，
  /// 内存天花板仍由解压体积闸（[maxUnpackedBytes]）守着。
  static const maxForeignPackBytes = 100 * 1024 * 1024;

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
  /// [packId] 为包的稳定分享 id（整包导出时传包的 originId）：
  /// 导入端按它把同一个包的重复导入归位到同一本地包。
  /// 不传则现场生成——散选内容拼的临时包没有持续身份，每次导出都是新包。
  ///
  /// [coverBytes] 为包封面（REQ-27.6）：整包导出时若有封面则写入顶层
  /// cover.png。该字段在附录格式中本就可选，格式不升版；
  /// 老版本按 NFR-07 忽略未知条目，不受影响。
  ///
  /// [includePhotos] 决定模板画布里的照片怎么处理，两条路都不会留下本机绝对路径
  /// ——REQ-21.4 是硬约束，不能只靠调用方自觉，因此这里对副本再处理一遍，
  /// 且不影响调用方内存里的模板对象：
  /// - false（默认）：路径一律清空只留占位框。分享给别人的包默认不带私人照片，
  ///   模板本身的语义也是让使用者填自己的照片（FIX-01.1）。
  /// - true：照片字节入包放进 photos/ 目录，画布里的路径改写为纯文件名，
  ///   由导入端按文件名重映射（FIX-01.2），与备份包 [BackupService.buildZip] 同一套做法。
  ///
  /// 读不到的照片文件跳过，对应元素退化为占位框，不让整包导出失败。
  /// 注意带照片的包很容易超过 [maxPackBytes]，调用方应在勾选开关处提示体积。
  Future<Uint8List> buildPack({
    required String packName,
    required String author,
    required List<JournalTemplate> templates,
    List<CustomSticker> stickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
    bool includePhotos = false,
    String? packId,
    Uint8List? coverBytes,
  }) async {
    final photoBytes = <String, Uint8List>{};
    final templateMaps = <Map<String, Object?>>[];
    for (final t in templates) {
      final canvas = t.canvas;
      if (canvas == null || !canvas.hasImagePaths) {
        templateMaps.add(t.toMap());
        continue;
      }
      if (!includePhotos) {
        final cleaned = canvas.clone()..clearImagePaths();
        templateMaps.add({...t.toMap(), 'canvas': encodeCanvas(cleaned)});
        continue;
      }
      final packed = <String>{};
      for (final img in canvas.images) {
        if (img.path.isEmpty) continue;
        final name = Attachments.baseName(img.path);
        if (packed.contains(name)) continue;
        final raw = await storedFiles.read(img.path);
        if (raw == null) continue;
        photoBytes.putIfAbsent(name, () => raw);
        packed.add(name);
      }
      final packedCanvas = canvas.clone();
      packedCanvas.remapImagePaths((path) {
        final name = Attachments.baseName(path);
        return packed.contains(name) ? name : '';
      });
      templateMaps.add({...t.toMap(), 'canvas': encodeCanvas(packedCanvas)});
    }

    final meta = <String, Object?>{
      'app': 'pagenote',
      'format': formatVersion,
      'kind': _kindOf(templates.isNotEmpty, stickers.isNotEmpty),
      'id': packId ?? 'pack-${makeId()}',
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
    // 包封面（REQ-27.6）：附录格式中的可选顶层条目，老版本忽略不报错。
    if (coverBytes != null) {
      archive.addFile(ArchiveFile.bytes(_coverFileName, coverBytes));
    }
    // 照片与贴纸分目录存放，导入端才能分别交给贴纸库与模板重映射（FIX-01.2）。
    photoBytes.forEach((name, bytes) {
      archive.addFile(ArchiveFile.bytes('$_photosDir$name', bytes));
    });

    return ZipEncoder().encodeBytes(archive);
  }

  /// 导出分享包到用户选择的位置（REQ-21.5）。
  /// [destination] 仅移动端生效：saveToFolder 走系统文件选择器由用户挑文件夹直接落盘，
  /// systemShare 写入临时文件后拉起系统分享；桌面端始终是系统保存对话框。
  /// [packId] 为包的稳定分享 id，语义同 [buildPack]。返回导出文件路径，用户取消返回 null。
  Future<String?> exportPack({
    required String packName,
    required String author,
    required List<JournalTemplate> templates,
    List<CustomSticker> stickers = const [],
    Map<String, Uint8List> stickerBytes = const {},
    bool includePhotos = false,
    String? packId,
    Uint8List? coverBytes,
    PackExportDestination destination = PackExportDestination.systemShare,
  }) async {
    final bytes = await buildPack(
      packName: packName,
      author: author,
      templates: templates,
      stickers: stickers,
      stickerBytes: stickerBytes,
      includePhotos: includePhotos,
      packId: packId,
      coverBytes: coverBytes,
    );
    // 文件名含包名与日期（REQ-21.5）；扩展名固定 .zip，
    // 自创扩展名会让微信 / QQ 的「用其他应用打开」失效。
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final safeName = packName.replaceAll(_unsafeFileChars, '_').trim();
    final name = '拾页素材包-${safeName.isEmpty ? '未命名' : safeName}-$date.zip';
    const zipGroup = XTypeGroup(label: '素材包', extensions: ['zip']);

    if (kIsWeb) {
      // 浏览器：saveFile 直接触发下载。
      final saved = await FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );
      return saved;
    }

    if (isNativeMobile) {
      if (destination == PackExportDestination.saveToFolder) {
        try {
          // SAF「新建文档」选择器：用户挑文件夹（可进下载、网盘等任意目录），
          // 字节由系统写入所选位置，应用自身不需要任何存储权限。
          final saved = await FilePicker.platform.saveFile(
            fileName: name,
            type: FileType.custom,
            allowedExtensions: const ['zip'],
            bytes: bytes,
          );
          return saved;
        } on PlatformException {
          // 个别机型的文件选择器不可用时退回系统分享，保证导出仍然可用。
        }
      }
      // 个别机型选择器不可用时退回系统分享；内存 XFile 由分享层自行暂存。
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/zip', name: name),
          ],
          fileNameOverrides: [name],
        ),
      );
      return name;
    }

    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [zipGroup],
    );
    if (location == null) return null;
    await writeToUserPath(location.path, bytes);
    return location.path;
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

    final archive = _decodeZip(bytes, '这不是有效的拾页素材包（无法解压）');
    _guardArchive(archive);

    if (archive.findFile(_packFileName) == null) {
      throw SharePackFormatException('这不是拾页素材包（缺少 pack.json）');
    }
    return _parsePagenotePack(archive);
  }

  /// 自动识别入口（REQ-29）：三个导入入口（素材页选择文件、Android
  /// intent、Windows 双击）统一从这里走，单一入口决定「能不能导」。
  ///
  /// 与 [parsePack] 的差别：
  /// - 单包上限放宽到 [maxForeignPackBytes]（外部素材包多为已压缩图片）；
  /// - 拾页备份包（顶层 entries.json）给指路提示而不是误当素材包；
  /// - 没有拾页格式特征的 zip 交给 [ForeignPackService] 转换成纯贴纸包，
  ///   包括别的应用恰好也叫 pack.json 的情形（按 `app` 认亲字段区分）。
  SharePackData parsePackAuto(Uint8List bytes, {String? sourceName}) {
    if (bytes.lengthInBytes > maxForeignPackBytes) {
      final mb = maxForeignPackBytes ~/ (1024 * 1024);
      throw SharePackFormatException('素材包体积过大（超过 $mb MB），已拒绝导入');
    }

    // RAR / 7z 魔数先行识别（REQ-29.5）：zip 解析器对坏数据可能过于宽容
    // （解出空包而不报错），不能依赖解码失败来触发诊断。
    ForeignPackService.rejectUnsupportedContainer(bytes);

    final archive = _decodeZip(bytes, null);
    final declared = _guardArchive(archive);

    // 备份包（REQ-03）不是素材包：整包恢复有专门入口，
    // 走这里会把备份里的照片当成贴纸导进来。
    if (archive.findFile('entries.json') != null) {
      throw SharePackFormatException(
        '这是拾页备份文件，请到「设置 → 备份与恢复」里导入',
      );
    }

    if (archive.findFile(_packFileName) != null) {
      // 先看认亲字段：别的应用的 pack.json 仍按外部包兜底转换；
      // 是拾页自己的包才走原生解析（损坏、版本过高等错误照抛）。
      final meta = _tryReadMeta(archive);
      if (meta != null && meta['app'] == 'pagenote') {
        return _parsePagenotePack(archive);
      }
    }
    return ForeignPackService.instance.convert(
      archive,
      sourceName: sourceName,
      declaredBaseBytes: declared,
    );
  }

  /// 解出 zip；[corruptMessage] 非空时按拾页包口径报错（严格入口），
  /// 为空（自动识别入口）时交给外部包诊断，识别 RAR / 7z 给出指引。
  static Archive _decodeZip(Uint8List bytes, String? corruptMessage) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw corruptMessage != null
          ? SharePackFormatException(corruptMessage)
          : ForeignPackService.describeUnreadable(bytes);
    }
  }

  /// pack.json 的宽松读取：不存在或解析失败返回 null，
  /// 供自动识别入口探认亲字段用；严格入口的报错在 [_parsePagenotePack] 里。
  static Map<String, Object?>? _tryReadMeta(Archive archive) {
    final packFile = archive.findFile(_packFileName);
    if (packFile == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(packFile.content as List<int>));
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 拾页格式部分的解析：调用方保证 pack.json 存在（REQ-21.10 的闸门顺序）。
  SharePackData _parsePagenotePack(Archive archive) {
    final Map<String, Object?> meta;
    try {
      meta = (jsonDecode(
        utf8.decode(archive.findFile(_packFileName)!.content as List<int>),
      ) as Map)
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

    // 贴纸位图与模板照片分属两个目录；老包与不带照片的包没有 photos/，降级为空（NFR-07）。
    final stickerBytes = <String, Uint8List>{};
    final photoBytes = <String, Uint8List>{};
    Uint8List? coverBytes;
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = p.basename(f.name);
      if (name.isEmpty) continue;
      if (f.name.startsWith(_assetsDir)) {
        stickerBytes[name] = Uint8List.fromList(f.content as List<int>);
      } else if (f.name.startsWith(_photosDir)) {
        photoBytes[name] = Uint8List.fromList(f.content as List<int>);
      } else if (f.name == _coverFileName) {
        // 可选封面（REQ-27.5）：字节原样交给调用方，解码与尺寸闸在落盘时做。
        coverBytes = Uint8List.fromList(f.content as List<int>);
      }
    }

    return SharePackData(
      name: (meta['name'] ?? '') as String,
      author: (meta['author'] ?? '') as String,
      packId: meta['id'] as String?,
      templates: templates,
      stickers: stickers,
      stickerBytes: stickerBytes,
      photoBytes: photoBytes,
      coverBytes: coverBytes,
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
  /// 返回累计的声明体积，外部包转换在其余量里继续算嵌套条目（REQ-29）。
  int _guardArchive(Archive archive) {
    if (archive.length > maxArchiveFiles) {
      throw SharePackFormatException('素材包内容过多（超过 $maxArchiveFiles 项），已拒绝导入');
    }
    var total = 0;
    for (final f in archive) {
      if (!isSafeEntryName(f.name)) {
        throw SharePackFormatException('素材包包含非法路径「${f.name}」，已拒绝导入');
      }
      total += f.size;
      if (total > maxUnpackedBytes) {
        final mb = maxUnpackedBytes ~/ (1024 * 1024);
        throw SharePackFormatException('素材包解压后体积过大（超过 $mb MB），已拒绝导入');
      }
    }
    return total;
  }

  /// 条目名是否安全（NFR-06 防路径穿越）：拒绝绝对路径与 `..` 回溯。
  /// 外部包嵌套 zip 的内层条目同样用它把关（REQ-29）。
  static bool isSafeEntryName(String name) {
    if (name.isEmpty) return false;
    final normalized = name.replaceAll('\\', '/');
    if (normalized.startsWith('/') || _driveLetter.hasMatch(normalized)) {
      return false;
    }
    return !normalized.split('/').contains('..');
  }
}
