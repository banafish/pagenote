import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../providers/settings_provider.dart';

/// WebDAV 操作失败（网络 / 认证 / 服务器错误）。
class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// WebDAV 客户端（REQ-15 第一阶段：定期单向备份）。
/// 基于 dart:io HttpClient 实现 Basic 认证与 MKCOL/PUT/PROPFIND/DELETE/GET,
/// 不引入额外依赖;Android 与 Windows 均可用。
class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required this.username,
    required this.password,
  }) : base = _normalizeBase(baseUrl);

  /// 服务器根地址,如 https://dav.jianguoyun.com/dav/。
  final Uri base;
  final String username;
  final String password;

  /// 备份在服务器上的目录名。
  static const remoteDir = 'pagenote-backup';

  /// 服务器端保留的最近备份份数(超出自动清理)。
  static const keepCount = 10;

  static Uri _normalizeBase(String raw) {
    var url = raw.trim();
    if (url.isEmpty) throw WebDavException('请先填写 WebDAV 服务器地址');
    if (!url.endsWith('/')) url = '$url/';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw WebDavException('服务器地址需为 http(s) 链接');
    }
    return uri;
  }

  factory WebDavClient.fromSettings(SettingsProvider settings) => WebDavClient(
    baseUrl: settings.webdavUrl,
    username: settings.webdavUsername,
    password: settings.webdavPassword,
  );

  Uri get _dirUri => base.resolve('$remoteDir/');

  Uri _fileUri(String name) => _dirUri.resolve(name);

  String get _authHeader =>
      'Basic '
      '${base64Encode(utf8.encode('$username:$password'))}';

  HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20);

  /// 执行单次请求并在结束时关闭连接;网络异常统一转 [WebDavException]。
  Future<T> _withRequest<T>(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    required Future<T> Function(HttpClientRequest) body,
  }) async {
    final client = _newClient();
    try {
      final request = await client.openUrl(method, uri)
        ..headers.set(HttpHeaders.authorizationHeader, _authHeader)
        ..headers.set(HttpHeaders.userAgentHeader, 'PageNote-Backup');
      headers.forEach(request.headers.set);
      return await body(request);
    } on WebDavException {
      rethrow;
    } on SocketException catch (e) {
      throw WebDavException('无法连接服务器:$e');
    } on HttpException catch (e) {
      throw WebDavException('网络异常:$e');
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _read(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  void _throwIfAuthFailed(int status) {
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw WebDavException('账号或密码不正确（$status）');
    }
  }

  /// 测试连接:对根地址发 PROPFIND（Depth 0）,成功返回 true。
  Future<bool> testConnection() async {
    return _withRequest(
      'PROPFIND',
      base,
      headers: {'Depth': '0'},
      body: (request) async {
        final response = await request.close();
        final ok =
            response.statusCode == 207 ||
            (response.statusCode >= 200 && response.statusCode < 300);
        if (!ok) _throwIfAuthFailed(response.statusCode);
        return ok;
      },
    );
  }

  /// 确保远端备份目录存在（已存在返回 405,视为成功）。
  Future<void> ensureDir() async {
    await _withRequest(
      'MKCOL',
      _dirUri,
      body: (request) async {
        final response = await request.close();
        await _read(response);
        final status = response.statusCode;
        if (status != 201 && status != 200 && status != 405) {
          _throwIfAuthFailed(status);
          throw WebDavException('创建备份目录失败（$status）');
        }
      },
    );
  }

  /// 上传备份文件字节,返回远端相对文件名。
  Future<String> uploadBackup(Uint8List bytes, String fileName) async {
    await ensureDir();
    return _withRequest(
      'PUT',
      _fileUri(fileName),
      headers: {HttpHeaders.contentTypeHeader: 'application/zip'},
      body: (request) async {
        request.add(bytes);
        final response = await request.close();
        await _read(response);
        final status = response.statusCode;
        if (status < 200 || status >= 300) {
          _throwIfAuthFailed(status);
          throw WebDavException('上传失败（$status）');
        }
        return fileName;
      },
    );
  }

  /// 列出远端备份文件名（按时间新→旧,固定命名格式下字典序即时间序）。
  /// 目录不存在时返回空列表。
  Future<List<String>> listBackups() async {
    return _withRequest(
      'PROPFIND',
      _dirUri,
      headers: {'Depth': '1'},
      body: (request) async {
        final response = await request.close();
        if (response.statusCode == 404) return <String>[];
        if (response.statusCode != 207 &&
            (response.statusCode < 200 || response.statusCode >= 300)) {
          _throwIfAuthFailed(response.statusCode);
          throw WebDavException('读取备份列表失败（${response.statusCode}）');
        }
        final body = utf8.decode(await _read(response));
        return parseBackupHrefs(body);
      },
    );
  }

  /// 下载指定备份文件。
  Future<Uint8List> download(String fileName) async {
    return _withRequest(
      'GET',
      _fileUri(fileName),
      body: (request) async {
        final response = await request.close();
        if (response.statusCode != 200) {
          _throwIfAuthFailed(response.statusCode);
          throw WebDavException('下载备份失败（${response.statusCode}）');
        }
        return _read(response);
      },
    );
  }

  /// 删除远端备份文件（清理旧版本）。
  Future<void> delete(String fileName) async {
    await _withRequest(
      'DELETE',
      _fileUri(fileName),
      body: (request) async {
        final response = await request.close();
        await _read(response);
      },
    );
  }

  /// 只保留最近 [keep] 份备份,返回被清理的文件名列表。
  Future<List<String>> pruneOldBackups({int keep = keepCount}) async {
    final files = await listBackups();
    final outdated = files.skip(keep).toList();
    for (final name in outdated) {
      await delete(name);
    }
    return outdated;
  }
}

/// 从 PROPFIND 响应 XML 中解析备份文件名。
/// 兼容任意命名空间前缀（D:href / d:href / href）;
/// 只保留 pagenote-backup-*.zip 形式的文件,排除目录本身,新→旧排序。
List<String> parseBackupHrefs(String xmlBody) {
  final hrefs = <String>[];
  final pattern = RegExp(r'<(?:[\w.-]+:)?href>([^<]+)</(?:[\w.-]+:)?href>');
  for (final match in pattern.allMatches(xmlBody)) {
    final href = Uri.decodeComponent(match.group(1)!);
    final name = href.split('/').last;
    if (name.startsWith('pagenote-backup-') && name.endsWith('.zip')) {
      hrefs.add(name);
    }
  }
  final unique = hrefs.toSet().toList()..sort((a, b) => b.compareTo(a));
  return unique;
}

/// 生成远端备份文件名:pagenote-backup-yyyy-MM-dd-HHmm.zip。
String backupFileName(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'pagenote-backup-${time.year}-${two(time.month)}-${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}.zip';
}

/// 判断是否到达自动备份时间（REQ-15 定期备份,纯函数便于测试）。
/// [last] 为上次成功备份时间,null 表示从未备份。
bool isBackupDue({
  required bool enabled,
  required DateTime? last,
  required int intervalDays,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (last == null) return true;
  final interval = Duration(days: intervalDays.clamp(1, 30));
  return !now.isBefore(last.add(interval));
}

/// WebDAV 备份执行器:打包复用 REQ-03 的 zip 格式,单向推送到服务器。
class WebDavBackupRunner {
  WebDavBackupRunner({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// 启动时的定期自动备份:未到期直接跳过;失败不抛出,记录到设置里。
  Future<void> maybeRunAutoBackup({
    required SettingsProvider settings,
    required Future<Uint8List> Function() buildZip,
  }) async {
    if (!settings.webdavBackupDue) return;
    try {
      await _backup(settings: settings, buildZip: buildZip);
    } on WebDavException catch (e) {
      await settings.setWebdavLastError(e.message);
    } catch (e) {
      await settings.setWebdavLastError('自动备份失败:$e');
    }
  }

  /// 手动「立即备份」:返回远端文件名,失败向调用方抛出异常。
  Future<String> backupNow({
    required SettingsProvider settings,
    required Future<Uint8List> Function() buildZip,
  }) async {
    return _backup(settings: settings, buildZip: buildZip);
  }

  Future<String> _backup({
    required SettingsProvider settings,
    required Future<Uint8List> Function() buildZip,
  }) async {
    final client = WebDavClient.fromSettings(settings);
    final name = backupFileName(_now());
    await client.uploadBackup(await buildZip(), name);
    await client.pruneOldBackups();
    final finished = _now();
    await settings.setWebdavLastBackupAt(finished);
    await settings.setWebdavLastError('');
    return name;
  }
}
