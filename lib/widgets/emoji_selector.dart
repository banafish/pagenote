import 'package:flutter/material.dart';

class EmojiItem {
  const EmojiItem({
    required this.id,
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String id;
  final String emoji;
  final String label;
  final Color color;
}

/// 心情/天气的横向表情选择器，可取消选择。
class EmojiSelector extends StatelessWidget {
  const EmojiSelector({
    super.key,
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final String label;
  final List<EmojiItem> items;
  final String? selectedId;
  final void Function(String? id) onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              final selected = item.id == selectedId;
              return GestureDetector(
                onTap: () =>
                    onSelected(selected ? null : item.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 64,
                  decoration: BoxDecoration(
                    color: selected
                        ? item.color.withValues(alpha: 0.18)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? item.color
                          : Colors.transparent,
                      width: 1.8,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item.emoji,
                          style: const TextStyle(fontSize: 25)),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
