// Web 平台：用 dart:html 打开下载链接（带 token 的 CSV 导出 URL）。
import 'dart:html' as html;
import 'package:flutter/material.dart';

void openForDownload(Uri url, BuildContext context) {
  html.window.open(url.toString(), '_blank');
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已在新标签页开始下载 CSV')),
  );
}
