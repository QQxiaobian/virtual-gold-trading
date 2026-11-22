import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// API 客户端。
/// - Web 端：baseUrl 留空，走相对路径 /api，由 nginx 反向代理到后端（避免 CORS 与 IP 硬编码）
/// - APP 端：默认指向 NAS 地址，可在登录页 / "我的"页修改并持久化
class Api {
  static String baseUrl = kIsWeb ? "" : "http://192.168.1.12:8100";
  static String? _token;
  static const String version = "1.2.1";

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    // Web 端始终走相对路径（nginx 反代），不读取可能来自其它端的硬编码地址
    if (!kIsWeb) {
      final saved = prefs.getString('baseUrl');
      if (saved != null && saved.isNotEmpty) baseUrl = saved;
    }
  }

  static Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', url);
  }

  static Future<void> saveToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('token');
    } else {
      await prefs.setString('token', token);
    }
  }

  static String? get token => _token;

  static Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        if (auth && _token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<dynamic> _req(String method, String path, {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response resp;
    try {
      if (method == 'GET') {
        resp = await http.get(uri, headers: _headers(auth: auth));
      } else if (method == 'POST') {
        resp = await http.post(uri, headers: _headers(auth: auth), body: jsonEncode(body ?? {}));
      } else if (method == 'PUT') {
        resp = await http.put(uri, headers: _headers(auth: auth), body: jsonEncode(body ?? {}));
      } else {
        resp = await http.delete(uri, headers: _headers(auth: auth));
      }
    } catch (e) {
      throw ApiError('无法连接服务器，请检查网络与服务器地址（$baseUrl）');
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw ApiError(_msg(resp) ?? '登录已失效，请重新登录');
    }
    if (resp.statusCode >= 400) {
      throw ApiError(_msg(resp) ?? '请求失败(${resp.statusCode})');
    }
    if (resp.bodyBytes.isEmpty) return null;
    // 必须按 UTF-8 解码原始字节：Dart http 对无 charset 的 JSON 默认用 Latin-1，
    // 会把后端返回的中文解成 â®¢å£® 之类的乱码。
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static String? _msg(http.Response resp) {
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      return d['detail']?.toString();
    } catch (_) {
      return null;
    }
  }

  // 健康检查
  static Future<dynamic> health() => _req('GET', '/api/health', auth: false);

  // 认证
  static Future<dynamic> login(String u, String p) => _req('POST', '/api/auth/login',
      body: {'username': u, 'password': p}, auth: false);
  static Future<dynamic> register(String u, String p, String nick) => _req('POST', '/api/auth/register',
      body: {'username': u, 'password': p, 'nickname': nick}, auth: false);
  static Future<dynamic> me() => _req('GET', '/api/auth/me');
  static Future<dynamic> registerEnabled() => _req('GET', '/api/auth/register-enabled', auth: false);

  // 行情
  static Future<dynamic> price() => _req('GET', '/api/market/price');
  static Future<dynamic> history(String range) => _req('GET', '/api/market/history?range=$range');
  static Future<dynamic> sources() => _req('GET', '/api/market/sources');

  // 交易
  static Future<dynamic> feeConfigPublic() => _req('GET', '/api/trade/fee-config');
  static Future<dynamic> portfolio() => _req('GET', '/api/trade/portfolio');
  static Future<dynamic> buy(double grams) => _req('POST', '/api/trade/buy', body: {'grams': grams});
  static Future<dynamic> sell(double grams) => _req('POST', '/api/trade/sell', body: {'grams': grams});
  static Future<dynamic> rechargeEnabled() => _req('GET', '/api/trade/recharge-enabled');
  static Future<dynamic> recharge(double amount, String note) =>
      _req('POST', '/api/trade/recharge', body: {'amount': amount, 'note': note});
  static Future<dynamic> transactions({int skip = 0, int limit = 100}) =>
      _req('GET', '/api/trade/transactions?skip=$skip&limit=$limit');

  // 后台
  static Future<dynamic> adminUsers() => _req('GET', '/api/admin/users');
  static Future<dynamic> adminCreateUser(String u, String p, String nick) =>
      _req('POST', '/api/admin/users', body: {'username': u, 'password': p, 'nickname': nick});
  static Future<dynamic> adminToggleUser(int id, bool active) =>
      _req('PUT', '/api/admin/users/$id/active?is_active=$active');
  static Future<dynamic> adminAdjust(int uid, double amount, String note) =>
      _req('POST', '/api/admin/adjust', body: {'user_id': uid, 'amount': amount, 'note': note});
  static Future<dynamic> adminFeeConfig() => _req('GET', '/api/admin/fee-config');
  static Future<dynamic> adminUpdateFee(Map<String, dynamic> cfg) =>
      _req('PUT', '/api/admin/fee-config', body: cfg);
  static Future<dynamic> adminStats({int days = 30}) => _req('GET', '/api/admin/statistics?days=$days');
  static Future<dynamic> adminTransactions({int limit = 200}) =>
      _req('GET', '/api/admin/transactions?limit=$limit');
  static Future<dynamic> adminRefund(int txId) =>
      _req('POST', '/api/admin/refund/$txId');
  static Future<dynamic> adminUserDetail(int uid) => _req('GET', '/api/admin/users/$uid/detail');
  static Future<dynamic> adminDeleteUser(int uid) => _req('DELETE', '/api/admin/users/$uid');
  static Future<dynamic> adminResetPassword(int uid, String password) =>
      _req('PUT', '/api/admin/users/$uid/password', body: {'new_password': password});
  static Future<dynamic> adminResetBalance(int uid, double amount, String note) =>
      _req('POST', '/api/admin/users/$uid/reset-balance', body: {'amount': amount, 'note': note});
  static Future<dynamic> adminUndoRecharge(int txId) => _req('POST', '/api/admin/undo-recharge/$txId');
  static Future<dynamic> adminResetFeeRecords() => _req('POST', '/api/admin/reset-fee-records');
  static Uri exportUrl({int? uid, int? days}) {
    final q = <String>[];
    if (_token != null) q.add('token=${Uri.encodeComponent(_token!)}');
    if (uid != null) q.add('user_id=$uid');
    if (days != null) q.add('days=$days');
    return Uri.parse('$baseUrl/api/admin/export-transactions${q.isNotEmpty ? "?${q.join("&")}" : ""}');
  }
}

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}
