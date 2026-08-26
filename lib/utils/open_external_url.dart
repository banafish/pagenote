/// 外链打开的条件导入入口。
///
/// 品牌页仅 Web 端展示，原生端不会触达；仍走条件导入，
/// 保证品牌页代码在全部平台可编译。
library;
export 'open_external_url_io.dart'
    if (dart.library.js_interop) 'open_external_url_web.dart';
