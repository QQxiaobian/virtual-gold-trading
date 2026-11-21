import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _nick = TextEditingController();
  bool _loading = false;
  bool _registerMode = false;

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      showError(context, '请输入账号和密码');
      return;
    }
    setState(() => _loading = true);
    try {
      final data = _registerMode
          ? await Api.register(_user.text.trim(), _pass.text, _nick.text.trim())
          : await Api.login(_user.text.trim(), _pass.text);
      await Api.saveToken(data['access_token']);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiError catch (e) {
      showError(context, e.message);
    } catch (e) {
      showError(context, '登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setServer() {
    final ctrl = TextEditingController(text: Api.baseUrl);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('服务器地址'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('填写 NAS 上后端地址，含 http:// 与端口', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: '如 http://192.168.1.12:8100', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final url = ctrl.text.trim();
          if (url.isEmpty || !url.startsWith('http')) {
            showError(context, '地址需以 http:// 或 https:// 开头');
            return;
          }
          await Api.setBaseUrl(url);
          if (!mounted) return;
          Navigator.pop(ctx);
          setState(() {});
          showOk(context, '服务器地址已保存');
        }, child: const Text('保存')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WarmBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 20)]),
                  child: const Icon(Icons.monetization_on, size: 56, color: Color(0xFFE8A33D)),
                ),
                const SizedBox(height: 16),
                const Text('虚拟黄金交易', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF4A3626))),
                const SizedBox(height: 4),
                Text('v${Api.version} · 自用模拟盘', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                const SizedBox(height: 30),
                GoldCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _setServer,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xFFFDF6E9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFF0D9A8))),
                          child: Row(children: [
                            const Icon(Icons.dns, size: 16, color: Color(0xFFB5791B)),
                            const SizedBox(width: 8),
                            Expanded(child: Text('服务器：${Api.baseUrl}', style: const TextStyle(fontSize: 12, color: Color(0xFF8A6D3B)), overflow: TextOverflow.ellipsis)),
                            const Icon(Icons.edit, size: 14, color: Color(0xFFB5791B)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(controller: _user, decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
                      const SizedBox(height: 14),
                      TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.lock), border: OutlineInputBorder())),
                      if (_registerMode) ...[
                        const SizedBox(height: 14),
                        TextField(controller: _nick, decoration: const InputDecoration(labelText: '昵称（可选）', prefixIcon: Icon(Icons.badge), border: OutlineInputBorder())),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(primary: const Color(0xFFE8A33D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: _loading ? const CircularProgressIndicator(color: Colors.white) : Text(_registerMode ? '注册并登录' : '登录', style: const TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _registerMode = !_registerMode),
                        child: Text(_registerMode ? '已有账号？去登录' : '没有账号？去注册'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('点击上方服务器地址可修改为你的 NAS 地址', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
