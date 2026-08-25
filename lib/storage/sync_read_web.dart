import 'dart:typed_data';

/// Web 端没有同步文件系统；FakeAsync 特判在 Web 上恒为 false，
/// 该入口不会被调用。
Uint8List? readStoredBytesSync(String path) =>
    throw UnsupportedError('Web 端不支持同步读取:$path');
