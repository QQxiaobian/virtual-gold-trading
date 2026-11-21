import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/data.dart';
import '../widgets/common.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('后台管理'),
        backgroundColor: const Color(0xFFFFE3C8),
        bottom: TabBar(controller: _tabs, labelColor: const Color(0xFFB5791B), unselectedLabelColor: Colors.grey[600], indicatorColor: const Color(0xFFE8A33D), tabs: const [
          Tab(text: '费率'), Tab(text: '用户'), Tab(text: '统计'), Tab(text: '流水'),
        ]),
      ),
      body: WarmBackground(
        child: TabBarView(controller: _tabs, children: const [_FeeTab(), _UserTab(), _StatTab(), _FlowTab()]),
      ),
    );
  }
}

// ---------- 费率配置 ----------
class _FeeTab extends StatefulWidget { const _FeeTab(); @override State<_FeeTab> createState() => _FeeTabState(); }
class _FeeTabState extends State<_FeeTab> {
  FeeConfig? _cfg;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final d = await Api.adminFeeConfig();
      if (mounted) setState(() => _cfg = FeeConfig.fromJson(d));
    } on ApiError catch (e) { if (mounted) showError(context, e.message); }
  }
  Future<void> _save() async {
    if (_cfg == null) return;
    try {
      await Api.adminUpdateFee(_cfg!.toJson());
      if (mounted) showOk(context, '费率已保存，立即生效');
    } on ApiError catch (e) { if (mounted) showError(context, e.message); }
  }
  Widget build(BuildContext context) {
    if (_cfg == null) return const Center(child: CircularProgressIndicator());
    final c = _cfg!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      GoldCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('手续费计费方式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _modeBtn('percent', '按金额百分比')),
          const SizedBox(width: 10),
          Expanded(child: _modeBtn('per_gram', '按克固定金额')),
        ]),
      ])),
      GoldCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('费率参数', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
        const SizedBox(height: 12),
        if (c.feeMode == 'percent') ...[
          _numField('买入费率（%）', c.buyFeeRate * 100, (v) => c.buyFeeRate = v / 100),
          _numField('卖出费率（%）', c.sellFeeRate * 100, (v) => c.sellFeeRate = v / 100),
        ] else ...[
          _numField('买入每克（元）', c.buyFeePerGram, (v) => c.buyFeePerGram = v),
          _numField('卖出每克（元）', c.sellFeePerGram, (v) => c.sellFeePerGram = v),
        ],
        _numField('单笔最低手续费（元）', c.minFee, (v) => c.minFee = v),
      ])),
      GoldCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('允许用户自助充值', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
          const SizedBox(height: 4),
          const Text('关闭后仅管理员可在后台为用户充值', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        Switch(value: c.allowUserRecharge, activeColor: const Color(0xFFE8A33D), onChanged: (v) => setState(() => c.allowUserRecharge = v)),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(primary: const Color(0xFFE8A33D), padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('保存费率', style: TextStyle(color: Colors.white, fontSize: 16)))),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('提示：切换计费方式后，参数会按新方式解释并保存。', style: TextStyle(fontSize: 11, color: Colors.grey))),
    ]);
  }
  Widget _modeBtn(String mode, String label) {
    final active = _cfg?.feeMode == mode;
    return GestureDetector(onTap: () => setState(() => _cfg?.feeMode = mode), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: active ? const Color(0xFFF5D9A8) : Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: active ? const Color(0xFFE8A33D) : Colors.transparent)), child: Center(child: Text(label, style: TextStyle(fontSize: 13, color: active ? const Color(0xFFB5791B) : Colors.grey[600], fontWeight: active ? FontWeight.bold : FontWeight.normal)))));
  }
  Widget _numField(String label, double value, Function(double) onChanged) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 4));
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (s) { final v = double.tryParse(s); if (v != null) onChanged(v); }, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)));
  }
}

// ---------- 用户管理 ----------
class _UserTab extends StatefulWidget { const _UserTab(); @override State<_UserTab> createState() => _UserTabState(); }
class _UserTabState extends State<_UserTab> {
  List<UserInfo> _users = [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final d = await Api.adminUsers();
      if (mounted) setState(() => _users = (d as List).map((e) => UserInfo.fromJson(e)).toList());
    } on ApiError catch (e) { if (mounted) showError(context, e.message); }
  }
  void _addUser() {
    final u = TextEditingController(), p = TextEditingController(), n = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('新建用户'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: u, decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: p, decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: n, decoration: const InputDecoration(labelText: '昵称', border: OutlineInputBorder())),
    ]), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      ElevatedButton(onPressed: () async {
        try { await Api.adminCreateUser(u.text.trim(), p.text, n.text.trim()); if (!mounted) return; Navigator.pop(ctx); showOk(context, '用户已创建'); _load(); }
        on ApiError catch (e) { showError(context, e.message); }
      }, child: const Text('创建')),
    ]));
  }
  void _adjust(UserInfo user) {
    final amt = TextEditingController(), note = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('资金调整 · ${user.nickname}'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: '金额（正数加，负数扣）', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: note, decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder())),
    ]), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      ElevatedButton(onPressed: () async {
        final v = double.tryParse(amt.text.trim());
        if (v == null || v == 0) { showError(context, '请输入非零金额'); return; }
        try { await Api.adminAdjust(user.id, v, note.text.trim()); if (!mounted) return; Navigator.pop(ctx); showOk(context, '调整成功'); }
        on ApiError catch (e) { showError(context, e.message); }
      }, child: const Text('确定')),
    ]));
  }
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    ElevatedButton.icon(onPressed: _addUser, icon: const Icon(Icons.add), label: const Text('新建用户'), style: ElevatedButton.styleFrom(primary: const Color(0xFFE8A33D), padding: const EdgeInsets.symmetric(vertical: 12)),),
    const SizedBox(height: 10),
    ..._users.map((u) => GoldCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
      CircleAvatar(backgroundColor: const Color(0xFFF5D9A8), child: Text(u.nickname.isNotEmpty ? u.nickname[0] : 'U', style: const TextStyle(color: Color(0xFFB5791B)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${u.nickname} ${u.isAdmin ? "(管理员)" : ""}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
        Text('@${u.username} · ${u.isActive ? "正常" : "已禁用"}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ])),
      IconButton(icon: const Icon(Icons.attach_money, color: Color(0xFF1FA463)), tooltip: '资金调整', onPressed: () => _adjust(u)),
      IconButton(icon: Icon(u.isActive ? Icons.block : Icons.check_circle, color: Colors.grey), tooltip: u.isActive ? '禁用' : '启用', onPressed: () async {
        try { await Api.adminToggleUser(u.id, !u.isActive); _load(); } on ApiError catch (e) { if (mounted) showError(context, e.message); }
      }),
    ]))),
  ]);
}

// ---------- 统计 ----------
class _StatTab extends StatefulWidget { const _StatTab(); @override State<_StatTab> createState() => _StatTabState(); }
class _StatTabState extends State<_StatTab> {
  Map<String, dynamic>? _s;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final d = await Api.adminStats(); if (mounted) setState(() => _s = d); }
    on ApiError catch (e) { if (mounted) showError(context, e.message); }
  }
  Widget build(BuildContext context) {
    if (_s == null) return const Center(child: CircularProgressIndicator());
    final s = _s!;
    final userFees = (s['user_fees'] as List? ?? []);
    return ListView(padding: const EdgeInsets.all(16), children: [
      GoldCard(child: Column(children: [
        const Text('近30天手续费总收入', style: TextStyle(fontSize: 13, color: Color(0xFF8A7A68))),
        const SizedBox(height: 6),
        Text('${(s['total_fee'] as num).toStringAsFixed(2)} 元', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFC0392B))),
      ])),
      GoldCard(child: Column(children: [
        _row('买入笔数', '${s['buy_count']}'),
        _row('卖出笔数', '${s['sell_count']}'),
        _row('充值总额', '${(s['recharge_total'] as num).toStringAsFixed(2)} 元'),
      ])),
      GoldCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('各用户手续费', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
        const SizedBox(height: 8),
        ...userFees.map((e) => _row('${e['username']} (${e['transactions']}笔)', '${(e['fee'] as num).toStringAsFixed(2)} 元')),
        if (userFees.isEmpty) const Text('暂无数据', style: TextStyle(color: Colors.grey)),
      ])),
    ]);
  }
  Widget _row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: const TextStyle(fontSize: 13, color: Color(0xFF6B5A45))), Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A3626)))]) );
}

// ---------- 全局流水 ----------
class _FlowTab extends StatefulWidget { const _FlowTab(); @override State<_FlowTab> createState() => _FlowTabState(); }
class _FlowTabState extends State<_FlowTab> {
  List<Tx> _txs = [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final d = await Api.adminTransactions(); if (mounted) setState(() => _txs = (d as List).map((e) => Tx.fromJson(e)).toList()); }
    on ApiError catch (e) { if (mounted) showError(context, e.message); }
  }
  Future<void> _doRefund(Tx t) async {
    final ok = await confirmDialog(context, '确认退款',
      '将撤销这笔${t.typeLabel}（#${t.id}），回滚资金与持仓，且不可恢复。确定继续吗？');
    if (!ok) return;
    try {
      await Api.adminRefund(t.id);
      if (!mounted) return;
      showOk(context, '退款成功');
      _load();
    } on ApiError catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    ..._txs.map((t) {
      final canRefund = (t.type == 'buy' || t.type == 'sell') && !t.refunded;
      return GoldCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t.typeLabel} · #${t.id}${t.refunded ? "（已退款）" : ""}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
          Text('${t.note}', style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (t.fee > 0) Text('手续费 ${t.fee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFFB5791B))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${t.amount >= 0 ? "+" : ""}${t.amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.amount >= 0 ? const Color(0xFFE23E3E) : const Color(0xFF1FA463))),
          if (canRefund) TextButton(onPressed: () => _doRefund(t), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('退款', style: TextStyle(fontSize: 11, color: Color(0xFFC0392B)))),
        ]),
      ]));
    }),
  ]);
}
