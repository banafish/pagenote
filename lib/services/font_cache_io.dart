import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'font_cache.dart';

/// 全局实例：字体下载缓存统一经 [fontCache] 读写。
final FontCache fontCache = FontCacheImpl();

/// 原生端实现：key（`v1/<字体文件名>`）映射到应用支持目录 fonts/ 下的
/// 真实文件。用支持目录而非文档目录，避免缓存出现在用户可见的存储区。
class FontCacheImpl implements FontCache {
  /// 缓存根目录；测试可替换该钩子以避开 path_provider 插件。
  static Future<String> Function() rootDir =
      () async => (await getApplicationSupportDirectory()).path;

  String? _root;

  Future<String> get root async => _root ??= await rootDir();

  Future<String> _resolve(String key) async =>
      p.join(await root, 'fonts', key);

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = File(await _resolve(key));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on IOException {
      return null;
    }
  }

  @override
  Future<void> write(String key, List<int> bytes) async {
    try {
      final file = File(await _resolve(key));
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on IOException {
      // 缓存写失败不影响本次使用（字节仍在内存中参与注册）。
    }
  }
}
