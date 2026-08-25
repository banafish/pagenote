/// 存储层图片的统一渲染入口。
///
/// 数据库里保存的图片路径在原生端是绝对文件路径、Web 端是
/// IndexedDB 键，本文件按平台条件导出对应的 `storedImageProvider`
/// 实现；所有渲染点一律写 `Image(image: storedImageProvider(path))`，
/// 不得直接使用 Image.file。
library;
export 'stored_image_io.dart'
    if (dart.library.js_interop) 'stored_image_web.dart';
