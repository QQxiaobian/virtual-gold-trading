// 非 Web 平台（APP）的空实现：由 openForDownload 统一处理。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void openForDownload(Uri url, BuildContext context) {
  // APP 端无法直接用浏览器下载，复制链接到剪贴板，提示用户粘贴到浏览器打开。
  Clipboard.setData(ClipboardData(text: url.toString()));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('下载链接已复制，请粘贴到浏览器打开下载 CSV')),
  );
}
