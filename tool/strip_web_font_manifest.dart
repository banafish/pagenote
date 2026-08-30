/// web 构建后处理：瘦身 build/web/assets/FontManifest.json。
///
/// web 引擎初始化会等 FontManifest.json 里全部字体下载完才出首帧，因此
/// 构建期做两件事：
/// 1. 剥离 webEagerFontFamilies 之外的花样字体族——字体文件仍留在
///    assets/fonts/ 下，运行时由 AppFontLoader（lib/services/
///    font_loader_service.dart）首次使用时经 rootBundle + FontLoader
///    按需注册；
/// 2. 把霞鹜文楷条目换指落地页专用子集（landingSubsetFontAsset，由
///    tool/make_landing_font_subset.py 生成并入库），并把子集文件复制进
///    构建产物——落地页首帧只需其固定文案字符，完整字库（传输约 2.2MB）
///    留给编辑器按需注册。
///
/// 与 lib/models/app_fonts.dart 共用注册表。
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

  final subsetFile = File(
    'fonts/${landingSubsetFontAsset.split('/').last}',
  );
  if (!subsetFile.existsSync()) {
    stderr.writeln(
      '未找到字体子集 ${subsetFile.path}，请先执行 '
      '`python tool/make_landing_font_subset.py` 生成并入库',
    );
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
  final kept = <Map<String, dynamic>>[];
  var swapped = false;
  for (final entry in manifest) {
    final family = entry['family'] as String?;
    if (family != null && lazyFamilies.contains(family)) continue;
    if (family == 'LXGW WenKai') {
      entry['fonts'] = [
        {'asset': landingSubsetFontAsset},
      ];
      swapped = true;
    }
    kept.add(entry);
  }
  if (!swapped) {
    stderr.writeln('FontManifest 里没有 LXGW WenKai 条目，落地页将回退系统字体');
  }

  final target = File('build/web/assets/$landingSubsetFontAsset');
  target.parent.createSync(recursive: true);
  subsetFile.copySync(target.path);

  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(kept));
  print(
    'FontManifest：剥离 ${manifest.length - kept.length} 款按需字体，'
    '保留 ${kept.length} 项急加载字体'
    '${swapped ? '，霞鹜文楷已换指落地页子集（${subsetFile.lengthSync()} 字节）' : ''}。',
  );
}
