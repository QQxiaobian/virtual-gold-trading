import 'package:flutter/material.dart';
import 'overview.dart';
import 'trade.dart';
import 'records.dart';
import 'profile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _pages = const [OverviewTab(), TradeTab(), RecordsTab(), ProfileTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFE8A33D),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: '持仓'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: '交易'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: '明细'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
