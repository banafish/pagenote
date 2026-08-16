import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/activity.dart';
import '../../models/app_fonts.dart';
import '../../models/canvas_page.dart';
import '../../models/decoration.dart';
import '../../models/journal_entry.dart';
import '../../models/sticker_assets.dart';
import '../../utils/date_utils.dart';

/// 元素树画布的静态渲染器（调研三阶段）：背景纸张 + 按 z 序铺元素。
/// 编辑器、时间线卡片、分享长图共用同一渲染逻辑,任意实际宽度下
/// 按页宽比例无损缩放,保证所见即所得。
class CanvasView extends StatelessWidget {
  const CanvasView({
    super.key,
    required this.canvas,
    required this.entry,
    this.placeholderImages = false,
  });

  final JournalCanvas canvas;

  /// 结构化数据来源（日期/心情/天气/活动组件从条目字段读取）。
  final JournalEntry entry;

  /// true 时空路径图片渲染为「添加照片」占位（编辑态）;
  /// false 渲染为灰色照片底（预览态）。
  final bool placeholderImages;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;
        final pageHeight = canvas.effectiveHeight * pageWidth;
        final paper = paperById(canvas.paperId);

        return SizedBox(
          width: pageWidth,
          height: pageHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: paper == null
                    ? const ColoredBox(color: Colors.white)
                    : CustomPaint(
                        painter: PaperPainter(paper),
                        size: Size(pageWidth, pageHeight),
                      ),
              ),
              for (final element in canvas.elements)
                Positioned(
                  left: element.x * pageWidth,
                  top: element.y * pageWidth,
                  width: element.w * pageWidth,
                  height: _elementHeight(element, pageWidth),
                  child: Opacity(
                    opacity: element.opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: element.rotation * math.pi / 180,
                      child: _buildElement(context, element, pageWidth),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 文本元素高度按内容实测;其余元素用存储高度。
  double _elementHeight(CanvasElement e, double pageWidth) {
    if (e is TextElement) {
      return math.max(e.h, measureTextHeight(e)) * pageWidth;
    }
    return e.h * pageWidth;
  }

  Widget _buildElement(BuildContext context, CanvasElement e, double pw) {
    return switch (e) {
      TextElement() => _TextElementView(element: e, pw: pw),
      ImageElement() => _ImageElementView(
          element: e,
          pw: pw,
          placeholder: placeholderImages,
        ),
      StickerElement() => _StickerElementView(element: e, pw: pw),
      TapeElement() => CustomPaint(
          size: Size(e.w * pw, e.h * pw),
          painter: TapePainter(
            style: e.style,
            color: Color(e.color),
          ),
        ),
      StructuredElement() => _ComponentView(element: e, entry: entry, pw: pw),
    };
  }
}

/// 文本框元素：花样字体 + 字号/颜色/对齐（调研一阶段）。
class _TextElementView extends StatelessWidget {
  const _TextElementView({required this.element, required this.pw});

  final TextElement element;
  final double pw;

  @override
  Widget build(BuildContext context) {
    final align = switch (element.align) {
      1 => TextAlign.center,
      2 => TextAlign.right,
      _ => TextAlign.left,
    };
    return SizedBox.expand(
      child: Text(
        element.text,
        style: TextStyle(
          fontSize: element.fontScale * pw,
          height: element.lineHeight,
          color: Color(element.color),
          fontFamily: element.fontFamily.isEmpty ? null : element.fontFamily,
          fontFamilyFallback:
              element.fontFamily.isEmpty ? null : canvasFontFallback,
          fontWeight: element.bold ? FontWeight.w700 : FontWeight.w400,
        ),
        textAlign: align,
      ),
    );
  }
}

/// 图片元素：圆形 / 拍立得遮罩（调研一阶段「照片贴纸化」）。
class _ImageElementView extends StatelessWidget {
  const _ImageElementView({
    required this.element,
    required this.pw,
    this.placeholder = false,
  });

  final ImageElement element;
  final double pw;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (element.path.isEmpty) {
      return _placeholderBox(context, scheme);
    }
    final image = Image.file(
      File(element.path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholderBox(context, scheme),
    );
    return switch (element.mask) {
      ImageMask.circle => AspectRatio(
          aspectRatio: 1,
          child: ClipOval(child: image),
        ),
      ImageMask.polaroid => Container(
          padding: EdgeInsets.only(
            left: 0.02 * pw,
            right: 0.02 * pw,
            top: 0.02 * pw,
            bottom: 0.07 * pw,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 0.01 * pw,
                offset: Offset(0, 0.004 * pw),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: AspectRatio(aspectRatio: 1, child: image),
          ),
        ),
      ImageMask.none => ClipRRect(
          borderRadius: BorderRadius.circular(element.radius * pw),
          child: image,
        ),
    };
  }

  Widget _placeholderBox(BuildContext context, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant,
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: placeholder
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 0.08 * pw,
                  color: scheme.onSurfaceVariant,
                ),
                if (pw > 240)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '添加照片',
                      style: TextStyle(
                        fontSize: 0.028 * pw,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            )
          : Icon(
              Icons.image_outlined,
              size: 0.08 * pw,
              color: scheme.onSurfaceVariant,
            ),
    );
  }
}

/// 贴纸元素：矢量贴纸（免抠）或 emoji。
class _StickerElementView extends StatelessWidget {
  const _StickerElementView({required this.element, required this.pw});

  final StickerElement element;
  final double pw;

  @override
  Widget build(BuildContext context) {
    final key = element.key;
    if (key.startsWith('vec:')) {
      return CustomPaint(
        size: Size(element.w * pw, element.h * pw),
        painter: StickerPainter(key.substring(4)),
      );
    }
    final emoji = key.startsWith('emoji:') ? key.substring(6) : key;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(emoji),
      ),
    );
  }
}

/// 结构化组件元素：日期 / 心情 / 天气 / 活动。
/// 数据实时读自条目结构化字段 —— 统计页照常可用（差异化定位）。
class _ComponentView extends StatelessWidget {
  const _ComponentView({required this.element, required this.entry, required this.pw});

  final StructuredElement element;
  final JournalEntry entry;
  final double pw;

  @override
  Widget build(BuildContext context) {
    final ink = _inkOn(entry.canvas?.paperId ?? '');

    switch (element.kind) {
      case ComponentKind.date:
        final date = DateUtils2.parseKey(entry.date);
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 0.032 * pw,
                color: ink.withValues(alpha: 0.75),
              ),
              SizedBox(width: 0.014 * pw),
              Flexible(
                child: Text(
                  '${date.year}年${date.month}月${date.day}日 · ${DateUtils2.weekdayOf(entry.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 0.034 * pw,
                    fontWeight: FontWeight.w600,
                    color: ink,
                    fontFamilyFallback: canvasFontFallback,
                  ),
                ),
              ),
            ],
          ),
        );
      case ComponentKind.mood:
        final mood = entry.mood;
        if (mood == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 0.026 * pw,
              vertical: 0.012 * pw,
            ),
            decoration: BoxDecoration(
              color: mood.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(0.02 * pw),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mood.emoji, style: TextStyle(fontSize: 0.05 * pw)),
                SizedBox(width: 0.012 * pw),
                Flexible(
                  child: Text(
                    mood.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 0.03 * pw,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      fontFamilyFallback: canvasFontFallback,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case ComponentKind.weather:
        final weather = entry.weather;
        if (weather == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(weather.emoji, style: TextStyle(fontSize: 0.05 * pw)),
              SizedBox(width: 0.012 * pw),
              Flexible(
                child: Text(
                  weather.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 0.03 * pw,
                    color: ink.withValues(alpha: 0.9),
                    fontFamilyFallback: canvasFontFallback,
                  ),
                ),
              ),
            ],
          ),
        );
      case ComponentKind.activities:
        if (entry.activities.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 0.02 * pw,
            runSpacing: 0.008 * pw,
            children: [
              for (final activity in entry.activities)
                Text(
                  emojiOfActivity(activity),
                  style: TextStyle(fontSize: 0.048 * pw),
                ),
            ],
          ),
        );
    }
  }

  /// 画布恒为浅色渲染（与分享导出一致,WYSIWYG）;
  /// 深色纸（夜墨）上用浅墨,其余用深墨。
  Color _inkOn(String paperId) {
    if (paperId == 'inkstone') return const Color(0xFFEDE7DD);
    return const Color(0xFF4A3F35);
  }
}
