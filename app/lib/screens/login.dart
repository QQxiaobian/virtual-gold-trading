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
                Text('请先在右上角设置服务器地址为 NAS 地址', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
