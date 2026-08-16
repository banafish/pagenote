import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'journal_id.dart';

/// 图片附件：选择图片并复制到应用私有目录，保证长期可访问。
class Attachments {
  Attachments._();

  static const maxImages = 9;

  static const _imageGroup = XTypeGroup(
    label: '图片',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
  );

  /// 打开系统图片选择器，返回复制后的附件绝对路径列表；用户取消返回空。
  /// [remaining] 为还能添加的图片数量，超出部分会被截断。
  static Future<List<String>> pickImages({int remaining = maxImages}) async {
    if (remaining <= 0) return [];
    final files = await openFiles(acceptedTypeGroups: [_imageGroup]);
    if (files.isEmpty) return [];
    final picked = files.take(remaining).toList();
    return Future.wait(picked.map(persist));
  }

  /// 将文件复制进附件目录，返回新路径。
  static Future<String> persist(XFile file) async {
    final dir = await _attachmentsDir();
    final ext = p.extension(file.path);
    final name = '${makeId()}${ext.isEmpty ? '.img' : ext}';
    final target = p.join(dir.path, name);
    await File(file.path).copy(target);
    return target;
  }

  static Future<Directory> _attachmentsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on IOException {
      // 忽略删除失败（文件可能已被移动）。
    }
  }
}
