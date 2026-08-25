import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 原生端：桌面（Windows/Linux）用 sqlite3 FFI 实现；
/// Android/iOS 用自带平台实现，不动全局工厂。
void configureDatabase() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
