import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'stored_files.dart';

/// 全局实例：应用内统一经 [storedFiles] 读写二进制资产。
final StoredFiles storedFiles = StoredFilesImpl();

/// 原生端实现：逻辑 key（`attachments/<id>.jpg`）映射到
/// 应用文档目录下的真实文件，数据库里仍存绝对路径，与历史数据兼容。
class StoredFilesImpl implements StoredFiles {
  /// 文档根目录；测试可替换该钩子以避开 path_provider 插件。
  static Future<String> Function() documentsDir =
      () async => (await getApplicationDocumentsDirectory()).path;

  String? _root;

  Future<String> get root async => _root ??= await documentsDir();

  @override
  bool get hasFileSystem => true;

  /// 相对键（如 `stickers/<sha1>.png`）解析到文档根目录下；
  /// 绝对路径原样返回，兼容数据库里的历史附件路径。
  Future<String> _resolve(String pathOrKey) async =>
      p.isAbsolute(pathOrKey) ? pathOrKey : p.join(await root, pathOrKey);

  @override
  Future<String> write(String key, List<int> bytes) async {
    final target = await _resolve(key);
    final file = File(target);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
    return target;
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final file = File(await _resolve(path));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on IOException {
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = File(await _resolve(path));
      if (await file.exists()) await file.delete();
    } on IOException {
      // 忽略删除失败（文件可能已被移动）。
    }
  }

  @override
  Future<void> clearDir(String dir) async {
    final target = Directory(p.join(await root, dir));
    if (!await target.exists()) return;
    await for (final entity in target.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } on IOException {
          // 忽略单个文件删除失败。
        }
      }
    }
  }
}
