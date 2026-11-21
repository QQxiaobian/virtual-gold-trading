import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/data.dart';
import '../widgets/common.dart';

class RecordsTab extends StatefulWidget {
  const RecordsTab({super.key});
  @override
  State<RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<RecordsTab> {
  List<Tx> _txs = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final data = await Api.transactions();
      if (!mounted) return;
      setState(() {
        _txs = (data as List).map((e) => Tx.fromJson(e)).toList();
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() { _err = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WarmBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20, top: 10),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text('交易明细', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
              ),
              if (_loading)
                const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
              else if (_err != null)
                Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_err!, style: const TextStyle(color: Colors.red))))
              else if (_txs.isEmpty)
                Padding(padding: const EdgeInsets.all(60), child: Center(child: Text('暂无交易记录', style: TextStyle(color: Colors.grey[400]))))
              else
                ..._txs.map(_txCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _txCard(Tx t) {
    final color = t.type == 'recharge' || t.type == 'sell'
        ? const Color(0xFFE23E3E)
        : const Color(0xFF1FA463);
    final sign = t.amount >= 0 ? '+' : '';
    return GoldCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(_icon(t.type), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(t.typeLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
                  Text('$sign${t.amount.toStringAsFixed(2)} 元', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                ]),
                const SizedBox(height: 4),
                if (t.grams != 0) Text('克重 ${t.grams.toStringAsFixed(4)} 克 · 价格 ${t.price.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                if (t.fee > 0) Text('手续费 ${t.fee.toStringAsFixed(2)} 元（${t.feeDesc}）', style: const TextStyle(fontSize: 11, color: Color(0xFFB5791B))),
                if (t.realizedPnl != 0) Text('盈亏 ${t.realizedPnl.toStringAsFixed(2)} 元', style: TextStyle(fontSize: 11, color: pnlColor(t.realizedPnl))),
                if (t.note.isNotEmpty) Text(t.note, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 4),
                Text(_fmtTime(t.createdAt), style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String type) => {'recharge': Icons.add_circle, 'buy': Icons.shopping_cart, 'sell': Icons.sell, 'adjust': Icons.tune}[type] ?? Icons.receipt;
  String _fmtTime(String s) {
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return s;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
