import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/custom_sticker_provider.dart';
import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import '../services/webdav_service.dart';
import '../widgets/lock_gate.dart';

/// WebDAV 自动备份设置（REQ-15）:配置服务器、定期单向备份与恢复。
/// 打包格式复用 REQ-03 的备份 zip;双向同步与冲突合并另行立项。
class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _url = TextEditingController(text: settings.webdavUrl);
    _username = TextEditingController(text: settings.webdavUsername);
    _password = TextEditingController(text: settings.webdavPassword);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveConfig() async {
    await _run(() async {
      await context.read<SettingsProvider>().setWebdavConfig(
        url: _url.text,
        username: _username.text,
        password: _password.text,
      );
      _toast('WebDAV 配置已保存');
    });
  }

  Future<void> _testConnection() async {
    await _run(() async {
      final client = WebDavClient(
        baseUrl: _url.text,
        username: _username.text,
        password: _password.text,
      );
      await client.testConnection();
      _toast('连接成功,服务器可用 ✅');
    });
  }

  Future<Uint8List> _buildZip() async {
    final journal = context.read<JournalProvider>();
    final templates = context.read<TemplateProvider>();
    final stickers = context.read<CustomStickerProvider>();
    return BackupService.instance.buildZip(
      entries: journal.entries,
      templates: templates.templates,
      customStickers: stickers.stickers,
      stickerBytes: await stickers.exportBytes(),
      stickerPacks: stickers.packs,
    );
  }

  Future<void> _backupNow() async {
    // 备份含全部手账与图片,应用锁开启时先验证（REQ-08.5 联动）。
    final verified = await verifyAppLock(context, reason: '上传备份前需验证身份');
    if (!verified || !mounted) return;
    await _run(() async {
      final settings = context.read<SettingsProvider>();
      final name = await WebDavBackupRunner().backupNow(
        settings: settings,
        buildZip: _buildZip,
      );
      _toast('已备份到 WebDAV:$name');
    });
  }

  Future<void> _restoreLatest() async {
    final verified = await verifyAppLock(context, reason: '从 WebDAV 恢复前需验证身份');
    if (!verified || !mounted) return;

    await _run(() async {
      final settings = context.read<SettingsProvider>();
      final client = WebDavClient.fromSettings(settings);
      final files = await client.listBackups();
      if (files.isEmpty) {
        _toast('WebDAV 上还没有备份');
        return;
      }
      final bytes = await client.download(files.first);
      final data = BackupService.instance.parseBackup(bytes);

      if (!mounted) return;
      final mode = await _pickImportMode(data);
      if (mode == null || !mounted) return;

      final journal = context.read<JournalProvider>();
      final templates = context.read<TemplateProvider>();
      final stickers = context.read<CustomStickerProvider>();
      final overwrite = mode == 'overwrite';
      final changed = await journal.importBackup(data, overwrite: overwrite);
      // 模板画布里的照片按附件文件名重映射到落地后的新路径（FIX-01.3）。
      await templates.importTemplates(
        data.templates,
        overwrite: overwrite,
        attachments: data.attachments,
      );
      final stickerCount = await _restoreStickers(
        stickers,
        data,
        overwrite: overwrite,
      );
      if (!mounted) return;
      // 跳过的素材如实附在末尾（NFR-06 尺寸闸拦下的那些）。
      final skippedNote = stickerCount.skipped > 0
          ? '；${stickerCount.skipped} 张素材尺寸超限或无法识别,已跳过'
          : '';
      _toast(
        overwrite
            ? '已覆盖导入 ${data.entries.length} 篇手账、'
                  '${data.templates.length} 个模板、'
                  '${stickerCount.saved} 张自定义贴纸$skippedNote'
            : '合并导入完成,更新 $changed 篇手账,'
                  '另含 ${data.templates.length} 个模板、'
                  '${stickerCount.saved} 张自定义贴纸$skippedNote',
      );
    });
  }

  /// 恢复备份内的自定义图片贴纸（REQ-20.6）,返回落地张数与跳过张数。
  /// 覆盖模式先清空既有素材,与手账、模板的覆盖语义保持一致。
  /// 素材包记录先行重建（v7）,贴纸的 packId 才有落位；
  /// 合并模式下同 id 的包保留本机版本。
  Future<({int saved, int skipped})> _restoreStickers(
    CustomStickerProvider stickers,
    BackupData data, {
    required bool overwrite,
  }) async {
    if (overwrite) await stickers.clearAll();
    await stickers.ensurePacksExist(data.stickerPacks);
    var count = 0;
    var skipped = 0;
    for (final sticker in data.customStickers) {
      final bytes = data.stickerBytes[sticker.fileName];
      if (bytes == null) {
        skipped++;
        continue;
      }
      final saved = await stickers.importFromBytes(
        bytes,
        name: sticker.name,
        category: sticker.category,
        ext: sticker.ext,
        packId: sticker.packId,
      );
      if (saved != null) {
        count++;
      } else {
        skipped++;
      }
    }
    return (saved: count, skipped: skipped);
  }

  Future<String?> _pickImportMode(BackupData data) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从 WebDAV 恢复'),
        content: Text(
          '最新备份包含 ${data.entries.length} 篇手账、'
          '${data.templates.length} 个模板、'
          '${data.customStickers.length} 张自定义贴纸。\n\n'
          '· 合并：按条目去重,保留较新的版本\n'
          '· 覆盖：清空现有全部数据后导入',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'merge'),
            child: const Text('合并'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 自动备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '定期把全部手账与图片单向备份到你的 WebDAV 网盘'
            '（如坚果云）,内容与本地导出的备份 zip 完全一致。',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel('服务器配置'),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dav.jianguoyun.com/dav/',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: '账号',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '应用密码 / 密码',
              helperText: '凭据仅保存在本机,不会上传到任何第三方',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveConfig,
                  icon: const Icon(Icons.save_outlined, size: 19),
                  label: const Text('保存配置'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _testConnection,
                  icon: const Icon(Icons.wifi_tethering, size: 19),
                  label: const Text('测试连接'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _sectionLabel('自动备份'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '启动时定期自动备份',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.webdavConfigured
                  ? '打开应用时若距上次备份超过所选间隔,将自动上传'
                  : '请先保存服务器配置',
              style: const TextStyle(fontSize: 12.5),
            ),
            value: settings.webdavEnabled,
            onChanged: settings.webdavConfigured && !_busy
                ? (v) => settings.setWebdavEnabled(v)
                : null,
          ),
          if (settings.webdavEnabled) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final days in SettingsProvider.webdavIntervalChoices)
                  ChoiceChip(
                    label: Text(switch (days) {
                      1 => '每天',
                      3 => '每 3 天',
                      _ => '每周',
                    }),
                    selected: settings.webdavIntervalDays == days,
                    onSelected: settings.webdavIntervalDays == days || _busy
                        ? null
                        : (_) => settings.setWebdavIntervalDays(days),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          _statusTile(settings, scheme),
          const SizedBox(height: 26),
          _sectionLabel('手动操作'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || !settings.webdavConfigured
                      ? null
                      : _backupNow,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 19),
                  label: const Text('立即备份'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !settings.webdavConfigured
                      ? null
                      : _restoreLatest,
                  icon: const Icon(Icons.cloud_download_outlined, size: 19),
                  label: const Text('恢复最新备份'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '服务器端最多保留最近 ${WebDavClient.keepCount} 份备份,更早的会在备份成功后自动清理。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _statusTile(SettingsProvider settings, ColorScheme scheme) {
    final last = settings.webdavLastBackupAt;
    final error = settings.webdavLastError;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.isEmpty
            ? scheme.surfaceContainerHigh
            : scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            error.isEmpty
                ? Icons.schedule_rounded
                : Icons.error_outline_rounded,
            size: 20,
            color: error.isEmpty ? scheme.onSurfaceVariant : scheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error.isNotEmpty
                  ? '上次自动备份失败:$error'
                  : last == null
                  ? '还没有备份过'
                  : '上次备份:${_formatTime(last)}',
              style: TextStyle(
                fontSize: 13,
                color: error.isEmpty ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Widget _sectionLabel(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 18,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
