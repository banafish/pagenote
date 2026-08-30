/// 花样字体注册表（调研一阶段落地后扩容）：开源可商用中文字体。
///
/// - 霞鹜文楷 Lite — SIL OFL 1.1,https://github.com/lxgw/LxgwWenKai-Lite
/// - 马善政（毛笔楷书）— SIL OFL 1.1,Google Fonts
/// - 站酷快乐体 — SIL OFL 1.1,Google Fonts
/// - 站酷小薇 — SIL OFL 1.1,Google Fonts
/// - 站酷庆科黄油体 — SIL OFL 1.1,Google Fonts
/// - 龙藏体 — SIL OFL 1.1,Google Fonts
/// - 志莽行书 — SIL OFL 1.1,Google Fonts
/// - 柳建毛草 — SIL OFL 1.1,Google Fonts
/// - 得意黑 Smiley Sans — SIL OFL 1.1,https://github.com/atelier-anchor/smiley-sans
/// - 朱雀仿宋 Zhuque Fangsong — SIL OFL 1.1,https://github.com/TrionesType/zhuque
/// 许可证原文见 fonts/ 目录。
///
/// 注意（素材与模板管理需求 NFR-08）：family 一经发布不得重命名或删除，
/// 只能新增——历史模板与已分发分享包按 family 引用字体。
///
/// 本文件不得引入 Flutter 依赖：tool/strip_web_font_manifest.dart 会在
/// web 构建后处理时按本表过滤 FontManifest.json。
class AppFont {
  const AppFont(this.family, this.name, this.asset);

  /// Flutter fontFamily;空串表示应用默认字体。
  final String family;

  /// 展示名。
  final String name;

  /// 字体文件路径（与 pubspec fonts 资产一致）；默认字体为空串。
  final String asset;
}

const List<AppFont> appFonts = [
  AppFont('', '默认', ''),
  AppFont('LXGW WenKai', '霞鹜文楷', 'fonts/LXGWWenKaiLite-Regular.ttf'),
  AppFont('Ma Shan Zheng', '马善政楷', 'fonts/MaShanZheng-Regular.ttf'),
  AppFont('ZCOOL KuaiLe', '快乐体', 'fonts/ZCOOLKuaiLe-Regular.ttf'),
  AppFont('ZCOOL XiaoWei', '站酷小薇', 'fonts/ZCOOLXiaoWei-Regular.ttf'),
  AppFont(
    'ZCOOL QingKe HuangYou',
    '庆科黄油体',
    'fonts/ZCOOLQingKeHuangYou-Regular.ttf',
  ),
  AppFont('Long Cang', '龙藏体', 'fonts/LongCang-Regular.ttf'),
  AppFont('Zhi Mang Xing', '志莽行书', 'fonts/ZhiMangXing-Regular.ttf'),
  AppFont('Liu Jian Mao Cao', '柳建毛草', 'fonts/LiuJianMaoCao-Regular.ttf'),
  AppFont('Smiley Sans', '得意黑', 'fonts/SmileySans-Oblique.ttf'),
  AppFont('Zhuque Fangsong', '朱雀仿宋', 'fonts/ZhuqueFangsong-Regular.ttf'),
];

/// 字体数据版本：重新子集化或更换远端字体内容时 +1，旧缓存文件名随之
/// 失配、触发重新下载（见 AppFontLoader 的缓存键）。
const int fontPackVersion = 1;

/// Android release 包内置的字体资产；其余花样字体在打包期由
/// android/app/build.gradle.kts 从合并资产中剔除，首次使用时经
/// AppFontLoader 从本地缓存或远端补齐。与 gradle 侧 bundledFontFiles
/// 保持一致，test/font_packaging_test.dart 校验。
const bundledFontAssets = {'fonts/LXGWWenKaiLite-Regular.ttf'};

/// web 落地页专用霞鹜文楷子集（tool/make_landing_font_subset.py 生成并
/// 入库）：落地页文案固定，只含其出现的字符约 236KB；完整字库仍随包部署，
/// 编辑器内由 AppFontLoader 首次使用时经 rootBundle 补注册。构建期由
/// tool/strip_web_font_manifest.dart 换入 FontManifest。
const landingSubsetFontAsset = 'fonts/LXGWWenKaiLite-LandingSubset.ttf';

/// web 端随 FontManifest 急加载的字体：web 引擎初始化会等 FontManifest 里
/// 全部字体下载完才出首帧，只保留落地页首帧要用的霞鹜文楷。构建期
/// （tool/strip_web_font_manifest.dart）会把该族换指落地页专用子集
/// [landingSubsetFontAsset]，其余字体在构建期从 FontManifest 剥离，运行时
/// 由 AppFontLoader 首次使用时经 rootBundle 注册完整字库。原生端 Windows
/// 与 Android debug 全量随包静态注册；Android release 仅内置
/// [bundledFontAssets]，其余同样由 AppFontLoader 首次使用时补齐。
const webEagerFontFamilies = {'LXGW WenKai'};

AppFont? fontByFamily(String family) => family.isEmpty
    ? null
    : appFonts.where((f) => f.family == family).firstOrNull;

/// 字体缺失或未知 family 时回退到系统字体族的兜底列表。
const canvasFontFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans SC',
  'sans-serif',
];
