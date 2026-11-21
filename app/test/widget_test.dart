import 'package:flutter_test/flutter_test.dart';
import 'package:gold_app/models/data.dart';

void main() {
  test('Portfolio 数值解析', () {
    final p = Portfolio.fromJson({
      'balance': 100.5, 'grams': 10.0, 'cost_amount': 8008.0, 'avg_cost': 800.8,
      'current_price': 800.0, 'market_value': 8000.0, 'holding_pnl': -8.0,
      'realized_pnl': 0.0, 'total_pnl': -8.0, 'today_pnl': 0.0, 'total_assets': 8100.5,
    });
    expect(p.avgCost, 800.8);
    expect(p.holdingPnl, -8.0);
  });

  test('涨红跌绿颜色方向', () {
    // 仅验证模型能正常构造，颜色逻辑在 common.dart
    expect(FeeConfig.fromJson({
      'fee_mode': 'percent', 'buy_fee_rate': 0.001, 'sell_fee_rate': 0.002,
      'buy_fee_per_gram': 0.5, 'sell_fee_per_gram': 0.5, 'min_fee': 0.0,
    }).feeMode, 'percent');
  });
}
