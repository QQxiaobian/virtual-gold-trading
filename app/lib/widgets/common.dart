import 'package:flutter/material.dart';

/// 涨红跌绿（中国市场习惯）
Color pnlColor(double v) => v > 0 ? const Color(0xFFE23E3E) : (v < 0 ? const Color(0xFF1FA463) : const Color(0xFF8A7A68));
String money(double v, {int digits = 2}) => v.toStringAsFixed(digits);

/// 暖橙渐变背景，还原参考图顶部氛围
class WarmBackground extends StatelessWidget {
  final Widget child;
  const WarmBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE3C8), Color(0xFFFFF3E8), Color(0xFFFFF7F0)],
          stops: [0.0, 0.35, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// 白色圆角卡片
class GoldCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const GoldCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.orange.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

void showError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: const Color(0xFFC0392B)),
  );
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1FA463)),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String content) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      ) ??
      false;
}
