/// 数据模型：解析后端 JSON。

class UserInfo {
  final int id;
  final String username;
  final String nickname;
  final String role;
  final bool isActive;
  UserInfo({required this.id, required this.username, required this.nickname, required this.role, required this.isActive});
  bool get isAdmin => role == 'admin';
  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        id: j['id'] ?? 0,
        username: j['username'] ?? '',
        nickname: j['nickname'] ?? '',
        role: j['role'] ?? 'user',
        isActive: j['is_active'] ?? true,
      );
}

class Portfolio {
  final double balance, grams, costAmount, avgCost, currentPrice;
  final double marketValue, holdingPnl, realizedPnl, totalPnl, todayPnl, totalAssets;
  Portfolio({
    required this.balance, required this.grams, required this.costAmount, required this.avgCost,
    required this.currentPrice, required this.marketValue, required this.holdingPnl,
    required this.realizedPnl, required this.totalPnl, required this.todayPnl, required this.totalAssets,
  });
  factory Portfolio.fromJson(Map<String, dynamic> j) => Portfolio(
        balance: _d(j['balance']), grams: _d(j['grams']), costAmount: _d(j['cost_amount']),
        avgCost: _d(j['avg_cost']), currentPrice: _d(j['current_price']),
        marketValue: _d(j['market_value']), holdingPnl: _d(j['holding_pnl']),
        realizedPnl: _d(j['realized_pnl']), totalPnl: _d(j['total_pnl']),
        todayPnl: _d(j['today_pnl']), totalAssets: _d(j['total_assets']),
      );
  static double _d(v) => (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
}

class Tx {
  final int id;
  final String type, feeDesc, note, createdAt;
  final double amount, grams, price, fee, balanceAfter, realizedPnl;
  final bool refunded;
  Tx({
    required this.id, required this.type, required this.amount, required this.grams,
    required this.price, required this.fee, required this.feeDesc, required this.balanceAfter,
    required this.realizedPnl, required this.note, required this.createdAt, this.refunded = false,
  });
  factory Tx.fromJson(Map<String, dynamic> j) => Tx(
        id: j['id'] ?? 0, type: j['type'] ?? '', amount: Portfolio._d(j['amount']),
        grams: Portfolio._d(j['grams']), price: Portfolio._d(j['price']), fee: Portfolio._d(j['fee']),
        feeDesc: j['fee_desc'] ?? '', balanceAfter: Portfolio._d(j['balance_after']),
        realizedPnl: Portfolio._d(j['realized_pnl']), note: j['note'] ?? '', createdAt: j['created_at'] ?? '',
        refunded: j['refunded'] ?? false,
      );
  String get typeLabel => {'recharge': '充值', 'buy': '买入', 'sell': '卖出', 'adjust': '调整', 'refund': '退款'}[type] ?? type;
}

class PricePoint {
  final DateTime time;
  final double price;
  PricePoint({required this.time, required this.price});
  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
        time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        price: Portfolio._d(j['price']),
      );
}

class FeeConfig {
  String feeMode;
  double buyFeeRate, sellFeeRate, buyFeePerGram, sellFeePerGram, minFee, buySellSpread;
  bool allowUserRecharge, allowRegister;
  FeeConfig({
    required this.feeMode, required this.buyFeeRate, required this.sellFeeRate,
    required this.buyFeePerGram, required this.sellFeePerGram, required this.minFee,
    this.allowUserRecharge = false, this.allowRegister = false, this.buySellSpread = 0.0006,
  });
  factory FeeConfig.fromJson(Map<String, dynamic> j) => FeeConfig(
        feeMode: j['fee_mode'] ?? 'percent', buyFeeRate: Portfolio._d(j['buy_fee_rate']),
        sellFeeRate: Portfolio._d(j['sell_fee_rate']), buyFeePerGram: Portfolio._d(j['buy_fee_per_gram']),
        sellFeePerGram: Portfolio._d(j['sell_fee_per_gram']), minFee: Portfolio._d(j['min_fee']),
        buySellSpread: Portfolio._d(j['buy_sell_spread']) == 0 ? 0.0006 : Portfolio._d(j['buy_sell_spread']),
        allowUserRecharge: j['allow_user_recharge'] == true || j['allow_user_recharge'] == '1' || j['allow_user_recharge'] == 'true',
        allowRegister: j['allow_register'] == true || j['allow_register'] == '1' || j['allow_register'] == 'true',
      );
  Map<String, dynamic> toJson() => {
        'fee_mode': feeMode,
        'buy_fee_rate': '$buyFeeRate', 'sell_fee_rate': '$sellFeeRate',
        'buy_fee_per_gram': '$buyFeePerGram', 'sell_fee_per_gram': '$sellFeePerGram',
        'min_fee': '$minFee',
        'buy_sell_spread': '$buySellSpread',
        'allow_user_recharge': allowUserRecharge ? '1' : '0',
        'allow_register': allowRegister ? '1' : '0',
      };
}

/// 实时行情买卖价
class PriceQuote {
  final double price, buyPrice, sellPrice, spread;
  PriceQuote({required this.price, required this.buyPrice, required this.sellPrice, required this.spread});
  factory PriceQuote.fromJson(Map<String, dynamic> j) => PriceQuote(
        price: Portfolio._d(j['price']), buyPrice: Portfolio._d(j['buy_price']),
        sellPrice: Portfolio._d(j['sell_price']), spread: Portfolio._d(j['spread']),
      );
}
