import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/decoration.dart';

/// 单个贴纸的静态渲染（编辑层与分享长图共用,保证导出所见即所得）。
class StickerView extends StatelessWidget {
  const StickerView({super.key, required this.sticker, this.selected = false});

  final Sticker sticker;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final emoji = Transform.rotate(
      angle: sticker.rotation * math.pi / 180,
      child: Text(
        sticker.emoji,
        style: TextStyle(
          fontSize: stickerBaseFontSize * sticker.scale,
          height: 1.1,
        ),
      ),
    );
    if (!selected) return emoji;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 1.4,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: emoji,
    );
  }
}

/// 贴纸层（REQ-13）：按归一化坐标把贴纸铺满父容器。
/// 传入 [onChanged] 即为编辑交互层（拖拽移动、点按选中）;
/// 不传则作为静态渲染层（分享长图导出）,坐标映射与编辑时完全一致。
class StickerOverlay extends StatelessWidget {
  const StickerOverlay({
    super.key,
    required this.stickers,
    this.selectedIndex = -1,
    this.onChanged,
    this.onSelect,
  });

  final List<Sticker> stickers;

  /// 当前选中贴纸下标;-1 为无选中。
  final int selectedIndex;

  /// 位置/内容变化后的回调。
  final VoidCallback? onChanged;

  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (stickers.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return const SizedBox.shrink();
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < stickers.length; i++)
              Positioned(
                left: stickers[i].dx * w,
                top: stickers[i].dy * h,
                child: FractionalTranslation(
                  // 锚点随位置移动:贴纸在页面内始终完整可见。
                  translation: Offset(-stickers[i].dx, -stickers[i].dy),
                  child: onChanged == null
                      ? StickerView(sticker: stickers[i])
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) {
                            final s = stickers[i];
                            s.dx = (s.dx + details.delta.dx / w).clamp(
                              0.0,
                              1.0,
                            );
                            s.dy = (s.dy + details.delta.dy / h).clamp(
                              0.0,
                              1.0,
                            );
                            onChanged!();
                          },
                          onTap: () => onSelect?.call(i),
                          child: StickerView(
                            sticker: stickers[i],
                            selected: i == selectedIndex,
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 选中贴纸的操作条:删除 / 缩放 / 旋转 / 完成。
class StickerToolbar extends StatelessWidget {
  const StickerToolbar({
    super.key,
    required this.sticker,
    required this.onChanged,
    required this.onDelete,
    required this.onDone,
  });

  final Sticker sticker;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(sticker.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                '拖动移动 · 滑杆调整',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                tooltip: '删除贴纸',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: scheme.error,
                ),
                onPressed: onDelete,
              ),
              TextButton(onPressed: onDone, child: const Text('完成')),
            ],
          ),
          Row(
            children: [
              Icon(
                Icons.zoom_out_map_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  value: sticker.scale.clamp(0.5, 2.5),
                  min: 0.5,
                  max: 2.5,
                  onChanged: (v) {
                    sticker.scale = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.rotate_right_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  value: sticker.rotation.clamp(-180, 180),
                  min: -180,
                  max: 180,
                  onChanged: (v) {
                    sticker.rotation = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
