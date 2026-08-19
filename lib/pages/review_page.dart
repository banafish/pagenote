import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import 'calendar_page.dart';
import 'stats_page.dart';

/// 「回顾」宿主页（REQ-24）：日历与统计合并为同一个一级入口，
/// 内部分「日历 / 统计」两个子页签，默认落在日历——高频项不为合并付出点击成本。
///
/// 子页签用 IndexedStack 切换而非 TabBarView：两页的滚动位置、选中日期与
/// 当前月份在页签切换、一级入口切换后都原样保留（REQ-24.5 / NFR-09）。
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('回顾'),
          bottom: TabBar(
            // 页签点击驱动 IndexedStack；控制器本身没有 TabBarView，
            // 指示器动画与内容切换各自独立、互不牵连。
            onTap: (index) => setState(() => _tab = index),
            tabs: const [Tab(text: '日历'), Tab(text: '统计')],
          ),
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            CalendarPage(onOpenEditor: widget.onOpenEditor),
            const StatsPage(),
          ],
        ),
      ),
    );
  }
}
