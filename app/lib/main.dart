import 'package:flutter/material.dart';
import 'services/api.dart';
import 'screens/login.dart';
import 'screens/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const GoldApp());
}

class GoldApp extends StatelessWidget {
  const GoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '虚拟黄金交易',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        primaryColor: const Color(0xFFE8A33D),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8A33D)),
        scaffoldBackgroundColor: const Color(0xFFFFF3E8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF4A3626),
        ),
      ),
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}

/// 根据是否有 token 决定进入登录页或主页。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (Api.token != null && Api.token!.isNotEmpty) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}
