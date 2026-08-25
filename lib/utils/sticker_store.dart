import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/sticker_assets.dart';
import '../storage/stored_files.dart';

/// 自定义图片贴纸的落盘层（REQ-20）：文件按内容 sha1 命名存入
/// 存储层的 stickers/ 目录。内容寻址天然去重（REQ-20.2），也让
/// `img:<sha1>` 这个 key 跨设备稳定，是分享包能正确引用素材的基础（REQ-21）。
class StickerStore {
  StickerStore._();

  /// 贴纸在存储层下的逻辑目录名。
  static const _dir = 'stickers';

  /// 单张素材上限（REQ-20.5）：长边 1024px、2MB，超限自动压缩。
  static const maxEdge = 1024;
  static const maxBytes = 2 * 1024 * 1024;

  /// 解码前的尺寸硬闸（NFR-06）：单边像素上限。
  /// 8192 是移动端 GPU 纹理边长的常见上限，超过这个数的图连渲染都无从谈起，
  /// 已经不可能是正常素材，只可能是构造出来的攻击载荷。
  static const maxDecodeEdge = 8192;

  /// 解码前的尺寸硬闸（NFR-06）：像素总数上限（4096×4096）。
  /// 解码后按 RGBA 每像素 4 字节算约 64MB，是单张图能接受的内存天花板；
  /// 20MB 的 PNG 能解压成上万像素的方图（图像层解压炸弹），
  /// 必须在**解码之前**用文件头拦下，不能先解码再判断。
  static const maxDecodePixels = 4096 * 4096;

  static const _imageGroup = XTypeGroup(
    label: '图片',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
  );

  /// 打开系统图片选择器（REQ-20.1）；用户取消返回空。
  static Future<List<XFile>> pickImages() =>
      openFiles(acceptedTypeGroups: [_imageGroup]);

  /// 导入一张图片作为自定义贴纸（REQ-20.1）：尺寸闸（NFR-06）→ 解码 →
  /// 长边超限等比缩放 → 统一编码 PNG（保留 alpha）→ 按 sha1 落盘，
  /// 同一图片重复导入命中同一文件。
  /// 尺寸超限或解码失败返回 null，由调用方给出中文提示，不向 UI 抛异常。
  static Future<CustomSticker?> importFile(
    XFile file, {
    String name = '',
    String category = '我的',
  }) async {
    final Uint8List? png;
    try {
      final raw = await file.readAsBytes();
      // 巨图直接拒，不尝试压缩挽救：压缩本身就要先整张解码。
      if (!withinDecodeLimit(raw)) return null;
      png = await compute(_toPng, raw);
    } on Exception {
      return null;
    }
    if (png == null) return null;
    final id = idOf(png);
    await _write(id, png, '.png');
    final label = name.trim().isEmpty
        ? p.basenameWithoutExtension(file.name)
        : name.trim();
    return CustomSticker(
      id: id,
      name: label.isEmpty ? '贴纸' : label,
      category: category,
    );
  }

  /// 去白底（REQ-20.3）：接近纯白的像素 alpha 置 0，阈值边缘留一档
  /// 半透明过渡避免锯齿。解码失败原样返回，不打断用户操作。
  /// 面板是「先抠白再导入」，这一步先于 [importFile] 整张解码，
  /// 因此这里也要过尺寸闸（NFR-06）；未过闸时原样返回，
  /// 由随后的 [importFile] 统一拒绝并提示。
  static Future<Uint8List> removeWhiteBackground(
    Uint8List png, {
    int tolerance = 24,
  }) async {
    if (!withinDecodeLimit(png)) return png;
    try {
      final cut = await compute(_cutWhite, (bytes: png, tolerance: tolerance));
      return cut ?? png;
    } on Exception {
      return png;
    }
  }

  /// 压缩到 [maxEdge] / [maxBytes] 上限内的 PNG（REQ-20.5）：
  /// 与贴纸导入同一条归一化链，包封面（REQ-27.4）复用同一约束。
  /// 先经 [withinDecodeLimit] 过闸再调用；无法解码返回 null。
  /// 在后台 isolate 执行，避免大图卡住界面。
  static Future<Uint8List?> normalizeToPng(Uint8List bytes) {
    return compute(_toPng, bytes);
  }

  /// 不可信字节的归一化落盘（NFR-06 + REQ-20.5），备份恢复与分享包安装共用：
  /// 先读文件头过尺寸闸，再保证落盘结果不超出 [maxEdge] / [maxBytes]。
  ///
  /// 返回落盘后的 id（内容 sha1）与实际扩展名；空字节、格式无法识别、
  /// 尺寸超上限或解码失败一律返回 **null**，调用方跳过这一张继续导入其余素材，
  /// 不抛异常打断整包（REQ-21.3）。
  ///
  /// 已在上限内的字节原样落盘，不做无意义的重编码——重编码会让 sha1 漂移，
  /// 打断分享包里 `img:<sha1>` 的引用（REQ-21），而尺寸闸已保证解码安全。
  static Future<({String id, String ext})?> persistNormalizedBytes(
    Uint8List bytes, {
    String ext = '.png',
  }) async {
    if (bytes.isEmpty) return null;
    final size = _probeSize(bytes);
    if (size == null || !_withinLimit(size)) return null;

    if (max(size.width, size.height) <= maxEdge && bytes.length <= maxBytes) {
      final ok = safeExt(ext);
      final id = idOf(bytes);
      await _write(id, bytes, ok);
      return (id: id, ext: ok);
    }

    final Uint8List? png;
    try {
      png = await compute(_toPng, bytes);
    } on Exception {
      return null;
    }
    if (png == null) return null;
    final id = idOf(png);
    await _write(id, png, '.png');
    return (id: id, ext: '.png');
  }

  /// 解码前的尺寸闸（NFR-06）：只解析文件头，不解码像素。
  /// 格式无法识别或超出 [maxDecodeEdge] / [maxDecodePixels] 时返回 false，
  /// 此时调用方应直接跳过该图，不要试图压缩一张恶意构造的巨图。
  static bool withinDecodeLimit(Uint8List bytes) {
    final size = _probeSize(bytes);
    return size != null && _withinLimit(size);
  }

  static bool _withinLimit(({int width, int height}) size) =>
      size.width <= maxDecodeEdge &&
      size.height <= maxDecodeEdge &&
      size.width * size.height <= maxDecodePixels;

  /// 读图像头取画布尺寸；识别不了或头部损坏返回 null。
  /// `startDecode` 只走到尺寸信息为止，不会展开像素数据。
  static ({int width, int height})? _probeSize(Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return (width: info.width, height: info.height);
    } catch (_) {
      // 头部损坏的文件可能抛出各种越界错误，一律按无法识别处理。
      return null;
    }
  }

  /// 字节内容的 sha1，即贴纸 id 与文件名主干（分享包打包时复用）。
  static String idOf(List<int> bytes) => sha1.convert(bytes).toString();

  /// 已知 id 的存储路径（逻辑键）；扩展名经 [safeExt] 消毒，
  /// 读写两侧算出的文件名始终一致。
  static String pathOf(String id, String ext) =>
      '$_dir/$id${safeExt(ext)}';

  /// 落盘用的安全扩展名（NFR-06 路径消毒）。
  ///
  /// 分享包 stickers.json 里的 `ext` 与包内条目名不同，不经 zip 条目名校验，
  /// 直接拼进文件名可以用 `../` 逃出素材目录写到任意位置；
  /// 这里只放行「点 + 短字母数字」的扩展名，其余一律按 .png 处理。
  static String safeExt(String ext) => _extPattern.hasMatch(ext) ? ext : '.png';

  static final _extPattern = RegExp(r'^\.[A-Za-z0-9]{1,8}$');

  /// 读取素材字节（备份 REQ-20.6 与分享包 REQ-21.3 打包用）；缺失返回 null。
  static Future<Uint8List?> readBytes(String id, String ext) =>
      storedFiles.read(pathOf(id, ext));

  /// 清空素材目录中的全部文件（覆盖导入前调用）。
  static Future<void> clearAll() => storedFiles.clearDir(_dir);

  /// 删除素材文件；测试可替换该钩子以拦截删除操作。
  static Future<void> Function(String path) delete = deleteFile;

  static Future<void> deleteFile(String path) => storedFiles.delete(path);

  static Future<String> _write(String id, Uint8List bytes, String ext) =>
      storedFiles.write(pathOf(id, ext), bytes);

  /// 归一化为 PNG（REQ-20.5）：长边超限先等比缩放，体积仍超 2MB 则
  /// 逐档降尺寸重试。放在后台 isolate 执行，避免大图卡住导入动画。
  static Uint8List? _toPng(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var edge = min(max(decoded.width, decoded.height), maxEdge);
    var png = img.encodePng(_resize(decoded, edge));
    for (var i = 0; i < 3 && png.length > maxBytes; i++) {
      edge = (edge * 0.8).round();
      png = img.encodePng(_resize(decoded, edge));
    }
    return png;
  }

  static img.Image _resize(img.Image src, int edge) {
    final scale = edge / max(src.width, src.height);
    if (scale >= 1) return src;
    return img.copyResize(
      src,
      width: max(1, (src.width * scale).round()),
      height: max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  static Uint8List? _cutWhite(({Uint8List bytes, int tolerance}) job) {
    final decoded = img.decodeImage(job.bytes);
    if (decoded == null) return null;
    // 三通道图片无 alpha 可写，先补一条 alpha 通道。
    final image = decoded.numChannels == 4
        ? decoded
        : decoded.convert(numChannels: 4);
    final tolerance = job.tolerance.clamp(1, 96) / 255;
    final clear = 1 - tolerance;
    final keep = clear - tolerance;
    // 按 [0,1] 归一化比较，兼容 16 位与浮点位深的图片。
    for (final px in image) {
      final low = min(px.rNormalized, min(px.gNormalized, px.bNormalized));
      if (low >= clear) {
        px.a = 0;
      } else if (low > keep) {
        px.aNormalized = min(px.aNormalized, (clear - low) / tolerance);
      }
    }
    return img.encodePng(image);
  }
}
