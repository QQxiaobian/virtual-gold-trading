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
    _drawText(canvas, prices[maxIdx].toStringAsFixed(2), Offset(xs[maxIdx] + 4, ys[maxIdx] - 4), hiStyle);
    _drawText(canvas, prices[minIdx].toStringAsFixed(2), Offset(xs[minIdx] + 4, ys[minIdx] - 4), hiStyle);

    // X 轴日期刻度：按时间比例均匀取 5 个，居中绘制并夹在绘图区内
    final dateStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    for (int i = 0; i <= 4; i++) {
      final ratio = i / 4;
      final dt = DateTime.fromMillisecondsSinceEpoch((t0 + tSpan * ratio).round());
      _drawTextCentered(
        canvas, _fmtDate(dt), padL + chartW * ratio, size.height - 15, dateStyle,
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

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, pos);
  }

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

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}
