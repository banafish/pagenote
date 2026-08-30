import 'dart:typed_data';

/// 花样字体下载缓存的介质抽象。
///
/// Android release 剔除包的花样字体首次下载后落盘，之后每次启动从缓存
/// 注册（FontLoader 的动态注册不跨进程持久）。原生端落在应用支持目录，
/// web 端字体与部署同源、无需缓存。
///
/// 条件导入入口见 [fontCache]；服务层一律经由本抽象读写，不直接触碰 dart:io。
export 'font_cache_io.dart' if (dart.library.js_interop) 'font_cache_web.dart';

abstract interface class FontCache {
  /// 读取 [key]（如 `v1/MaShanZheng-Regular.ttf`）对应的字节；不存在返回 null。
  Future<Uint8List?> read(String key);

  /// 写入 [key] 对应的内容，重复写入幂等覆盖。失败静默——缓存缺失只
  /// 影响下次启动的加载速度，不影响本次使用。
  Future<void> write(String key, List<int> bytes);
}
