import 'dart:io';
import 'dart:typed_data';

/// 同步读取存储层字节。生产代码一律走 [storedFiles].read 的异步接口；
/// 本入口仅供 FakeAsync 测试环境使用，路径为绝对文件路径。
Uint8List? readStoredBytesSync(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  } on IOException {
    return null;
  }
}
