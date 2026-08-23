import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import 'calendar_page.dart';
import 'stats_page.dart';

/// 「回顾」宿主页（REQ-24）：日历与统计合并为同一个一级入口。
///
/// 窄屏（<900dp）：默认展示日历，右上角统计图标进入独立的统计页。
/// 日历常驻不卸载，从统计页返回后滚动位置、选中日期与当前月份原样保留
/// （REQ-24.5 / NFR-09）。
/// 宽屏（≥900dp）：左栏日历、右栏统计并排同屏，两页常驻，无需入口。
class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key, required this.onOpenEditor});

  final void Function(BuildContext context, JournalEntry? entry) onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回顾'),
        actions: [
          // 宽屏统计与日历并排同屏，入口只在窄屏出现。
          if (!wide) ...[
            IconButton(
              tooltip: '统计',
              icon: const Icon(Icons.insights_rounded),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const _StatsScreen())),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: wide
          ? _wideBody(context)
          : CalendarPage(onOpenEditor: onOpenEditor),
    );
  }

  /// 宽屏：左栏日历（含当日列表）、右栏统计并排同屏。
  Widget _wideBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 460,
          child: CalendarPage(onOpenEditor: onOpenEditor),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).dividerTheme.color,
        ),
        const Expanded(child: _StatsPane()),
      ],
    );
  }
}

/// 窄屏统计页：由「回顾」右上角图标进入的独立页面，带返回。
class _StatsScreen extends StatelessWidget {
  const _StatsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: const StatsPage(),
    );
  }
}

/// 宽屏右栏：统计视图 + 与左栏月份标题同款排版的栏目标题。
class _StatsPane extends StatelessWidget {
  const _StatsPane();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Text(
            '统计',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Expanded(child: StatsPage()),
      ],
    );
  }
}
