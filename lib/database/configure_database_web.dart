import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web 端：sqlite3 编译为 wasm，在专用 worker 内运行，
/// 数据经浏览器 OPFS/IndexedDB 持久化（web/sqlite3.wasm + web/sqflite_sw.js）。
void configureDatabase() {
  databaseFactory = databaseFactoryFfiWeb;
}
