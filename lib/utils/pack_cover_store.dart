import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'sticker_store.dart';

/// 素材包封面的落盘层（REQ-27）：文件按内容 sha1 命名存入
/// documents/pack_covers/，与贴纸的 stickers/ 分开，避免污染自定义贴纸索引。
///
/// 封面有两条不可信来源——用户相册与分享包内的 cover.png——
/// 写盘前一律走与贴纸相同的安全链（NFR-06 / NFR-14）：
/// 先读文件头过解码尺寸闸，再压缩到长边 ≤1024px、单文件 ≤2MB（REQ-27.4）。
/// 落盘结果统一为 PNG，文件名即 `<sha1>.png`，DB 只存这个相对名。
class PackCoverStore {
  PackCoverStore._();

  static const maxEdge = StickerStore.maxEdge;
  static const maxBytes = StickerStore.maxBytes;

  /// 封面目录绝对路径，[ensureDir] 后可用；同步的 [pathOf] 依赖它。
  static String _root = '';

  /// 导入一张封面图（REQ-27.2 上传 / REQ-27.5 分享包导入共用）：
  /// 尺寸闸（NFR-06/14）→ 解码压缩到上限内 → 按 sha1 落盘。
  /// 空字节、格式无法识别、尺寸超解码上限或解码失败返回 null，
  /// 调用方按返回值提示，不向 UI 抛异常。
  static Future<String?> importFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    // 巨图直接拒，不尝试压缩挽救：压缩本身就要先整张解码（NFR-06）。
    if (!StickerStore.withinDecodeLimit(bytes)) return null;
    final Uint8List png;
    try {
      final out = await StickerStore.normalizeToPng(bytes);
      if (out == null) return null;
      png = out;
    } on Exception {
      return null;
    }
    final name = '${StickerStore.idOf(png)}.png';
    final dir = await ensureDir();
    final file = File(p.join(dir.path, name));
    if (!await file.exists()) {
      await file.writeAsBytes(png, flush: true);
    }
    return name;
  }

  /// 已知封面文件名的绝对路径；需先 [ensureDir]。
  /// 只取 basename，DB 里的名字即使被篡改也逃不出封面目录（NFR-14）。
  static String pathOf(String fileName) => p.join(_root, p.basename(fileName));

  /// 读取封面字节（分享包整包导出 REQ-27.6 与备份 REQ-27.7 打包用）；
  /// 缺失返回 null。
  static Future<Uint8List?> readBytes(String fileName) async {
    try {
      final file = File(pathOf(fileName));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on IOException {
      return null;
    }
  }

  /// 删除封面文件（移除封面 / 删除包 / 解散包，REQ-27.8）；测试可替换。
  static Future<void> Function(String path) delete = deleteFile;

  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on IOException {
      // 忽略删除失败（文件可能已被移动）。
    }
  }

  /// 封面目录（不存在则创建），并缓存路径供同步的 [pathOf] 使用。
  static Future<Directory> ensureDir() async {
    final dir = Directory(p.join(await documentsDir(), 'pack_covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir.path;
    return dir;
  }

  /// 清空封面目录中的全部文件（备份覆盖导入前调用）。
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

  /// 文档根目录；默认与 [StickerStore.documentsDir] 同源——测试替换
  /// StickerStore 的钩子时封面目录一并指到临时目录，行为与贴纸一致。
  static Future<String> Function() documentsDir = _documentsDir;

  static Future<String> _documentsDir() => StickerStore.documentsDir();
}
