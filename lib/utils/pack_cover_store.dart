import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../storage/stored_files.dart';
import 'sticker_store.dart';

/// 素材包封面的落盘层（REQ-27）：文件按内容 sha1 命名存入
/// 存储层的 pack_covers/ 目录，与贴纸的 stickers/ 分开，避免污染自定义贴纸索引。
///
/// 封面有两条不可信来源——用户相册与分享包内的 cover.png——
/// 落盘前一律走与贴纸相同的安全链（NFR-06 / NFR-14）：
/// 先读文件头过解码尺寸闸，再压缩到长边 ≤1024px、单文件 ≤2MB（REQ-27.4）。
/// 落盘结果统一为 PNG，文件名即 `<sha1>.png`，DB 只存这个相对名。
class PackCoverStore {
  PackCoverStore._();

  /// 封面在存储层下的逻辑目录名。
  static const _dir = 'pack_covers';

  static const maxEdge = StickerStore.maxEdge;
  static const maxBytes = StickerStore.maxBytes;

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
    await storedFiles.write(pathOf(name), png);
    return name;
  }

  /// 已知封面文件名的存储路径；只取 basename，
  /// DB 里的名字即使被篡改也逃不出封面目录（NFR-14）。
  static String pathOf(String fileName) =>
      '$_dir/${p.basename(fileName)}';

  /// 读取封面字节（分享包整包导出 REQ-27.6 与备份 REQ-27.7 打包用）；
  /// 缺失返回 null。
  static Future<Uint8List?> readBytes(String fileName) =>
      storedFiles.read(pathOf(fileName));

  /// 删除封面文件（移除封面 / 删除包 / 解散包，REQ-27.8）；测试可替换。
  static Future<void> Function(String path) delete = deleteFile;

  static Future<void> deleteFile(String path) => storedFiles.delete(path);

  /// 清空封面目录中的全部文件（备份覆盖导入前调用）。
  static Future<void> clearAll() => storedFiles.clearDir(_dir);
}
