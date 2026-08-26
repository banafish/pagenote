/// 品牌页外链配置。
///
/// 全部经构建期 `--dart-define` 注入（编译进产物，无需运行时请求）：
/// Cloudflare Pages 构建时由 `tool/build_web.sh` 读取同名环境变量透传，
/// 本地未注入时为空串，品牌页会自动隐藏对应入口。
const String kLandingGithubRepoUrl =
    String.fromEnvironment('PAGENOTE_GITHUB_REPO');

/// GitHub Releases 页（查看/下载全部版本）。
const String kLandingGithubReleasesUrl =
    String.fromEnvironment('PAGENOTE_GITHUB_RELEASES');

/// 安卓客户端直链（APK）。
const String kLandingDownloadAndroidUrl =
    String.fromEnvironment('PAGENOTE_DOWNLOAD_ANDROID');

/// PC 客户端直链（Windows 安装包）。
const String kLandingDownloadPcUrl =
    String.fromEnvironment('PAGENOTE_DOWNLOAD_PC');
