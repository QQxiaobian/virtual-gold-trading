import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/data.dart';

/// 自绘金价走势图：折线 + 渐变面积填充 + 网格 + 最高最低标注。
/// X 轴按每个点的真实时间比例定位（而非点索引），避免密集实时点把历史走势挤成一段直线；
/// Y 轴使用整齐刻度（1/2/2.5/5/10 系列），保证刻度数字工整、与价格标注吻合。
class PriceChart extends StatelessWidget {
  final List<PricePoint> points;
  final double height;
  const PriceChart({super.key, required this.points, this.height = 220});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(height: height, child: Center(child: Text('暂无行情数据', style: TextStyle(color: Colors.grey[400]))));
    }
    return SizedBox(height: height, child: CustomPaint(painter: _ChartPainter(points), child: Container()));
  }
}

class _ChartPainter extends CustomPainter {
  final List<PricePoint> points;
  _ChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 50.0, padR = 14.0, padT = 18.0, padB = 28.0;
    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;

    final prices = points.map((p) => p.price).toList();
    final rawMin = prices.reduce((a, b) => a < b ? a : b);
    final rawMax = prices.reduce((a, b) => a > b ? a : b);
    double dataMin = rawMin, dataMax = rawMax;
    if ((dataMax - dataMin).abs() < 1e-6) {
      dataMin -= 1;
      dataMax += 1;
    }

    // ---- Y 轴：整齐刻度 ----
    final step = _niceStep((dataMax - dataMin) / 5);
    final yMin = (dataMin / step).floor() * step;
    final yMax = (dataMax / step).ceil() * step;
    final yRange = (yMax - yMin).abs() < 1e-6 ? step : yMax - yMin;

    // ---- X 轴：按真实时间比例 ----
    final t0 = points.first.time.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.time.millisecondsSinceEpoch.toDouble();
    double tSpan = t1 - t0;
    if (tSpan < 1) tSpan = 1;

    // 网格线 + Y 轴刻度
    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.18)..strokeWidth = 1;
    final labelStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    final tickCount = (yRange / step).round().clamp(1, 8);
    for (int i = 0; i <= tickCount; i++) {
      final val = yMin + step * i;
      final y = padT + chartH * (1 - (val - yMin) / yRange);
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), gridPaint);
      _drawText(canvas, _fmtTick(val, step), Offset(2, y - 6), labelStyle);
    }

    // 采样点坐标：X 用真实时间，Y 用价格
    final xs = <double>[], ys = <double>[];
    for (int i = 0; i < points.length; i++) {
      final x = padL + chartW * ((points[i].time.millisecondsSinceEpoch - t0) / tSpan);
      final y = padT + chartH * (1 - (prices[i] - yMin) / yRange);
      xs.add(x);
      ys.add(y);
    }

    // 面积渐变
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFD9A441).withOpacity(0.35), const Color(0xFFD9A441).withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(padL, padT, chartW, chartH));
    final path = Path()..moveTo(xs.first, padT + chartH);
    for (int i = 0; i < xs.length; i++) {
      path.lineTo(xs[i], ys[i]);
    }
    path.lineTo(xs.last, padT + chartH);
    path.close();
    canvas.drawPath(path, areaPaint);

    // 折线
    final linePaint = Paint()
      ..color = const Color(0xFFC9932F)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(xs.first, ys.first);
    for (int i = 1; i < xs.length; i++) {
      linePath.lineTo(xs[i], ys[i]);
    }
    canvas.drawPath(linePath, linePaint);

    // 最高/最低标注（用原始极值定位，避免全平线扩展后 indexOf 找不到）
    final maxIdx = prices.indexOf(rawMax);
    final minIdx = prices.indexOf(rawMin);
    final hiStyle = TextStyle(color: const Color(0xFFB57B18), fontSize: 10, fontWeight: FontWeight.bold);
    // 标注放在点的上方，并夹紧 X 范围，避免最右/最左端的标注越界被截断或与日期轴重叠。
    _drawTextClamped(
      canvas, prices[maxIdx].toStringAsFixed(2), xs[maxIdx], ys[maxIdx] - 16, hiStyle,
      left: padL, right: size.width - padR,
    );
    _drawTextClamped(
      canvas, prices[minIdx].toStringAsFixed(2), xs[minIdx], ys[minIdx] - 16, hiStyle,
      left: padL, right: size.width - padR,
    );

    // X 轴日期刻度：短格式 MM-DD，按可用宽度自适应标签数量，避免窄屏标签重叠。
    final dateStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    final sampleW = _textWidth('08-26', dateStyle);
    final maxLabels = (chartW / (sampleW + 22)).floor().clamp(2, 5);
    for (int i = 0; i < maxLabels; i++) {
      final ratio = maxLabels == 1 ? 0.0 : i / (maxLabels - 1);
      final dt = DateTime.fromMillisecondsSinceEpoch((t0 + tSpan * ratio).round());
      _drawTextCentered(
        canvas, _fmtDateShort(dt), padL + chartW * ratio, size.height - 15, dateStyle,
        left: padL, right: size.width - padR,
      );
    }
  }

  /// 把任意步长规整到 1/2/2.5/5/10 × 10^n，得到工整的刻度间隔。
  double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    if (n <= 1) return mag;
    if (n <= 2) return 2 * mag;
    if (n <= 2.5) return 2.5 * mag;
    if (n <= 5) return 5 * mag;
    return 10 * mag;
  }

  String _fmtTick(double v, double step) => step >= 1 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double _textWidth(String text, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    return tp.width;
  }

  void _drawText(
    Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, pos);
  }

  /// 以 cx 为中心绘制文本，并夹紧在 [left, right] 内，防止越界被截断。
  void _drawTextCentered(
    Canvas canvas, String text, double cx, double y, TextStyle style,
    {required double left, required double right}) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    double x = cx - tp.width / 2;
    if (x < left) x = left;
    if (x + tp.width > right) x = right - tp.width;
    tp.paint(canvas, Offset(x, y));
  }

  /// 以锚点 x 为起点绘制文本（略右偏移），越界时自动翻转到锚点左侧，保证完整可见。
  void _drawTextClamped(
    Canvas canvas, String text, double anchorX, double y, TextStyle style,
    {required double left, required double right}) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    final w = tp.width;
    double x = anchorX + 4;              // 默认在锚点右侧
    if (x + w > right) x = anchorX - w - 4;  // 右侧放不下则翻到左侧
    if (x < left) x = left;              // 左边界兜底
    if (x + w > right) x = right - w;    // 右边界兜底
    tp.paint(canvas, Offset(x, y));
  }

  String _fmtDateShort(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}
