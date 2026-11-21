// 条件导出：Web 用 dart:html 打开下载，APP 用剪贴板复制。
export 'url_helper_stub.dart'
    if (dart.library.html) 'url_helper_web.dart';
