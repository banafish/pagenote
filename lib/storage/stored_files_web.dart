import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'stored_files.dart';

/// 全局实例：应用内统一经 [storedFiles] 读写二进制资产。
final StoredFiles storedFiles = StoredFilesImpl();

/// Web 端实现：逻辑 key（`attachments/<id>.jpg`）直接作为 IndexedDB
/// 对象仓库的主键，数据库里存的路径即 key 本身。浏览器没有文件系统，
/// 渲染端通过同一抽象异步取字节。
class StoredFilesImpl implements StoredFiles {
  static const _dbName = 'pagenote_files';
  static const _storeName = 'files';

  Database? _db;

  Future<Database> get _database async {
    final factory = getIdbFactory();
    if (factory == null) {
      throw StateError('当前浏览器环境不支持 IndexedDB');
    }
    return _db ??= await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_storeName)) {
          event.database.createObjectStore(_storeName);
        }
      },
    );
  }

  @override
  bool get hasFileSystem => false;

  @override
  Future<String> write(String key, List<int> bytes) async {
    final db = await _database;
    await db
        .transaction(_storeName, idbModeReadWrite)
        .objectStore(_storeName)
        .put(Uint8List.fromList(bytes), key);
    return key;
  }

  @override
  Future<Uint8List?> read(String path) async {
    if (!_isManagedKey(path)) return null;
    try {
      final db = await _database;
      final value = await db
          .transaction(_storeName, idbModeReadOnly)
          .objectStore(_storeName)
          .getObject(path);
      if (value is List<int>) return Uint8List.fromList(value);
      return null;
    } catch (_) {
      // 记录缺失或存储不可用（如隐私模式）时按不存在处理。
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final db = await _database;
      await db
          .transaction(_storeName, idbModeReadWrite)
          .objectStore(_storeName)
          .delete(path);
    } catch (_) {
      // 目标本就不存在，忽略。
    }
  }

  @override
  Future<void> clearDir(String dir) async {
    final prefix = '$dir/';
    try {
      final db = await _database;
      await db
          .transaction(_storeName, idbModeReadWrite)
          .objectStore(_storeName)
          // U+FFFF 是合法 Unicode 码点的上界，作为上开区间端点
          // 可精确圈定该前缀下的所有键。
          .delete(KeyRange.bound(prefix, '$prefix\uFFFF', false, true));
    } catch (_) {
      // 目录本就为空或存储不可用，忽略。
    }
  }

  /// 路径是否是本层写出的相对键（`目录/文件名` 形式）；
  /// 其他平台的绝对路径在 Web 上无从读取，一律按缺失处理。
  static bool _isManagedKey(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      return false;
    }
    if (path.contains(':')) return false;
    final slash = path.indexOf('/');
    return slash > 0 && slash < path.length - 1;
  }
}
