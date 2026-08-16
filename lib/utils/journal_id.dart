import 'dart:math';

/// 生成简短唯一 id。
String makeId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(0xffffff);
  return '$ts-${rand.toRadixString(16).padLeft(6, '0')}';
}
