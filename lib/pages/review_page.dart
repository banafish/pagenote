import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import 'calendar_page.dart';
import 'stats_page.dart';

/// 「回顾」宿主页（REQ-24）：日历与统计合并为同一个一级入口。
///
/// 窄屏（<900dp）：页首居中的分段控件切换「日历 / 统计」，默认落在日历——
/// 高频项不为合并付出点击成本；子视图用 IndexedStack 而非 TabBarView：
/// 滚动位置、选中日期与当前月份在切换后原样保留（REQ-24.5 / NFR-09）。
/// 宽屏（≥900dp）：左栏日历、右栏统计并排同屏，两页常驻，无需切换。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.onOpenEditor});

  final void Function(BuildContext context, JournalEntry? entry) onOpenEditor;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(title: const Text('回顾')),
      body: wide ? _wideBody(context) : _compactBody(),
    );
  }

  /// 窄屏：分段控件 + IndexedStack。与统计页「7/30/90 天」同款控件语言
  /// （showSelectedIcon 关闭、带图标），避免与底部导航形成双层页签。
  Widget _compactBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.calendar_month_rounded),
                  label: Text('日历'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.insights_rounded),
                  label: Text('统计'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (set) => setState(() => _tab = set.first),
              showSelectedIcon: false,
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              CalendarPage(onOpenEditor: widget.onOpenEditor),
              const StatsPage(),
            ],
          ),
        ),
      ],
    );
  }

  /// 宽屏：左栏日历（含当日列表）、右栏统计并排同屏。
  Widget _wideBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 460,
          child: CalendarPage(onOpenEditor: widget.onOpenEditor),
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
