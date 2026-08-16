/// 花样字体注册表（调研一阶段）：开源可商用中文字体。
///
/// - 霞鹜文楷 Lite — SIL OFL 1.1,https://github.com/lxgw/LxgwWenKai-Lite
/// - 马善政（毛笔楷书）— SIL OFL 1.1,Google Fonts
/// - 站酷快乐体 — SIL OFL 1.1,Google Fonts
/// 许可证原文见 fonts/ 目录。
class AppFont {
  const AppFont(this.family, this.name);

  /// Flutter fontFamily;空串表示应用默认字体。
  final String family;

  /// 展示名。
  final String name;
}

const List<AppFont> appFonts = [
  AppFont('', '默认'),
  AppFont('LXGW WenKai', '霞鹜文楷'),
  AppFont('Ma Shan Zheng', '马善政楷'),
  AppFont('ZCOOL KuaiLe', '快乐体'),
];

AppFont? fontByFamily(String family) =>
    family.isEmpty ? null : appFonts.where((f) => f.family == family).firstOrNull;

/// 字体缺失或未知 family 时回退到系统字体族的兜底列表。
const canvasFontFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans SC',
  'sans-serif',
];
