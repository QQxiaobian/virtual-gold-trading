import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/data.dart';
import '../widgets/common.dart';

class TradeTab extends StatefulWidget {
  const TradeTab({super.key});
  @override
  State<TradeTab> createState() => _TradeTabState();
}

class _TradeTabState extends State<TradeTab> {
  int _side = 0; // 0 买入 1 卖出
  final _grams = TextEditingController();
  Portfolio? _p;
  FeeConfig? _fee;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.portfolio();
      dynamic fee;
      try { fee = await Api.feeConfigPublic(); } catch (_) { fee = null; }
      if (!mounted) return;
      setState(() {
        _p = Portfolio.fromJson(p);
        _fee = fee != null ? FeeConfig.fromJson(fee) : null;
      });
    } on ApiError catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {}
  }

  double? get _parsed => double.tryParse(_grams.text.trim());

  FeeEstimate _estimate(double grams) {
    if (_p == null || grams <= 0) return FeeEstimate(0, '');
    final amount = grams * _p!.currentPrice;
    double fee;
    String desc;
    final f = _fee;
    if (f != null && f.feeMode == 'per_gram') {
      final rate = _side == 0 ? f.buyFeePerGram : f.sellFeePerGram;
      fee = grams * rate;
      desc = '每克 $rate 元 × $grams 克';
    } else {
      final rate = f != null ? (_side == 0 ? f.buyFeeRate : f.sellFeeRate) : 0.001;
      fee = amount * rate;
      desc = '费率 ${(rate * 100).toStringAsFixed(3)}%';
    }
    if (f != null && fee < f.minFee) { fee = f.minFee; desc += '（最低收费）'; }
    return FeeEstimate(fee, desc);
  }

  Future<void> _submit() async {
    final g = _parsed;
    if (g == null || g <= 0) { showError(context, '请输入有效克重'); return; }
    final est = _estimate(g);
    final total = g * (_p?.currentPrice ?? 0);
    final isBuy = _side == 0;
    final ok = await confirmDialog(
      context,
      isBuy ? '确认买入' : '确认卖出',
      '${isBuy ? '买入' : '卖出'} ${g.toStringAsFixed(4)} 克 @ ${(_p?.currentPrice ?? 0).toStringAsFixed(2)} 元/克\n'
      '成交额：${total.toStringAsFixed(2)} 元\n'
      '手续费：${est.fee.toStringAsFixed(2)} 元${est.desc.isNotEmpty ? '（${est.desc}）' : ''}\n'
      '${isBuy ? '预计支出' : '预计到账'}：${(isBuy ? total + est.fee : total - est.fee).toStringAsFixed(2)} 元\n\n'
      '请确认无误后再提交。',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final tx = isBuy ? await Api.buy(g) : await Api.sell(g);
      if (!mounted) return;
      final t = Tx.fromJson(tx);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text(_side == 0 ? '买入成功' : '卖出成功'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t.typeLabel} ${t.grams.abs().toStringAsFixed(4)} 克 @ ${t.price.toStringAsFixed(2)} 元/克'),
          const SizedBox(height: 6),
          Text('成交额：${(t.grams.abs() * t.price).toStringAsFixed(2)} 元'),
          Text('手续费：${t.fee.toStringAsFixed(2)} 元（${t.feeDesc}）'),
          if (_side == 1) Text('本次盈亏：${(t.realizedPnl >= 0 ? '+' : '')}${t.realizedPnl.toStringAsFixed(2)} 元', style: TextStyle(color: pnlColor(t.realizedPnl))),
          const SizedBox(height: 6),
          Text('余额：${t.balanceAfter.toStringAsFixed(2)} 元'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
      ));
      _grams.clear();
      await _load();
    } on ApiError catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '交易失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WarmBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20, top: 10),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('黄金买卖', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
            ),
            _priceCard(),
            GoldCard(
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: _sideBtn(0, '买入')),
                    const SizedBox(width: 10),
                    Expanded(child: _sideBtn(1, '卖出')),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _grams,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '克重（克）',
                      suffixText: '当前价 ${_p?.currentPrice.toStringAsFixed(2) ?? "--"}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_parsed != null && _parsed! > 0) _estimateCard(_parsed!),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        primary: _side == 0 ? const Color(0xFFE23E3E) : const Color(0xFF1FA463),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _busy ? const CircularProgressIndicator(color: Colors.white) : Text(_side == 0 ? '确认买入' : '确认卖出', style: const TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceCard() {
    final p = _p;
    return GoldCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('实时金价（元/克）', style: TextStyle(fontSize: 12, color: Color(0xFF8A7A68))),
            SizedBox(height: 4),
            Text('Au99.99 上金所', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          Text(p != null ? p.currentPrice.toStringAsFixed(2) : '--', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xFFC0392B))),
        ],
      ),
    );
  }

  Widget _sideBtn(int side, String label) {
    final active = _side == side;
    return GestureDetector(
      onTap: () => setState(() => _side = side),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? (side == 0 ? const Color(0xFFE23E3E) : const Color(0xFF1FA463)) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.grey[600]))),
      ),
    );
  }

  Widget _estimateCard(double grams) {
    final est = _estimate(grams);
    final total = grams * (_p?.currentPrice ?? 0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF8EF), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        _row('成交金额', '${total.toStringAsFixed(2)} 元'),
        _row('预估手续费', '${est.fee.toStringAsFixed(2)} 元'),
        if (est.desc.isNotEmpty) _row('计费方式', est.desc),
        _row(_side == 0 ? '预计支出' : '预计到账', '${(_side == 0 ? total + est.fee : total - est.fee).toStringAsFixed(2)} 元', bold: true),
      ]),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(v, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: const Color(0xFF5A4A38))),
      ]),
    );
  }
}

/// 手续费预估结果（Dart 2.17 无 Record 类型，用类代替）
class FeeEstimate {
  final double fee;
  final String desc;
  FeeEstimate(this.fee, this.desc);
}
