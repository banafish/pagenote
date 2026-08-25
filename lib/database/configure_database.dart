/// 数据库平台工厂的初始化（条件导入入口）。
library;
export 'configure_database_io.dart'
    if (dart.library.js_interop) 'configure_database_web.dart';
