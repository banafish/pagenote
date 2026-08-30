import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader, rootBundle;
import 'package:http/http.dart' as http;

import '../models/app_fonts.dart';
import 'font_cache.dart';

/// 花样字体远端下载源（逗号分隔多个，按序回退）：每项直接指向字体所在
/// 目录，如 Pages 部署的 `https://…/assets/fonts` 与 jsDelivr 仓库源的
/// `https://cdn.jsdelivr.net/gh/<owner>/<repo>@<tag>/fonts`——两者服务
/// 同一份入库字体，后者由公共 CDN 长期托管，单一部署下线不影响取字。
/// 构建期经 --dart-define 注入；未注入时 Android release 的非内置字体
/// 无法下载，按兜底字体渲染。
const fontBaseUrl = String.fromEnvironment('PAGENOTE_FONT_BASE_URL');

/// 花样字体按需加载器。
///
/// 各构建形态下的字体可用性：
/// - Windows / Android debug / web 急加载三款：随包或 FontManifest 静态
///   注册，直接可用；
/// - web 非急加载：字体文件与部署同源，经 rootBundle 取回后注册；
/// - Android release：除 bundledFontAssets 外的字体已在打包期剔除
///   （android/app/build.gradle.kts），首次使用时从远端下载、写入本地缓存
///   并经 FontLoader 注册（动态注册不跨进程持久，之后每次启动从缓存补注册）。
///
/// 统一入口 [ensure]：先查 FontManifest 判定是否已静态注册，再交由
/// [FontFetcher] 取字节；失败进入冷却期——画布逐帧重绘不能放大成网络
/// 风暴。成功后 [notifyListeners] 触发画布重绘。
class AppFontLoader extends ChangeNotifier {
  AppFontLoader._();

  static final AppFontLoader instance = AppFontLoader._();

  final _pending = <String, Future<void>>{};
  final _loaded = <String>{};
  final _failedAt = <String, DateTime>{};
  Set<String>? _manifestFamilies;

  FontFetcher get _fetcher => fetcherOverride ?? _defaultFetcher;
  final _defaultFetcher = FontFetcher();

  /// 失败后的重试冷却期：冷却期内直接按兜底字体渲染。
  static const retryCooldown = Duration(seconds: 60);

  /// 测试注入点。
  @visibleForTesting
  FontFetcher? fetcherOverride;

  /// 测试注入点：非 null 时替代 FontManifest 判定。
  @visibleForTesting
  Set<String>? manifestFamiliesOverride;

  /// 测试注入点：清空运行状态。
  @visibleForTesting
  void debugReset() {
    _pending.clear();
    _loaded.clear();
    _failedAt.clear();
    _manifestFamilies = null;
  }

  /// 确保 [family] 可用：缺失时按需下载/注册，失败按兜底字体渲染，
  /// 成功后重复调用为空操作。
  Future<void> ensure(String family) {
    if (family.isEmpty || _loaded.contains(family)) return Future.value();
    return _pending.putIfAbsent(family, () => _load(family));
  }

  Future<void> _load(String family) async {
    try {
      final font = fontByFamily(family);
      if (font == null || font.asset.isEmpty) return;
      if (await _staticallyRegistered(family)) {
        _loaded.add(family);
        return;
      }
      final failedAt = _failedAt[family];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < retryCooldown) {
        return;
      }
      final bytes = await _fetcher.fetch(font);
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
      _loaded.add(family);
      _failedAt.remove(family);
      notifyListeners();
    } catch (error) {
      _failedAt[family] = DateTime.now();
      debugPrint('按需加载字体 $family 失败：$error');
    } finally {
      _pending.remove(family);
    }
  }

  /// family 是否已随包静态注册（FontManifest 里声明即注册）：
  /// Windows / Android debug 全量，Android release 仅内置字体，web 急加载。
  Future<bool> _staticallyRegistered(String family) async {
    final override = manifestFamiliesOverride;
    if (override != null) return override.contains(family);
    try {
      _manifestFamilies ??= await _readManifestFamilies();
    } catch (_) {
      // 清单读不到时宁可重新注册一次（重复注册仅告警，不致命）。
      return false;
    }
    return _manifestFamilies!.contains(family);
  }

  Future<Set<String>> _readManifestFamilies() async {
    final raw = await rootBundle.loadString('FontManifest.json');
    final entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return {
      for (final entry in entries)
        if (entry['family'] is String) entry['family'] as String,
    };
  }
}

/// 字体字节获取策略：rootBundle → 本地缓存 → 远端下载（多源按序回退）。
/// 依赖全部可注入，单元测试可离线覆盖各条路径。
class FontFetcher {
  FontFetcher({
    String? baseUrl,
    FontCache? cache,
    Future<ByteData> Function(String asset)? loadAsset,
    http.Client Function()? clientFactory,
  }) : _baseUrl = baseUrl ?? fontBaseUrl,
       _cache = cache ?? fontCache,
       _loadAsset = loadAsset ?? rootBundle.load,
       _clientFactory = clientFactory ?? http.Client.new;

  static const _downloadTimeout = Duration(seconds: 20);

  final String _baseUrl;
  final FontCache _cache;
  final Future<ByteData> Function(String) _loadAsset;
  final http.Client Function() _clientFactory;

  Future<ByteData> fetch(AppFont font) async {
    // 随包资产：web 按需字体与 Windows / Android debug 全量构建都在包内。
    try {
      return await _loadAsset(font.asset);
    } catch (_) {
      // Android release 已剔除该字体，继续走缓存/下载。
    }

    final name = font.asset.split('/').last;
    final key = 'v$fontPackVersion/$name';
    final cached = await _cache.read(key);
    if (cached != null) return ByteData.sublistView(cached);

    final sources = _baseUrl
        .split(',')
        .map((source) => source.trim().replaceAll(RegExp(r'/+$'), ''))
        .where((source) => source.isNotEmpty)
        .toList();
    if (sources.isEmpty) {
      throw StateError('未配置字体下载源（--dart-define=PAGENOTE_FONT_BASE_URL）');
    }

    final client = _clientFactory();
    final failures = <String>[];
    try {
      for (final source in sources) {
        try {
          final response = await client
              .get(Uri.parse('$source/$name'))
              .timeout(_downloadTimeout);
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            // 先落缓存再返回：注册失败重试时不再重复下载。
            await _cache.write(key, response.bodyBytes);
            return ByteData.sublistView(response.bodyBytes);
          }
          failures.add('$source：HTTP ${response.statusCode}');
        } catch (error) {
          failures.add('$source：$error');
        }
      }
      throw StateError(
        '下载 $name 失败，${sources.length} 个源均不可用：${failures.join('；')}',
      );
    } finally {
      client.close();
    }
  }
}
