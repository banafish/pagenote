import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../storage/stored_files.dart';
import 'journal_id.dart';

/// 图片附件：选择图片并存入应用存储层，保证长期可访问。
/// 原生端落在文档目录的真实文件，Web 端存 IndexedDB，
/// 两侧对上层都只是「可长期复用的路径字符串」。
class Attachments {
  Attachments._();

  /// 附件在存储层下的逻辑目录名。
  static const _dir = 'attachments';

  static const maxImages = 9;

  /// 分隔符无关的文件名提取。备份包里的画布路径可能来自其他平台
  /// （如 Windows 导出的 `C:\a\b.jpg`），package:path 的 basename
  /// 在 POSIX 平台不认反斜杠，会整串返回导致重映射失配，
  /// 因此这里同时按 `\` 和 `/` 截取。
  static String baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  static const _imageGroup = XTypeGroup(
    label: '图片',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
  );

  /// 打开系统图片选择器，返回存储后的附件路径列表；用户取消返回空。
  /// [remaining] 为还能添加的图片数量，超出部分会被截断。
  static Future<List<String>> pickImages({int remaining = maxImages}) async {
    if (remaining <= 0) return [];
    final files = await openFiles(acceptedTypeGroups: [_imageGroup]);
    if (files.isEmpty) return [];
    final picked = files.take(remaining).toList();
    return Future.wait(picked.map(persist));
  }

  /// 将文件内容存入附件目录，返回新路径。
  static Future<String> persist(XFile file) async =>
      persistBytes(await file.readAsBytes(), p.extension(file.name));

  /// 将字节内容写入附件目录（备份导入用），返回新路径。
  static Future<String> persistBytes(List<int> bytes, String ext) async {
    final name = '${makeId()}${ext.isEmpty ? '.img' : ext}';
    return storedFiles.write('$_dir/$name', bytes);
  }

  /// 清空附件目录中的全部文件（覆盖导入前调用）。
  static Future<void> clearAll() => storedFiles.clearDir(_dir);

  /// 删除附件文件；测试可替换该钩子以拦截删除操作。
  static Future<void> Function(String path) delete = deleteFile;

  static Future<void> deleteFile(String path) => storedFiles.delete(path);
}
