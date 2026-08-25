/// 把字节写到用户通过系统对话框选定的绝对路径。
///
/// Web 端没有可写的文件系统，「用户选定的绝对路径」这一概念不存在；
/// Web 的导出走浏览器下载（见各导出流程的 kIsWeb 分支），不会调用到这里。
Future<void> writeToUserPath(String path, List<int> bytes) =>
    throw UnsupportedError('Web 端不支持按绝对路径写文件:$path');
