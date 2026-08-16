import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../widgets/lock_gate.dart';
import 'pin_setup_page.dart';
import 'template_manager_page.dart';
import 'trash_page.dart';

/// 设置页：外观、写作、数据、隐私与关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final journal = context.watch<JournalProvider>();
    final templates = context.watch<TemplateProvider>();
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _pageTitle(context),
        const SizedBox(height: 14),
        _sectionTitle(context, '外观'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            _SettingsLabel('主题模式'),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 19),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined, size: 19),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 19),
                  label: Text('深色'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (modes) => settings.setThemeMode(modes.first),
            ),
            const Divider(height: 32),
            _SettingsLabel('强调色'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < seedColorOptions.length; i++)
                  _SeedSwatch(
                    option: seedColorOptions[i],
                    selected: i == settings.seedIndexCache,
                    onTap: () => settings.setSeedIndex(i),
                  ),
              ],
            ),
            const Divider(height: 32),
            _SettingsLabel('正文字号'),
            Row(
              children: [
                const Text('小', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: settings.fontScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (v) => settings.setFontScale(v),
                  ),
                ),
                const Text('大', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                Text(
                  '${(settings.fontScale * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '写作'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.description_outlined,
                  scheme.primaryContainer, scheme.onPrimaryContainer),
              title: const Text('手账模板',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '内置 ${templates.builtinTemplates.length} 套 · 自建 ${templates.userTemplates.length} 套',
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TemplateManagerPage()),
              ),
            ),
            const _ReminderTile(),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '数据'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.auto_stories_rounded,
                  scheme.primaryContainer, scheme.onPrimaryContainer),
              title: const Text('手账篇数',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(
                '${journal.totalCount} 篇',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13.5,
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.sell_rounded,
                  scheme.secondaryContainer, scheme.onSecondaryContainer),
              title: const Text('标签个数',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(
                '${journal.allTags.length} 个',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13.5,
                ),
              ),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.delete_outline_rounded,
                  scheme.errorContainer, scheme.onErrorContainer),
              title: const Text('回收站',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                journal.trashedEntries.isEmpty
                    ? '删除的手账保留 30 天'
                    : '${journal.trashedEntries.length} 篇可恢复',
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrashPage()),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.archive_outlined,
                  scheme.secondaryContainer, scheme.onSecondaryContainer),
              title: const Text('导出备份',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('全部手账、模板与图片打包为 zip',
                  style: TextStyle(fontSize: 12.5)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _exportBackup(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(context, Icons.restore_outlined,
                  scheme.secondaryContainer, scheme.onSecondaryContainer),
              title: const Text('导入备份',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('从 zip 备份合并或覆盖恢复',
                  style: TextStyle(fontSize: 12.5)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _importBackup(context),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: _iconBox(context, Icons.image_outlined,
                  scheme.primaryContainer, scheme.onPrimaryContainer),
              title: const Text('分享图显示署名',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('导出长图底部附「拾页」标记',
                  style: TextStyle(fontSize: 12.5)),
              value: settings.shareSignatureEnabled,
              onChanged: (v) => settings.setShareSignature(v),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '隐私'),
        const SizedBox(height: 10),
        const _AppLockCard(),
        const SizedBox(height: 26),
        _sectionTitle(context, '关于'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary,
                          scheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child:
                        const Icon(Icons.auto_stories, color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '拾页',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'PageNote',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'v1.1.0 · 拾起生活中的每一页',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    return width < 900
        ? content
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: content,
            ),
          );
  }

  Widget _iconBox(
      BuildContext context, IconData icon, Color bg, Color fg) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }

  // ---------------- 备份导出 / 导入（REQ-03） ----------------

  Future<void> _exportBackup(BuildContext context) async {
    // 应用锁开启时导出需先验证（REQ-08.5）。
    final verified = await verifyAppLock(context, reason: '导出备份前需验证身份');
    if (!verified || !context.mounted) return;

    final journal = context.read<JournalProvider>();
    final templates = context.read<TemplateProvider>();
    try {
      final path = await BackupService.instance.exportBackup(
        entries: journal.entries,
        templates: templates.templates,
      );
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已导出：$path')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请重试')),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    BackupData data;
    try {
      data = await BackupService.instance.pickAndReadBackup() ??
          (throw const _BackupCanceled());
    } on _BackupCanceled {
      return;
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('读取备份文件失败')));
      return;
    }
    if (!context.mounted) return;

    // 选择导入模式（REQ-03.2/3.3）。
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入备份'),
        content: Text(
          '备份包含 ${data.entries.length} 篇手账、'
          '${data.templates.length} 个模板。\n\n'
          '· 合并：按条目去重，保留较新的版本\n'
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
    if (mode == null || !context.mounted) return;

    if (mode == 'overwrite') {
      // 覆盖模式二次确认（REQ-03.3）。
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认覆盖导入？'),
          content: const Text(
            '当前全部手账、模板与图片将被彻底删除，'
            '且无法恢复。确定继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE57373),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('覆盖导入'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    final journal = context.read<JournalProvider>();
    final templates = context.read<TemplateProvider>();
    final changed =
        await journal.importBackup(data, overwrite: mode == 'overwrite');
    await templates.importTemplates(data.templates,
        overwrite: mode == 'overwrite');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mode == 'overwrite'
            ? '已覆盖导入 ${data.entries.length} 篇手账'
            : '合并导入完成，更新 $changed 篇'),
      ),
    );
  }

  Widget _pageTitle(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, left: 4),
      child: Text(
        '设置',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
    );
  }
}

class _BackupCanceled implements Exception {
  const _BackupCanceled();
}

/// 写作提醒（REQ-07）：Android 可用；Windows 展示降级说明（REQ-07.4）。
class _ReminderTile extends StatelessWidget {
  const _ReminderTile();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (!NotificationService.instance.supported) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _iconBox(context, Icons.notifications_off_outlined,
            scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
        title: const Text('写作提醒',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('仅 Android 端支持本地提醒',
            style: TextStyle(fontSize: 12.5)),
        enabled: false,
      );
    }

    final minutes = settings.reminderMinutes;
    final timeLabel =
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _iconBox(context, Icons.notifications_active_outlined,
          scheme.primaryContainer, scheme.onPrimaryContainer),
      title: const Text('写作提醒',
          style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('每天 $timeLabel 提醒写手账',
          style: const TextStyle(fontSize: 12.5)),
      trailing: Switch(
        value: settings.reminderEnabled,
        onChanged: (v) => _onToggle(context, v),
      ),
      onTap: () => _pickTime(context),
    );
  }

  Widget _iconBox(BuildContext context, IconData icon, Color bg, Color fg) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }

  Future<void> _onToggle(BuildContext context, bool enabled) async {
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!enabled) {
      await settings.setReminder(false, settings.reminderMinutes);
      await NotificationService.instance.cancelDaily();
      return;
    }
    final granted = await NotificationService.instance.requestPermission();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('未获得通知权限，无法开启提醒')),
      );
      return;
    }
    final result = await NotificationService.instance
        .scheduleDaily(
            settings.reminderMinutes ~/ 60, settings.reminderMinutes % 60);
    if (!context.mounted) return;
    if (result == ReminderScheduleResult.denied) {
      messenger
          .showSnackBar(const SnackBar(content: Text('提醒调度失败，未开启')));
      return;
    }
    await settings.setReminder(true, settings.reminderMinutes);
    if (result == ReminderScheduleResult.inexact && context.mounted) {
      _showExactAlarmGuide(context);
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final initial = settings.reminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await settings.setReminder(settings.reminderEnabled, minutes);
    if (settings.reminderEnabled) {
      await NotificationService.instance
          .scheduleDaily(picked.hour, picked.minute);
    }
  }

  /// 精确闹钟权限被拒时的引导说明（REQ-07.2）。
  void _showExactAlarmGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('已降级为非精确提醒'),
        content: const Text(
          '精确闹钟权限未授予，提醒时间可能有几分钟偏差。\n'
          '如需准时提醒，请在 系统设置 → 应用 → 拾页 → 闹钟和提醒 中'
          '允许使用精确闹钟。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 应用锁卡片（REQ-08）。
class _AppLockCard extends StatelessWidget {
  const _AppLockCard();

  Future<void> _disableLock(BuildContext context) async {
    final ok = await verifyAppLock(context, reason: '关闭应用锁前需验证身份');
    if (!ok || !context.mounted) return;
    await context.read<SettingsProvider>().disableLock();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('应用锁已关闭')),
      );
    }
  }

  Future<void> _changePin(BuildContext context) async {
    final ok = await verifyAppLock(context, reason: '修改 PIN 前需验证身份');
    if (!ok || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PinSetupPage(skipRiskNotice: true)),
    );
  }

  Future<void> _pickDelay(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final index = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('从后台返回后多久需要解锁'),
        children: [
          RadioGroup<int>(
            groupValue: settings.lockDelayIndex,
            onChanged: (v) => Navigator.pop(dialogContext, v),
            child: Column(
              children: [
                for (var i = 0; i < lockDelayOptions.length; i++)
                  RadioListTile<int>(
                    value: i,
                    title: Text(switch (i) {
                      0 => '立即',
                      1 => '1 分钟后',
                      _ => '5 分钟后',
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (index != null) await settings.setLockDelayIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final enabled = settings.lockEnabled;

    return _SettingsCard(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _iconBox(
              context,
              enabled ? Icons.lock_rounded : Icons.lock_open_rounded,
              scheme.primaryContainer,
              scheme.onPrimaryContainer),
          title: const Text('应用锁',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            enabled
                ? '已开启 · ${settings.lockBiometric ? 'PIN + 生物识别' : 'PIN'}'
                : '进入应用需 PIN 或生物识别验证',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: enabled
              ? const Icon(Icons.chevron_right_rounded)
              : FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PinSetupPage()),
                  ),
                  child: const Text('开启'),
                ),
        ),
        if (enabled) ...[
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('修改 PIN', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _changePin(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('解锁时机', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              switch (settings.lockDelayIndex) {
                0 => '从后台返回立即锁定',
                1 => '从后台返回超过 1 分钟锁定',
                _ => '从后台返回超过 5 分钟锁定',
              },
              style: const TextStyle(fontSize: 12.5),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickDelay(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('关闭应用锁', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _disableLock(context),
          ),
        ],
      ],
    );
  }

  Widget _iconBox(BuildContext context, IconData icon, Color bg, Color fg) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 用 Material 承载背景与圆角，保证内部 ListTile 的水波纹可见。
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SeedColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: option.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 21)
              : null,
        ),
      ),
    );
  }
}
