import 'package:flutter/material.dart';
import '../models/data.dart';

/// 自绘金价走势图：折线 + 渐变面积填充 + 网格 + 最高最低标注。
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
    final padL = 46.0, padR = 12.0, padT = 16.0, padB = 26.0;
    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;

    final prices = points.map((p) => p.price).toList();
    double minP = prices.reduce((a, b) => a < b ? a : b);
    double maxP = prices.reduce((a, b) => a > b ? a : b);
    final span = (maxP - minP).abs() < 1e-6 ? 1.0 : (maxP - minP);
    minP -= span * 0.08;
    maxP += span * 0.08;
    final range = maxP - minP;

    // 网格线 + Y 轴刻度
    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.18)..strokeWidth = 1;
    final labelStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    for (int i = 0; i <= 4; i++) {
      final y = padT + chartH * i / 4;
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), gridPaint);
      final val = maxP - range * i / 4;
      _drawText(canvas, val.toStringAsFixed(0), Offset(2, y - 6), labelStyle);
    }

    // 采样点坐标
    final xs = <double>[], ys = <double>[];
    for (int i = 0; i < points.length; i++) {
      final x = padL + chartW * i / (points.length - 1).clamp(1, points.length - 1);
      final y = padT + chartH * (1 - (prices[i] - minP) / range);
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

    // 最高/最低标注
    int maxIdx = prices.indexOf(prices.reduce((a, b) => a > b ? a : b));
    int minIdx = prices.indexOf(prices.reduce((a, b) => a < b ? a : b));
    final hiStyle = TextStyle(color: const Color(0xFFB57B18), fontSize: 10, fontWeight: FontWeight.bold);
    _drawText(canvas, prices[maxIdx].toStringAsFixed(2), Offset(xs[maxIdx] + 4, ys[maxIdx] - 4), hiStyle);
    _drawText(canvas, prices[minIdx].toStringAsFixed(2), Offset(xs[minIdx] + 4, ys[minIdx] - 4), hiStyle);

    // X 轴首尾日期
    final dateStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    _drawText(canvas, _fmtDate(points.first.time), Offset(padL, size.height - 16), dateStyle);
    final endText = _fmtDate(points.last.time);
    _drawText(canvas, endText, Offset(size.width - padR - endText.length * 6.2, size.height - 16), dateStyle);
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, pos);
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}
