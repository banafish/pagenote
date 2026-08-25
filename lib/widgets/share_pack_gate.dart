/// 分享包入口 Gate（条件导入入口）：原生端监听系统转发的 zip，
/// Web 端没有该通道，直接透传子组件。
library;
export 'share_pack_gate_io.dart'
    if (dart.library.js_interop) 'share_pack_gate_stub.dart';
