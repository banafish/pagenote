import 'dart:io';

/// 把字节写到用户通过系统对话框选定的绝对路径（原生端真实文件）。
Future<void> writeToUserPath(String path, List<int> bytes) async {
  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}
