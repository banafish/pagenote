import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/sticker_assets.dart';

/// 自定义图片贴纸的落盘层（REQ-20）：文件按内容 sha1 命名存入
/// documents/stickers/。内容寻址天然去重（REQ-20.2），也让 `img:<sha1>`
/// 这个 key 跨设备稳定，是分享包能正确引用素材的基础（REQ-21）。
class StickerStore {
  StickerStore._();

  /// 单张素材上限（REQ-20.5）：长边 1024px、2MB，超限自动压缩。
  static const maxEdge = 1024;
  static const maxBytes = 2 * 1024 * 1024;

  static const _imageGroup = XTypeGroup(
    label: '图片',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
  );

  /// 素材目录绝对路径，[ensureDir] 后可用；同步的 [pathOf] 依赖它。
  static String _root = '';

  /// 打开系统图片选择器（REQ-20.1）；用户取消返回空。
  static Future<List<XFile>> pickImages() =>
      openFiles(acceptedTypeGroups: [_imageGroup]);

  /// 导入一张图片作为自定义贴纸（REQ-20.1）：解码 → 长边超限等比缩放 →
  /// 统一编码 PNG（保留 alpha）→ 按 sha1 落盘，同一图片重复导入命中同一文件。
  /// 解码失败返回 null，由调用方给出中文提示，不向 UI 抛异常。
  static Future<CustomSticker?> importFile(
    XFile file, {
    String name = '',
    String category = '我的',
  }) async {
    final Uint8List? png;
    try {
      png = await compute(_toPng, await file.readAsBytes());
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
  static Future<Uint8List> removeWhiteBackground(
    Uint8List png, {
    int tolerance = 24,
  }) async {
    try {
      final cut = await compute(_cutWhite, (bytes: png, tolerance: tolerance));
      return cut ?? png;
    } on Exception {
      return png;
    }
  }

  /// 按内容 sha1 落盘并返回绝对路径；同 sha1 的文件已存在则直接复用。
  static Future<String> persistBytes(Uint8List bytes, String ext) =>
      _write(idOf(bytes), bytes, ext.isEmpty ? '.png' : ext);

  /// 字节内容的 sha1，即贴纸 id 与文件名主干（分享包打包时复用）。
  static String idOf(List<int> bytes) => sha1.convert(bytes).toString();

  /// 已知 id 的文件路径；需先 [ensureDir]（provider 加载时已调用）。
  static String pathOf(String id, String ext) => p.join(_root, '$id$ext');

  /// 读取素材字节（备份 REQ-20.6 与分享包 REQ-21.3 打包用）；缺失返回 null。
  static Future<Uint8List?> readBytes(String id, String ext) async {
    try {
      final file = File(pathOf(id, ext));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on IOException {
      return null;
    }
  }

  /// 素材目录（不存在则创建），并缓存路径供同步的 [pathOf] 使用。
  static Future<Directory> ensureDir() async {
    final dir = Directory(p.join(await documentsDir(), 'stickers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir.path;
    return dir;
  }

  /// 清空素材目录中的全部文件（覆盖导入前调用）。
  static Future<void> clearAll() async {
    final dir = await ensureDir();
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } on IOException {
          // 忽略单个文件删除失败。
        }
      }
    }
  }

  /// 文档根目录；测试可替换该钩子以避开 path_provider 插件。
  static Future<String> Function() documentsDir = _documentsDir;

  static Future<String> _documentsDir() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// 删除素材文件；测试可替换该钩子以拦截文件操作。
  static Future<void> Function(String path) delete = deleteFile;

  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on IOException {
      // 忽略删除失败（文件可能已被移动）。
    }
  }

  static Future<String> _write(String id, Uint8List bytes, String ext) async {
    final dir = await ensureDir();
    final target = p.join(dir.path, '$id$ext');
    final file = File(target);
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return target;
  }

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
