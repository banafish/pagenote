/// 运行环境探测的条件导入入口。
library;
export 'env_io.dart' if (dart.library.js_interop) 'env_web.dart';
