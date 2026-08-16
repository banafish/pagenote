import 'package:flutter/material.dart';

import 'models/journal_entry.dart';
import 'pages/editor_page.dart';
import 'pages/home_page.dart';
import 'pages/calendar_page.dart';
import 'pages/settings_page.dart';
import 'pages/stats_page.dart';
import 'providers/journal_provider.dart';
import 'services/notification_service.dart';
import 'utils/date_utils.dart';
import 'widgets/adaptive_scaffold.dart';

/// 应用根页面：导航骨架 + 编辑器路由。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  @override
  void initState() {
    super.initState();
    // 冷启动由写作提醒通知拉起时，直接进入编辑页（REQ-07.3）。
    NotificationService.instance
        .consumePendingAction(() => _newEntry(context));
  }

  void _openEditor(BuildContext context, JournalEntry? entry) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorPage(entry: entry)),
    );
  }

  void _newEntry(BuildContext context) {
    final now = DateTime.now();
    _openEditor(
      context,
      JournalEntry(
        id: JournalProvider.newId(),
        date: DateUtils2.dateKey(now),
        title: '',
        content: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return AdaptiveScaffold(
      destinations: const [
        AdaptiveDestination(
          label: '时光',
          icon: Icons.auto_stories_outlined,
          selectedIcon: Icons.auto_stories,
        ),
        AdaptiveDestination(
          label: '日历',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
        ),
        AdaptiveDestination(
          label: '统计',
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights_rounded,
        ),
        AdaptiveDestination(
          label: '设置',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
        ),
      ],
      bodyBuilder: (index) => switch (index) {
        0 => HomePage(onOpenEditor: _openEditor),
        1 => CalendarPage(onOpenEditor: _openEditor),
        2 => const StatsPage(),
        _ => const SettingsPage(),
      },
      floatingActionButton: wide
          ? FloatingActionButton.extended(
              onPressed: () => _newEntry(context),
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text('写手账'),
            )
          : FloatingActionButton(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              onPressed: () => _newEntry(context),
              child: const Icon(Icons.edit_rounded, size: 24),
            ),
    );
  }
}
