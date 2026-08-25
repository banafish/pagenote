import 'package:flutter/material.dart';

/// Web 端没有系统分享包转发通道，直接透传子组件。
class SharePackGate extends StatelessWidget {
  const SharePackGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
