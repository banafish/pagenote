import 'dart:io';

/// 原生端：Flutter 测试跑在 FakeAsync 环境里，不推进真实 isolate。
bool get isFlutterTest => Platform.environment['FLUTTER_TEST'] == 'true';

/// 原生端是否为桌面操作系统（Windows/macOS/Linux）。
bool get isDesktopOS =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
