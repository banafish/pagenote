import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:path/path.dart' as p;

import '../models/sticker_assets.dart';
import 'share_pack_service.dart';

/// 外部素材包兼容导入（REQ-29）。
///
/// 国内主流手账 App（时光手帐 / 念念手帐 / 微手帐等）都没有公开的第三方
/// 素材包格式，用户之间实际流通的「素材包」绝大多数是**免抠 PNG 的 zip
/// 压缩包**（素材站购买、微信群 / QQ 群分享），iPad 阵营的 GoodNotes /
/// Zinnia 素材文件同样以 zip 为容器。本服务把这类「非拾页格式」的压缩包
/// 统一转换成纯贴纸的 [SharePackData]，复用分享包既有的预览勾选、落库与
/// 尺寸闸全链路（NFR-06），不新增第二条导入管线。
class ForeignPackService {
  ForeignPackService._();

  static final ForeignPackService instance = ForeignPackService._();

  /// 可导入的图片扩展名（小写、含点）。gif/webp 按静态图渲染。
  static const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};

  /// 压缩包嵌套展开的最大层数（zip 里套 zip 是素材站分发的常见形态）。
  static const _maxZipDepth = 2;

  /// 素材名展示上限：超长文件名截断，预览格与面板都按一行排版。
  static const _maxNameLength = 40;

  // ---------------- 主入口 ----------------

  /// 把外部压缩包转换成可导入的纯贴纸包。
  ///
  /// [archive] 必须已通过 [SharePackService] 的解包安全校验（条目名 /
  /// 条目数 / 声明总体积）；[declaredBaseBytes] 是外层校验时累计的声明
  /// 体积，内层嵌套 zip 的条目体积在它的余量里继续计算（NFR-06）。
  /// 包内找不到任何可导入图片时抛 [SharePackFormatException]。
  SharePackData convert(
    Archive archive, {
    String? sourceName,
    int declaredBaseBytes = 0,
  }) {
    final scan = _Scan(totalBytes: declaredBaseBytes);
    _scanArchive(archive, scan, depth: 0, scopeName: null);

    if (scan.images.isEmpty) {
      throw SharePackFormatException(
        '包内没有找到可导入的图片素材（支持 PNG / JPG / WebP / GIF / BMP）',
      );
    }

    // 同一张图在不同子目录重复放置是打包时的常见冗余，按内容去重。
    final byId = <String, _FoundImage>{};
    for (final image in scan.images) {
      byId.putIfAbsent(image.id, () => image);
    }
    final images = byId.values.toList();

    return SharePackData(
      name: _packName(images, sourceName),
      author: '',
      // 内容指纹作为包的稳定身份：同一个压缩包重复导入归位到同一个包
      // （与拾页包按 pack.json id 归位同一套语义，REQ-29.4）。
      packId: _foreignPackId(images),
      templates: const [],
      stickers: [
        for (var i = 0; i < images.length; i++) images[i].toSticker(i),
      ],
      stickerBytes: {for (final image in images) image.fileName: image.bytes},
      isForeign: true,
    );
  }

  /// zip 解码前的容器魔数检查（REQ-29.5）：RAR / 7z 是素材包最常见的
  /// 「导不进来」原因，且解析器对坏数据可能过于宽容（解出空包而不报错），
  /// 不能依赖解码失败来触发诊断，必须先行识别并给出明确指引。
  static void rejectUnsupportedContainer(Uint8List bytes) {
    if (_startsWith(bytes, const [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) {
      throw SharePackFormatException(
        '这是 RAR 压缩包，暂不支持直接导入：请先解压，再把里面的图片打包成 zip 后导入',
      );
    }
    if (_startsWith(bytes, const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
      throw SharePackFormatException(
        '这是 7z 压缩包，暂不支持直接导入：请先解压，再把里面的图片打包成 zip 后导入',
      );
    }
  }

  /// zip 打不开时的可读诊断（REQ-29.5）：容器魔数给出明确指引，
  /// 其余按损坏处理。
  static SharePackFormatException describeUnreadable(Uint8List bytes) {
    try {
      rejectUnsupportedContainer(bytes);
    } on SharePackFormatException catch (e) {
      return e;
    }
    return SharePackFormatException('这不是有效的素材包（无法解压）');
  }

  // ---------------- 扫描 ----------------

  void _scanArchive(
    Archive archive,
    _Scan scan, {
    required int depth,
    required String? scopeName,
  }) {
    for (final f in archive) {
      if (!f.isFile) continue;
      // 嵌套 zip 的内层条目不再整体拒包（外层已把关），坏条目跳过即可：
      // 名字只用于展示，字节不落盘，不构成路径穿越风险。
      final path = f.name.replaceAll('\\', '/');
      if (!SharePackService.isSafeEntryName(f.name) || _isJunk(path)) continue;

      scan.fileCount++;
      if (scan.fileCount > SharePackService.maxArchiveFiles) {
        throw SharePackFormatException(
          '素材包内容过多（超过 ${SharePackService.maxArchiveFiles} 项），已拒绝导入',
        );
      }

      final bytes = f.readBytes();
      if (bytes == null || bytes.isEmpty) continue;
      _charge(scan, f, bytes, declared: depth == 0);

      final ext = p.extension(path).toLowerCase();
      if (ext == '.zip') {
        // 套娃 zip：展开一层继续扫（素材站经常整站打包再套一层）。
        if (depth + 1 >= _maxZipDepth) continue;
        try {
          final inner = ZipDecoder().decodeBytes(bytes);
          _scanArchive(
            inner,
            scan,
            depth: depth + 1,
            scopeName: _scopeName(path),
          );
        } on SharePackFormatException {
          rethrow;
        } catch (_) {
          // 内层损坏只跳过这一个，不影响其余素材。
        }
        continue;
      }
      if (!_imageExts.contains(ext)) continue;

      // 目录段按 zip 条目的 '/' 手工切分（不依赖 path 包的平台样式），
      // 与文件名一样做编码还原：旧分组字段与顶层目录名都来自这里。
      final segments = [
        for (final segment in path.split('/'))
          if (segment.isNotEmpty) recoverEntryName(segment),
      ];
      final dirSegments = segments..removeLast();
      scan.images.add(
        _FoundImage(
          bytes: bytes,
          ext: ext,
          name: _displayName(path),
          category: _categoryOf(dirSegments, depth: depth, scopeName: scopeName),
          topFolder: depth == 0 && dirSegments.isNotEmpty
              ? dirSegments.first
              : null,
        ),
      );
    }
  }

  /// 计入解压体积预算（NFR-06）：外层条目的声明体积已在整体校验里算过，
  /// 这里只补声明与实际的差值；内层条目全额计入。
  static void _charge(
    _Scan scan,
    ArchiveFile f,
    Uint8List bytes, {
    required bool declared,
  }) {
    if (!declared) scan.totalBytes += f.size;
    scan.totalBytes += bytes.lengthInBytes - f.size;
    if (scan.totalBytes > SharePackService.maxUnpackedBytes) {
      final mb = SharePackService.maxUnpackedBytes ~/ (1024 * 1024);
      throw SharePackFormatException('素材包解压后体积过大（超过 $mb MB），已拒绝导入');
    }
  }

  /// 系统与打包工具的垃圾条目：macOS 元数据、Windows 缩略图缓存、隐藏文件。
  static bool _isJunk(String path) {
    final segments = path.split('/');
    final base = segments.last;
    if (base.isEmpty || base.startsWith('.')) return true;
    if (base == 'Thumbs.db' || base == 'desktop.ini') return true;
    return segments.any((s) => s == '__MACOSX' || s.startsWith('.'));
  }

  static String _scopeName(String zipPath) =>
      p.basenameWithoutExtension(zipPath);

  /// 旧「分组」字段的透传值：取图片所在的直接子文件夹名；根目录的图退回
  /// 内层 zip 名；两者都没有（根目录平铺）用默认值。分组 UI 已下线，
  /// 只随数据往返保留，不参与展示。
  static String _categoryOf(
    List<String> dirSegments, {
    required int depth,
    required String? scopeName,
  }) {
    if (dirSegments.isNotEmpty) return dirSegments.last;
    if (depth > 0 && scopeName != null && scopeName.isNotEmpty) {
      return scopeName;
    }
    return '我的';
  }

  /// 贴纸展示名：文件名主干（去扩展名），控制字符折叠为空格；
  /// 取不出名字的交给 [CustomSticker] 侧按序号兜底。
  static String _displayName(String path) {
    final recovered = recoverEntryName(p.basename(path));
    final stem = p.basenameWithoutExtension(recovered)
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stem.isEmpty) return '';
    return stem.length > _maxNameLength
        ? stem.substring(0, _maxNameLength)
        : stem;
  }

  // ---------------- 包名与包身份 ----------------

  /// 包名：优先用来源文件名主干（用户下载 / 分享时看到的那个名字），
  /// 其次是包内唯一的顶层目录名（素材站打包的常见结构），兜底「外部素材包」。
  static String _packName(List<_FoundImage> images, String? sourceName) {
    if (sourceName != null) {
      final stem = p.basenameWithoutExtension(sourceName.trim())
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (stem.isNotEmpty) return stem;
    }
    final tops = {
      for (final image in images)
        if (image.topFolder != null) image.topFolder!,
    };
    if (tops.length == 1) return tops.single;
    return '外部素材包';
  }

  /// 外部包的稳定身份：全部素材内容 sha1 排序后再哈希。
  /// 与内容一一对应——同一压缩包（或其改名的副本）重复导入归位同一个包，
  /// 内容不同的包永不冲突。
  static String _foreignPackId(List<_FoundImage> images) {
    final ids = [for (final image in images) image.id]..sort();
    return 'foreign-${sha1.convert(utf8.encode(ids.join(',')))}';
  }

  // ---------------- 条目名编码还原 ----------------

  static final _percentSeq = RegExp('%[0-9A-Fa-f]{2}');

  /// zip 条目名的编码还原（REQ-29.3），按「百分号解码 → UTF-8 → GBK」尝试：
  /// - 网页 / 网盘打包的文件名常为百分号编码（`%E7%A7%8B.png`）；
  /// - archive 包对非 UTF-8 文件名退回逐字节 charCodes，Windows 下
  ///   WinRAR / 好压等按 GBK 打包的中文文件名会呈现为 latin1 乱码，
  ///   把这些「字符即字节」的乱码还原成原始字节后按 GBK 解码即可恢复。
  /// 还原失败（本就不是中文、或字节无法解释）时原样返回。
  static String recoverEntryName(String raw) {
    String? result;
    if (_percentSeq.allMatches(raw).length >= 2) {
      final bytes = _percentBytes(raw);
      if (bytes != null) {
        result = _tryUtf8(bytes) ?? _tryGbk(bytes);
      }
    }
    if (result == null) {
      final units = raw.codeUnits;
      // 仅当字符串呈现为「字符即字节」的 latin1 形式时才尝试 GBK：
      // 真正的 UTF-8 中文（charCode 超过 0xFF）还原字节再解必然是错的。
      if (units.any((c) => c >= 0x80) && units.every((c) => c <= 0xFF)) {
        result = _tryGbk(Uint8List.fromList(units));
      }
    }
    return result ?? raw;
  }

  static Uint8List? _percentBytes(String raw) {
    final codes = raw.codeUnits;
    final out = BytesBuilder();
    var decoded = false;
    for (var i = 0; i < codes.length;) {
      final c = codes[i];
      if (c == 0x25 && i + 2 < codes.length) {
        final hi = _hexVal(codes[i + 1]);
        final lo = _hexVal(codes[i + 2]);
        if (hi != null && lo != null) {
          out.addByte(hi * 16 + lo);
          decoded = true;
          i += 3;
          continue;
        }
      }
      out.addByte(c & 0xFF);
      i++;
    }
    return decoded ? out.toBytes() : null;
  }

  static int? _hexVal(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return null;
  }

  static String? _tryUtf8(List<int> bytes) {
    try {
      return _plausible(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static String? _tryGbk(List<int> bytes) {
    try {
      return _plausible(const GbkCodec(allowMalformed: true).decode(bytes));
    } catch (_) {
      return null;
    }
  }

  /// 还原结果的基本校验：不许有替换符与控制字符。
  static String? _plausible(String s) {
    if (s.isEmpty) return null;
    for (final c in s.codeUnits) {
      if (c == 0xFFFD || c < 0x20 || c == 0x7F) return null;
    }
    return s;
  }

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.lengthInBytes < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}

/// 扫描过程的累计状态：找到的图片、条目数与解压体积预算。
class _Scan {
  _Scan({required this.totalBytes});

  final images = <_FoundImage>[];
  int fileCount = 0;
  int totalBytes;
}

/// 包内发现的一张候选素材图。
class _FoundImage {
  _FoundImage({
    required this.bytes,
    required this.ext,
    required this.name,
    required this.category,
    required this.topFolder,
  });

  final Uint8List bytes;

  /// 小写、含点的真实扩展名（白名单内）。
  final String ext;

  /// 清洗后的展示名；空串表示取不出名字。
  final String name;
  final String category;
  final String? topFolder;

  late final String id = sha1.convert(bytes).toString();

  /// 与贴纸落盘命名 `<sha1><ext>` 对齐（REQ-20.2），导入页按它取字节。
  String get fileName => '$id$ext';

  CustomSticker toSticker(int index) => CustomSticker(
    id: id,
    name: name.isEmpty ? '素材 ${index + 1}' : name,
    category: category,
    ext: ext,
  );
}
