import 'dart:typed_data';

import 'font_cache.dart';

/// web 端空实现：按需字体与部署同源，rootBundle 可随时重新获取，
/// 不需要本地缓存。
final FontCache fontCache = _NoopFontCache();

class _NoopFontCache implements FontCache {
  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> write(String key, List<int> bytes) async {}
}
