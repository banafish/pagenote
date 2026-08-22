import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/services/webdav_service.dart';

void main() {
  // 内存版 WebDAV 服务器:完整模拟 MKCOL/PUT/PROPFIND/GET/DELETE 与 Basic 认证。
  late HttpServer server;
  final files = <String, List<int>>{};
  final dirs = <String>{};
  String lastAuthHeader = '';

  const user = 'pagenote-user';
  const password = 'app-password';

  bool authorized(HttpRequest req) {
    final expected = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    return req.headers.value(HttpHeaders.authorizationHeader) == expected;
  }

  setUp(() async {
    files.clear();
    dirs.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      lastAuthHeader =
          request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final path = request.uri.path;
      if (!authorized(request)) {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      switch (request.method) {
        case 'MKCOL':
          final existed = dirs.contains(path);
          dirs.add(path);
          request.response.statusCode = existed ? 405 : 201;
          await request.response.close();
        case 'PUT':
          final body = <int>[];
          await for (final chunk in request) {
            body.addAll(chunk);
          }
          files[path] = body;
          request.response.statusCode = 201;
          await request.response.close();
        case 'PROPFIND':
          // 根路径视为始终存在;子目录未创建时返回 404。
          if (path != '/dav/' && !dirs.contains(path)) {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }
          final sb = StringBuffer(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
          );
          sb.write('<d:response><d:href>$path</d:href></d:response>');
          for (final name in files.keys) {
            if (name.startsWith(path)) {
              final file = name.substring(path.length);
              if (file.isNotEmpty && !file.contains('/')) {
                sb.write(
                  '<d:response><d:href>$path$file</d:href></d:response>',
                );
              }
            }
          }
          sb.write('</d:multistatus>');
          request.response.statusCode = 207;
          request.response.write(sb.toString());
          await request.response.close();
        case 'GET':
          final body = files[path];
          if (body == null) {
            request.response.statusCode = 404;
          } else {
            request.response.add(body);
          }
          await request.response.close();
        case 'DELETE':
          final removed = files.remove(path) != null;
          request.response.statusCode = removed ? 204 : 404;
          await request.response.close();
        default:
          request.response.statusCode = 405;
          await request.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close();
  });

  WebDavClient client() => WebDavClient(
    baseUrl: 'http://127.0.0.1:${server.port}/dav',
    username: user,
    password: password,
  );

  group('纯函数', () {
    test('parseBackupHrefs：兼容命名空间前缀、过滤无关文件并按新→旧排序', () {
      const xml =
          '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">'
          '<D:response><D:href>/dav/pagenote-backup/</D:href></D:response>'
          '<D:response><D:href>/dav/pagenote-backup/pagenote-backup-2026-08-01-0900.zip</D:href></D:response>'
          '<D:response><D:href>/dav/pagenote-backup/pagenote-backup-2026-08-16-2130.zip</D:href></D:response>'
          '<D:response><D:href>/dav/pagenote-backup/notes.txt</D:href></D:response>'
          '</D:multistatus>';
      expect(parseBackupHrefs(xml), [
        'pagenote-backup-2026-08-16-2130.zip',
        'pagenote-backup-2026-08-01-0900.zip',
      ]);
    });

    test('backupFileName：固定可排序命名', () {
      expect(
        backupFileName(DateTime(2026, 8, 16, 21, 30)),
        'pagenote-backup-2026-08-16-2130.zip',
      );
      expect(
        backupFileName(DateTime(2026, 1, 2, 3, 4)),
        'pagenote-backup-2026-01-02-0304.zip',
      );
    });

    test('isBackupDue：间隔决策（REQ-15 定期备份）', () {
      final now = DateTime(2026, 8, 16, 20);
      expect(
        isBackupDue(enabled: false, last: null, intervalDays: 1, now: now),
        isFalse,
        reason: '未启用不备份',
      );
      expect(
        isBackupDue(enabled: true, last: null, intervalDays: 1, now: now),
        isTrue,
        reason: '从未备份过',
      );
      expect(
        isBackupDue(
          enabled: true,
          last: DateTime(2026, 8, 15, 9),
          intervalDays: 1,
          now: now,
        ),
        isTrue,
        reason: '已超过 1 天',
      );
      expect(
        isBackupDue(
          enabled: true,
          last: DateTime(2026, 8, 16, 9),
          intervalDays: 7,
          now: now,
        ),
        isFalse,
        reason: '7 天间隔未到',
      );
    });
  });

  group('客户端', () {
    test('测试连接：认证通过返回 true 并携带 Basic 头;错误凭据抛异常', () async {
      expect(await client().testConnection(), isTrue);
      expect(lastAuthHeader, startsWith('Basic '));

      final bad = WebDavClient(
        baseUrl: 'http://127.0.0.1:${server.port}/dav',
        username: user,
        password: 'wrong',
      );
      await expectLater(bad.testConnection(), throwsA(isA<WebDavException>()));
    });

    test('上传 → 列表 → 下载 → 清理旧备份（REQ-15 复用 zip 打包格式）', () async {
      final c = client();
      final name = await c.uploadBackup(
        Uint8List.fromList([1, 2, 3]),
        backupFileName(DateTime(2026, 8, 16, 21, 30)),
      );
      expect(name, 'pagenote-backup-2026-08-16-2130.zip');
      // MKCOL 已建目录后再上传不报错（405 已处理）。
      await c.uploadBackup(
        Uint8List.fromList([4]),
        backupFileName(DateTime(2026, 8, 15, 21, 30)),
      );

      final list = await c.listBackups();
      expect(list.first, 'pagenote-backup-2026-08-16-2130.zip');
      expect(list.length, 2);

      final bytes = await c.download(list.first);
      expect(bytes, [1, 2, 3]);

      // 只保留 1 份:更早的应被删除。
      final pruned = await c.pruneOldBackups(keep: 1);
      expect(pruned, ['pagenote-backup-2026-08-15-2130.zip']);
      expect((await c.listBackups()).length, 1);
    });

    test('目录不存在时列表返回空', () async {
      expect(await client().listBackups(), isEmpty);
    });

    test('非法地址构造时抛出明确错误', () {
      expect(
        () => WebDavClient(baseUrl: 'ftp://x', username: 'u', password: 'p'),
        throwsA(isA<WebDavException>()),
      );
      expect(
        () => WebDavClient(baseUrl: '', username: 'u', password: 'p'),
        throwsA(isA<WebDavException>()),
      );
    });
  });

  group('自动备份执行器与设置', () {
    Future<Uint8List> zip() async => Uint8List.fromList([9, 9]);

    Future<SettingsProvider> providerWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SettingsProvider(await SharedPreferences.getInstance());
    }

    test('立即备份成功并记录时间与文件名（REQ-15）', () async {
      final s = await providerWith({
        'webdav.url': 'http://127.0.0.1:${server.port}/dav',
        'webdav.username': user,
        'webdav.password': base64Encode(utf8.encode(password)),
        'webdav.enabled': true,
        'webdav.intervalDays': 1,
      });

      final name = await WebDavBackupRunner(
        now: () => DateTime(2026, 8, 16, 21, 30),
      ).backupNow(settings: s, buildZip: zip);
      expect(name, 'pagenote-backup-2026-08-16-2130.zip');
      expect(s.webdavLastBackupAt, DateTime(2026, 8, 16, 21, 30));
      expect(s.webdavLastError, isEmpty);
      expect((await client().listBackups()).single, name);
    });

    test('未到期跳过,不产生任何请求（REQ-15 定期）', () async {
      final s = await providerWith({
        'webdav.url': 'http://127.0.0.1:${server.port}/dav',
        'webdav.username': user,
        'webdav.password': base64Encode(utf8.encode(password)),
        'webdav.enabled': true,
        'webdav.intervalDays': 7,
        // 相对当前时间取 3 天前,避免固定日期随真实时间推移变成“已到期”。
        'webdav.lastBackupAt': DateTime.now()
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch,
      });
      expect(s.webdavBackupDue, isFalse);

      await WebDavBackupRunner().maybeRunAutoBackup(settings: s, buildZip: zip);
      expect(await client().listBackups(), isEmpty);
    });

    test('自动备份失败记录错误不抛出,时间不更新（REQ-15）', () async {
      final s = await providerWith({
        'webdav.url': 'http://127.0.0.1:${server.port}/dav',
        'webdav.username': user,
        'webdav.password': base64Encode(utf8.encode('bad')),
        'webdav.enabled': true,
      });
      await WebDavBackupRunner().maybeRunAutoBackup(settings: s, buildZip: zip);
      expect(s.webdavLastError, isNotEmpty);
      expect(s.webdavLastBackupAt, isNull);
    });

    test('配置存取：base64 密码与 webdavConfigured 判定', () async {
      final s = await providerWith({});
      expect(s.webdavConfigured, isFalse);
      expect(s.webdavPassword, isEmpty);

      await s.setWebdavConfig(
        url: 'https://dav.jianguoyun.com/dav',
        username: 'me',
        password: 'pw',
      );
      expect(s.webdavUrl, 'https://dav.jianguoyun.com/dav');
      expect(s.webdavUsername, 'me');
      expect(s.webdavPassword, 'pw', reason: 'base64 往返');
      expect(s.webdavConfigured, isTrue);

      await s.setWebdavEnabled(true);
      await s.setWebdavIntervalDays(3);
      expect(s.webdavEnabled, isTrue);
      expect(s.webdavIntervalDays, 3);
      expect(s.webdavBackupDue, isTrue, reason: '开启且从未备份');
    });
  });
}
