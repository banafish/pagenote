import 'package:flutter/material.dart';

/// 目标平台布局：手机用底部导航栏，平板/桌面用侧边导航栏。
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.bodyBuilder,
    this.floatingActionButton,
    this.floatingActionButtonTabs,
  });

  final List<AdaptiveDestination> destinations;
  final Widget Function(int index) bodyBuilder;
  final Widget? floatingActionButton;

  /// 允许显示 [floatingActionButton] 的页签下标；null 表示全部页签都显示。
  final Set<int>? floatingActionButtonTabs;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class AdaptiveDestination {
  const AdaptiveDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showFab =
        widget.floatingActionButtonTabs?.contains(_index) ?? true;
    final fab = showFab ? widget.floatingActionButton : null;
    // 四个一级入口同时挂载、只切换显示层（NFR-09）：滚动位置、选中日期、
    // 当前子页签与排序方式在切换后原样保留，切换本身也不触发任何 provider 重载。
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < widget.destinations.length; i++)
          widget.bodyBuilder(i),
      ],
    );

    if (width >= 700) {
      final extended = width >= 1050;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              extended: extended,
              minExtendedWidth: 190,
              leading: Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 10),
                child: _BrandMark(extended: extended),
              ),
              destinations: [
                for (final d in widget.destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerTheme.color,
            ),
            Expanded(child: body),
          ],
        ),
        floatingActionButton: fab,
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in widget.destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(Icons.auto_stories, color: Colors.white, size: 23),
    );
    if (!extended) return logo;
    return Row(
      children: [
        logo,
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '拾页',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            Text(
              'PageNote',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
