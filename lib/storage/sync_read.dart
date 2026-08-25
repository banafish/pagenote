/// 存储层同步读取（条件导入入口）。
///
/// 仅服务一个场景：widget 测试的 FakeAsync 环境不推进真实异步 IO，
/// 裁剪对话框在 FLUTTER_TEST 下需要同步拿到字节才能复现旧有同步链路。
library;
export 'sync_read_io.dart'
    if (dart.library.js_interop) 'sync_read_web.dart';
