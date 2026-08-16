import 'package:flutter/material.dart';

import '../utils/date_utils.dart';

/// 心情趋势折线图（REQ-05）。
///
/// 数据为逐日心情均分（1–10）；无记录的日期在图中留空断开，
/// 不做插值，避免误导（REQ-05.3）。
class MoodTrendChart extends StatelessWidget {
  const MoodTrendChart({super.key, required this.points});

  /// 有数据的日期点（旧→新），score 为当日均分。
  final List<(String date, double score)> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30),
        alignment: Alignment.center,
        child: Text(
          '区间内还没有带心情的手账',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
        ),
      );
    }

    final scores = points.map((p) => p.$2).toList();
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    var maxPoint = points.first;
    var minPoint = points.first;
    for (final p in points) {
      if (p.$2 > maxPoint.$2) maxPoint = p;
      if (p.$2 < minPoint.$2) minPoint = p;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: _TrendPainter(
            points: points,
            lineColor: scheme.primary,
            dotColor: scheme.primary,
            gridColor: scheme.outlineVariant.withValues(alpha: 0.4),
            labelColor: scheme.onSurfaceVariant,
            avgValue: avg,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _Summary(label: '区间平均', value: avg.toStringAsFixed(1)),
            _Summary(
              label: '最高',
              value:
                  '${maxPoint.$2.toStringAsFixed(1)} · ${DateUtils2.monthDay(maxPoint.$1)}',
            ),
            _Summary(
              label: '最低',
              value:
                  '${minPoint.$2.toStringAsFixed(1)} · ${DateUtils2.monthDay(minPoint.$1)}',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '无记录的日期在图中留空断开，不做插值',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends StatelessWidget {
  const _TrendPainter({
    required this.points,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelColor,
    required this.avgValue,
  });

  final List<(String, double)> points;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color labelColor;
  final double avgValue;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainterDelegate(
        points: points,
        lineColor: lineColor,
        dotColor: dotColor,
        gridColor: gridColor,
        labelColor: labelColor,
        avgValue: avgValue,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TrendPainterDelegate extends CustomPainter {
  _TrendPainterDelegate({
    required this.points,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelColor,
    required this.avgValue,
  });

  final List<(String, double)> points;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color labelColor;
  final double avgValue;

  static const _min = 0.0;
  static const _max = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 26.0;
    final bottomPad = 18.0;
    final chartWidth = size.width - leftPad;
    final chartHeight = size.height - bottomPad;

    // 纵轴刻度（0/5/10）与横线。
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelTp = TextStyle(color: labelColor, fontSize: 10);
    for (final v in [0.0, 5.0, 10.0]) {
      final y = _yOf(v, chartHeight);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      _text(
        canvas,
        v == v.roundToDouble() ? '${v.toInt()}' : v.toString(),
        Offset(0, y - 6),
        labelTp,
      );
    }

    if (points.length == 1) {
      // 单点：只画点。
      final c = Offset(leftPad + chartWidth / 2,
          _yOf(points.first.$2, chartHeight));
      canvas.drawCircle(c, 4.5, Paint()..color = dotColor);
      _drawDateLabel(canvas, points.first.$1, leftPad, size, chartHeight);
      return;
    }

    // x 轴按日期在区间内的比例分布。
    final dates = points.map((p) => DateUtils2.parseKey(p.$1)).toList();
    final firstDay = dates.first;
    final lastDay = dates.last;
    final spanDays = lastDay.difference(firstDay).inDays == 0
        ? 1
        : lastDay.difference(firstDay).inDays;

    Offset offsetOf(int i) => Offset(
          leftPad +
              dates[i].difference(firstDay).inDays / spanDays * chartWidth,
          _yOf(points[i].$2, chartHeight),
        );

    // 平均线（虚线）。
    final avgY = _yOf(avgValue, chartHeight);
    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    var dashX = leftPad;
    while (dashX < size.width) {
      canvas.drawLine(
          Offset(dashX, avgY), Offset(dashX + 5, avgY), dashPaint);
      dashX += 10;
    }

    // 折线。
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i + 1 < points.length; i++) {
      canvas.drawLine(offsetOf(i), offsetOf(i + 1), linePaint);
    }

    // 数据点。
    final dotPaint = Paint()..color = dotColor;
    final maxScore = points
        .reduce((a, b) => a.$2 >= b.$2 ? a : b);
    final minScore = points
        .reduce((a, b) => a.$2 <= b.$2 ? a : b);
    for (var i = 0; i < points.length; i++) {
      final isExtreme =
          points[i] == maxScore || points[i] == minScore;
      canvas.drawCircle(
          offsetOf(i), isExtreme ? 5 : 3.2, dotPaint);
    }

    // 首末日期横轴标签。
    _drawDateLabel(canvas, points.first.$1, leftPad, size, chartHeight);
    _drawDateLabel(canvas, points.last.$1, size.width - 34, size, chartHeight);
  }

  void _drawDateLabel(
      Canvas canvas, String key, double x, Size size, double chartHeight) {
    _text(
      canvas,
      DateUtils2.monthDay(key),
      Offset(x.clamp(0, size.width - 34), chartHeight + 4),
      TextStyle(color: labelColor, fontSize: 10),
    );
  }

  double _yOf(double score, double chartHeight) =>
      chartHeight - (score - _min) / (_max - _min) * chartHeight;

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainterDelegate old) =>
      old.points != points || old.avgValue != avgValue;
}
