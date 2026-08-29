/// web 构建后处理：从 build/web/assets/FontManifest.json 剥离非急加载花样字体。
///
/// web 引擎初始化会等 FontManifest.json 里全部字体下载完才出首帧，因此
/// 构建期只保留 webEagerFontFamilies（落地页与内置模板首帧要用的三款），
/// 其余字体文件仍留在 assets/fonts/ 下，运行时由 AppFontLoader
/// （lib/services/font_loader_service.dart）首次使用时经 rootBundle +
/// FontLoader 按需注册。与 lib/models/app_fonts.dart 共用注册表。
///
/// 用法：flutter build web 之后执行 `dart run tool/strip_web_font_manifest.dart`。
/// 失败时以非零码退出——宁可回退到全量急加载，也不静默产生错误清单。
library;

// 命令行构建后处理脚本，stdout 摘要供 CI 日志查看。
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:pagenote/models/app_fonts.dart';

void main() {
  const path = 'build/web/assets/FontManifest.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('未找到 $path，请先执行 flutter build web');
    exitCode = 1;
    return;
  }

  final lazyFamilies = appFonts
      .map((f) => f.family)
      .where(
        (family) => family.isNotEmpty && !webEagerFontFamilies.contains(family),
      )
      .toSet();

  final manifest = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final kept = manifest
      .where((entry) => !lazyFamilies.contains(entry['family'] as String?))
      .toList();

  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(kept));
  print(
    'FontManifest：剥离 ${manifest.length - kept.length} 款按需字体，'
    '保留 ${kept.length} 项急加载字体。',
  );
}
