import 'package:flutter/material.dart';

import '../models/activity.dart';

/// 当日活动多选（REQ-12.1）：预设图标 + 自定义活动名。
class ActivitySelector extends StatefulWidget {
  const ActivitySelector({
    super.key,
    required this.selected,
    required this.customActivities,
    required this.onChanged,
    required this.onAddCustom,
  });

  final List<String> selected;
  final List<String> customActivities;
  final ValueChanged<List<String>> onChanged;

  /// 新增自定义活动（同时入库，供下次使用）。
  final ValueChanged<String> onAddCustom;

  @override
  State<ActivitySelector> createState() => _ActivitySelectorState();
}

class _ActivitySelectorState extends State<ActivitySelector> {
  List<Activity> get _all {
    final customs = widget.customActivities
        .where((n) => !presetActivities.any((a) => a.name == n))
        .map((n) => Activity(customActivityEmoji, n))
        .toList();
    return [...presetActivities, ...customs];
  }

  void _toggle(String name) {
    if (widget.selected.contains(name)) {
      widget
          .onChanged(widget.selected.where((a) => a != name).toList());
    } else {
      widget.onChanged([...widget.selected, name]);
    }
  }

  Future<void> _showAddDialog() async {
    var pending = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加自定义活动'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '活动名称，如「撸猫」'),
          onChanged: (v) => pending = v,
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, pending),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    widget.onAddCustom(trimmed);
    _toggle(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '今日活动',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '做了什么？',
              style:
                  TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final activity in all)
              _activityChip(context, activity),
            ActionChip(
              avatar: Icon(Icons.add, size: 16, color: scheme.primary),
              label: Text(
                '自定义',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              onPressed: _showAddDialog,
            ),
          ],
        ),
      ],
    );
  }

  Widget _activityChip(BuildContext context, Activity activity) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected.contains(activity.name);
    return GestureDetector(
      onTap: () => _toggle(activity.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.7)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activity.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 5),
            Text(
              activity.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
