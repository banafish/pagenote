import 'dart:typed_data';

/// 应用内二进制资产的统一存取层。
///
/// 手账附件、自定义贴纸与包封面在数据库里只存「路径字符串」，
/// 本层负责把字符串落到具体介质：
/// - 原生端（Android/Windows）：真实文件系统，路径为绝对路径，与历史行为一致；
/// - Web 端：IndexedDB 键值对，路径为形如 `attachments/<id>.jpg` 的相对键，
///   没有真实文件系统。
///
/// 条件导入入口见 [storedFiles]；UI 与服务层一律经由本抽象读写，
/// 不直接触碰 dart:io。
export 'stored_files_io.dart'
    if (dart.library.js_interop) 'stored_files_web.dart';

abstract interface class StoredFiles {
  /// 写入内容到 [key] 对应的位置（如 `stickers/<sha1>.png`），
  /// 返回应存入数据库的路径字符串。重复写入同一 key 幂等覆盖。
  Future<String> write(String key, List<int> bytes);

  /// 读取 [write] 返回的路径对应的字节；不存在或无法识别返回 null。
  Future<Uint8List?> read(String path);

  /// 删除单个文件；目标不存在时静默成功。
  Future<void> delete(String path);

  /// 清空某个逻辑目录（如 `attachments`）下的全部文件。
  Future<void> clearDir(String dir);

  /// 当前介质是否为真实文件系统（用于决定能否把路径交给系统分享等场景）。
  bool get hasFileSystem;
}
