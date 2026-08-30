// 字体打包一致性与按需加载行为测试。
//
// Android release 只内置 bundledFontAssets，其余字体经 AppFontLoader 在
// 运行时补齐；内置清单分处 pubspec（字体声明）、android/app/build.gradle.kts
// （打包剔除）与 lib/models/app_fonts.dart（Dart 注册表）三处，靠本文件兜住漂移。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pagenote/models/app_fonts.dart';
import 'package:pagenote/services/font_cache.dart';
import 'package:pagenote/services/font_loader_service.dart';

/// 内存版缓存，同时记录写入以供断言。
class _MemoryFontCache implements FontCache {
  final store = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => store[key];

  @override
  Future<void> write(String key, List<int> bytes) async =>
      store[key] = Uint8List.fromList(bytes);
}

AppFont _fontOf(String family) =>
    appFonts.firstWhere((f) => f.family == family);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('打包一致性', () {
    test('bundledFontAssets 必须是注册表里真实声明的字体资产', () {
      final declared = appFonts
          .map((f) => f.asset)
          .where((a) => a.isNotEmpty)
          .toSet();
      expect(
        declared.containsAll(bundledFontAssets),
        isTrue,
        reason: 'bundledFontAssets 出现了注册表之外的字体：$bundledFontAssets',
      );
    });

    test('gradle 内置字体列表与 Dart bundledFontAssets 一致', () {
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      final match = RegExp(r'val bundledFontFiles = setOf\(([^)]*)\)')
          .firstMatch(gradle);
      expect(match, isNotNull, reason: 'gradle 侧缺少 bundledFontFiles 定义');
      final gradleSet = RegExp('"([^"]+)"')
          .allMatches(match!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        gradleSet,
        bundledFontAssets.map((a) => a.split('/').last).toSet(),
      );
    });

    test('全部花样字体文件（含按需下载源）存在于 fonts/ 目录', () {
      for (final font in appFonts) {
        if (font.asset.isEmpty) continue;
        expect(
          File(font.asset).existsSync(),
          isTrue,
          reason: '${font.asset} 缺失（按需下载源与内置字体都要求其入库）',
        );
      }
    });

    test('内置字体属于急加载字体族（模板与首帧体验）', () {
      for (final font in appFonts) {
        if (bundledFontAssets.contains(font.asset)) {
          expect(
            webEagerFontFamilies.contains(font.family),
            isTrue,
            reason: '内置字体 ${font.family} 不在 webEagerFontFamilies 中',
          );
        }
      }
    });
  });

  group('FontFetcher', () {
    test('rootBundle 命中时不走缓存与网络', () async {
      final cache = _MemoryFontCache();
      var downloads = 0;
      final fetcher = FontFetcher(
        cache: cache,
        loadAsset: (_) async => ByteData(1),
        clientFactory: () => MockClient((request) async {
          downloads++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      await fetcher.fetch(_fontOf('Ma Shan Zheng'));
      expect(downloads, 0);
      expect(cache.store, isEmpty);
    });

    test('包内缺失时命中本地缓存，不发起下载', () async {
      final cache = _MemoryFontCache();
      cache.store['v$fontPackVersion/MaShanZheng-Regular.ttf'] =
          Uint8List.fromList([9, 9, 9]);
      var downloads = 0;
      final fetcher = FontFetcher(
        cache: cache,
        loadAsset: (_) => throw StateError('不在包内'),
        clientFactory: () => MockClient((request) async {
          downloads++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final bytes = await fetcher.fetch(_fontOf('Ma Shan Zheng'));
      expect(bytes.lengthInBytes, 3);
      expect(downloads, 0);
    });

    test('缓存未命中时从远端下载并落缓存', () async {
      final cache = _MemoryFontCache();
      final fetcher = FontFetcher(
        baseUrl: 'http://localhost:1234',
        cache: cache,
        loadAsset: (_) => throw StateError('不在包内'),
        clientFactory: () => MockClient((request) async {
          expect(request.url.toString(),
              'http://localhost:1234/assets/fonts/MaShanZheng-Regular.ttf');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final bytes = await fetcher.fetch(_fontOf('Ma Shan Zheng'));
      expect(bytes.lengthInBytes, 3);
      expect(
        cache.store['v$fontPackVersion/MaShanZheng-Regular.ttf'],
        isNotNull,
      );
    });

    test('未配置下载源或下载失败时抛错', () async {
      final fetcher = FontFetcher(
        cache: _MemoryFontCache(),
        loadAsset: (_) => throw StateError('不在包内'),
      );
      expect(
        fetcher.fetch(_fontOf('Ma Shan Zheng')),
        throwsA(isA<StateError>()),
      );

      final failing = FontFetcher(
        baseUrl: 'http://localhost:1234',
        cache: _MemoryFontCache(),
        loadAsset: (_) => throw StateError('不在包内'),
        clientFactory: () => MockClient((request) async =>
            http.Response('not found', 404)),
      );
      expect(
        failing.fetch(_fontOf('Ma Shan Zheng')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AppFontLoader', () {
    setUp(() {
      AppFontLoader.instance.debugReset();
      AppFontLoader.instance.manifestFamiliesOverride = const {};
    });
    tearDown(() {
      AppFontLoader.instance.debugReset();
      AppFontLoader.instance.manifestFamiliesOverride = null;
      AppFontLoader.instance.fetcherOverride = null;
    });

    test('下载成功后注册并通知监听者', () async {
      var downloads = 0;
      var notified = 0;
      AppFontLoader.instance.addListener(() => notified++);
      AppFontLoader.instance.fetcherOverride = FontFetcher(
        baseUrl: 'http://localhost:1234',
        cache: _MemoryFontCache(),
        loadAsset: (_) => throw StateError('不在包内'),
        clientFactory: () => MockClient((request) async {
          downloads++;
          return http.Response.bytes(Uint8List(16), 200);
        }),
      );
      await AppFontLoader.instance.ensure('Ma Shan Zheng');
      expect(downloads, 1);
      expect(notified, 1);
      // 成功后重复 ensure 不再下载。
      await AppFontLoader.instance.ensure('Ma Shan Zheng');
      expect(downloads, 1);
    });

    test('失败后进入冷却期，画布逐帧重试不会放大成网络风暴', () async {
      var downloads = 0;
      AppFontLoader.instance.fetcherOverride = FontFetcher(
        baseUrl: 'http://localhost:1234',
        cache: _MemoryFontCache(),
        loadAsset: (_) => throw StateError('不在包内'),
        clientFactory: () => MockClient((request) async {
          downloads++;
          return http.Response('server error', 500);
        }),
      );
      await AppFontLoader.instance.ensure('Ma Shan Zheng');
      expect(downloads, 1);
      // 冷却期内重试直接短路。
      await AppFontLoader.instance.ensure('Ma Shan Zheng');
      expect(downloads, 1);
    });

    test('FontManifest 已声明的字体视为已注册，不做任何加载', () async {
      AppFontLoader.instance.manifestFamiliesOverride = null;
      var downloads = 0;
      AppFontLoader.instance.fetcherOverride = FontFetcher(
        cache: _MemoryFontCache(),
        loadAsset: (_) => throw StateError('不应被调用'),
        clientFactory: () => MockClient((request) async {
          downloads++;
          return http.Response.bytes([1], 200);
        }),
      );
      // 测试环境 rootBundle 的 FontManifest 声明了全部注册表字体。
      await AppFontLoader.instance.ensure('Smiley Sans');
      expect(downloads, 0);
    });
  });
}
