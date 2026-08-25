/// Web 端没有 dart:io，也不存在 Flutter 测试的 FakeAsync 约束
/// （flutter_test 在 web 上同样可用 compute 的同步回退，无需特判）。
bool get isFlutterTest => false;

/// Web 端不是桌面操作系统（浏览器环境按移动/桌面布局自适应，
/// 不用于区分系统能力）。
bool get isDesktopOS => false;
