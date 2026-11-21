import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/data.dart';
import '../widgets/common.dart';
import '../widgets/price_chart.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});
  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Portfolio? _p;
  List<PricePoint> _points = [];
  String _range = '1y';
  bool _loading = true;
  String? _err;
  double? _changePct;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final p = await Api.portfolio();
      final h = await Api.history(_range);
      final pts = (h['points'] as List? ?? []).map((e) => PricePoint.fromJson(e)).toList();
      double? chg;
      if (pts.length >= 2) {
        final first = pts.first.price, last = pts.last.price;
        if (first > 0) chg = (last - first) / first * 100;
      }
      if (!mounted) return;
      setState(() {
        _p = Portfolio.fromJson(p);
        _points = pts;
        _changePct = chg;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() { _err = e.message; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = '加载失败：$e'; _loading = false; });
    }
  }

  Future<void> _switchRange(String r) async {
    setState(() => _range = r);
    try {
      final h = await Api.history(r);
      final pts = (h['points'] as List? ?? []).map((e) => PricePoint.fromJson(e)).toList();
      double? chg;
      if (pts.length >= 2 && pts.first.price > 0) chg = (pts.last.price - pts.first.price) / pts.first.price * 100;
      if (!mounted) return;
      setState(() { _points = pts; _changePct = chg; });
    } catch (_) {}
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
              _header(),
              if (_loading)
                const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
              else if (_err != null)
                Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_err!, style: const TextStyle(color: Colors.red))))
              else ...[
                _portfolioCard(),
                _quickActions(),
                _chartCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: const [
                Icon(Icons.check_circle_outline, size: 14, color: Color(0xFFB5791B)),
                SizedBox(width: 3), Text('实时报价', style: TextStyle(fontSize: 12, color: Color(0xFF7A6246))),
              ]),
              Row(children: const [
                Icon(Icons.check_circle_outline, size: 14, color: Color(0xFFB5791B)),
                SizedBox(width: 3), Text('交易便捷', style: TextStyle(fontSize: 12, color: Color(0xFF7A6246))),
              ]),
              Row(children: const [
                Icon(Icons.check_circle_outline, size: 14, color: Color(0xFFB5791B)),
                SizedBox(width: 3), Text('可兑换实物金', style: TextStyle(fontSize: 12, color: Color(0xFF7A6246))),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard() {
    final p = _p!;
    return GoldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('持仓金额(元)', style: TextStyle(fontSize: 14, color: Color(0xFF6B5A45))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF0DB), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFF0D3A0))),
                child: const Text('日交易明细', style: TextStyle(fontSize: 10, color: Color(0xFFB5791B))),
              ),
              const Spacer(),
              Icon(Icons.help_outline, size: 18, color: Colors.grey[400]),
            ],
          ),
          const SizedBox(height: 8),
          Text(money(p.marketValue), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF2E2A26), letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text('持仓克重=${p.grams.toStringAsFixed(4)}克，成本均价=${p.avgCost.toStringAsFixed(2)}元/克',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A68))),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pnlCell('交易时间更新', null, isLabel: true),
              _pnlCell('今日收益(元)', p.todayPnl),
              _pnlCell('持仓收益(元)', p.holdingPnl),
              _pnlCell('累计收益(元)', p.totalPnl),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pnlCell(String label, double? value, {bool isLabel = false}) {
    if (isLabel) {
      return Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]));
    }
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((value! >= 0 ? '+' : '') + money(value), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pnlColor(value))),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return GoldCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _action(Icons.card_giftcard, '兑换实物', () => showOk(context, '兑换实物：自用模拟盘暂未开放')),
          _action(Icons.savings, '黄金定投', () => showOk(context, '黄金定投：可在交易页按需买入')),
          _action(Icons.calendar_month, '黄金定期', () => showOk(context, '黄金定期：自用模拟盘暂未开放')),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFFC9932F)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF5A4A38))),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final chg = _changePct;
    return GoldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFC9932F), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${_rangeLabel(_range)}涨跌幅', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5A4A38))),
              const SizedBox(width: 8),
              if (chg != null)
                Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pnlColor(chg))),
              const Spacer(),
              Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
            ],
          ),
          const SizedBox(height: 10),
          PriceChart(points: _points),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['realtime', '1m', '3m', '6m', '1y', 'all'].map((r) => _rangeChip(r)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(String r) {
    final selected = _range == r;
    return GestureDetector(
      onTap: () => _switchRange(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE3C8) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(_rangeLabel(r), style: TextStyle(fontSize: 12, color: selected ? const Color(0xFFB5791B) : Colors.grey[600], fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  String _rangeLabel(String r) => {'realtime': '实时', '1m': '近1月', '3m': '近3月', '6m': '近半年', '1y': '近1年', 'all': '全部'}[r] ?? r;
}
