import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/data.dart';
import '../widgets/common.dart';
import 'admin.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  UserInfo? _user;
  Portfolio? _p;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await Api.me();
      final p = await Api.portfolio();
      if (!mounted) return;
      setState(() {
        _user = UserInfo.fromJson(u);
        _p = Portfolio.fromJson(p);
      });
    } on ApiError catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {}
  }

  void _recharge() {
    final ctrl = TextEditingController();
    final note = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('虚拟充值'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '金额（元）', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final amt = double.tryParse(ctrl.text.trim());
          if (amt == null || amt <= 0) { showError(context, '请输入有效金额'); return; }
          try {
            await Api.recharge(amt, note.text.trim());
            if (!mounted) return;
            Navigator.pop(ctx);
            showOk(context, '充值成功');
            _load();
          } on ApiError catch (e) {
            showError(context, e.message);
          }
        }, child: const Text('充值')),
      ],
    ));
  }

  void _setServer() {
    final ctrl = TextEditingController(text: Api.baseUrl);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('服务器地址'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '如 http://192.168.1.10:8100', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          await Api.setBaseUrl(ctrl.text.trim());
          if (!mounted) return;
          Navigator.pop(ctx);
          showOk(context, '已保存，请重新登录生效');
        }, child: const Text('保存')),
      ],
    ));
  }

  void _logout() async {
    final ok = await confirmDialog(context, '退出登录', '确定要退出当前账号吗？');
    if (!ok) return;
    await Api.saveToken(null);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return WarmBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20, top: 10),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('我的', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
            ),
            GoldCard(
              child: Row(
                children: [
                  CircleAvatar(radius: 30, backgroundColor: const Color(0xFFF5D9A8), child: const Icon(Icons.person, size: 30, color: Color(0xFFB5791B))),
                  const SizedBox(height: 1, width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u?.nickname ?? '...', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('@${u?.username ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (u?.isAdmin == true) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: const Color(0xFFF5D9A8), borderRadius: BorderRadius.circular(6)), child: const Text('管理员', style: TextStyle(fontSize: 10, color: Color(0xFFB5791B)))),
                    ]),
                  ]),
                ],
              ),
            ),
            GoldCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(children: [
                _assetRow('总资产', '${_p?.totalAssets.toStringAsFixed(2) ?? "--"} 元', bold: true),
                _assetRow('可用资金', '${_p?.balance.toStringAsFixed(2) ?? "--"} 元'),
                _assetRow('持仓市值', '${_p?.marketValue.toStringAsFixed(2) ?? "--"} 元'),
                _assetRow('累计收益', '${_p?.totalPnl.toStringAsFixed(2) ?? "--"} 元', color: _p != null ? pnlColor(_p!.totalPnl) : null),
              ]),
            ),
            GoldCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                _tile(Icons.account_balance_wallet, '虚拟充值', _recharge),
                const Divider(height: 1, indent: 56),
                _tile(Icons.dns, '服务器设置', _setServer),
                if (u?.isAdmin == true) ...[
                  const Divider(height: 1, indent: 56),
                  _tile(Icons.admin_panel_settings, '后台管理', () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()));
                  }),
                ],
                const Divider(height: 1, indent: 56),
                _tile(Icons.logout, '退出登录', _logout),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('v${Api.version} · 自用模拟盘', style: TextStyle(fontSize: 11, color: Colors.grey[400])))),
          ],
        ),
      ),
    );
  }

  Widget _assetRow(String k, String v, {bool bold = false, Color? color}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(fontSize: 13, color: Color(0xFF6B5A45))),
      Text(v, style: TextStyle(fontSize: bold ? 20 : 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color ?? const Color(0xFF4A3626))),
    ]));
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(leading: Icon(icon, color: const Color(0xFFC9932F)), title: Text(label, style: const TextStyle(fontSize: 14)), onTap: onTap, trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey));
  }
}
