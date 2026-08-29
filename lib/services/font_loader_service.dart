import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;

import '../models/app_fonts.dart';

/// web 端花样字体按需加载器。
///
/// web 引擎初始化会等 FontManifest.json 里全部字体下载完才出首帧
/// （engine/initialization.dart 的 `_downloadAssetFonts`），构建期已把
/// 非急加载字体从 FontManifest 剥离（见 tool/strip_web_font_manifest.dart），
/// 因此首次使用时在此经 rootBundle + FontLoader 注册，完成后
/// [notifyListeners] 触发画布重绘。原生平台字体已随包静态注册，
/// [ensure] 直接返回。
class AppFontLoader extends ChangeNotifier {
  AppFontLoader._();

  static final AppFontLoader instance = AppFontLoader._();

  final _pending = <String, Future<void>>{};

  /// 确保 [family] 可用（web 端按需下载并注册，其余平台为空操作）。
  /// 失败时按兜底字体渲染，可再次调用重试。
  Future<void> ensure(String family) {
    if (!kIsWeb ||
        family.isEmpty ||
        webEagerFontFamilies.contains(family) ||
        _pending.containsKey(family)) {
      return Future.value();
    }
    final future = _load(family);
    _pending[family] = future;
    return future;
  }

  Future<void> _load(String family) async {
    final font = fontByFamily(family);
    if (font == null || font.asset.isEmpty) return;
    try {
      final bytes = await rootBundle.load(font.asset);
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
      notifyListeners();
    } catch (error) {
      debugPrint('按需加载字体 $family 失败：$error');
      _pending.remove(family);
    }
  }
}
