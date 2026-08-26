import 'package:web/web.dart' as web;

/// 新开标签页打开外链；下载直链同样交给浏览器接管。
/// 必须在用户手势（按钮点击）中调用，否则会被弹窗拦截。
void openExternalUrl(String url) => web.window.open(url, '_blank');
