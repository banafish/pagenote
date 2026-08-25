import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/pack_detail_page.dart';
import '../pages/share_pack_import_page.dart';

/// 分享包入口（REQ-21.11）：系统把 zip 交给拾页时,原生侧只暂存到私有缓存,
/// 由本层在启动与每次回到前台时主动来取,再打开导入预览页(REQ-21.5)。
///
/// 挂在 [LockGate] 内侧 —— 应用锁未解开时本层根本不挂载,导入页不会盖在锁屏之上。
/// 仅 Android 有原生实现;Windows 走设置页手动选择文件(REQ-21.12),此处直接空转。
class SharePackGate extends StatefulWidget {
  const SharePackGate({super.key, required this.child});

  final Widget child;

  @override
  State<SharePackGate> createState() => _SharePackGateState();
}

class _SharePackGateState extends State<SharePackGate>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('pagenote/app');

  /// 导入流程进行中:不重复取包、不叠开第二个预览页。
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    // 冷启动:首帧后再取,此时 Navigator 已就绪。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPack());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 热启动:原生侧 onNewIntent 之后必然走一次 onResume,在这里补取。
    if (state == AppLifecycleState.resumed) _consumePendingPack();
  }

  Future<void> _consumePendingPack() async {
    if (_handling) return;
    Map<Object?, Object?>? pending;
    try {
      pending = await _channel.invokeMethod<Map<Object?, Object?>>(
        'sharePack.consumePending',
      );
    } on MissingPluginException {
      return; // 原生侧未实现（测试环境）。
    } on PlatformException {
      return;
    }
    final path = pending?['path'] as String?;
    if (path == null || path.isEmpty || !mounted) return;

    _handling = true;
    final file = File(path);
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      _handling = false;
      return;
    }
    try {
      await file.delete();
    } on FileSystemException {
      // 缓存文件删不掉不影响导入,下次收包时会被整目录清掉。
    }
    if (!mounted) {
      _handling = false;
      return;
    }
    try {
      await _openImportPage(bytes, pending?['name'] as String?);
    } finally {
      _handling = false;
    }
  }

  Future<void> _openImportPage(Uint8List bytes, String? sourceName) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<SharePackImportResult>(
      MaterialPageRoute(
        builder: (_) =>
            SharePackImportPage(bytes: bytes, sourceName: sourceName),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    // REQ-26.4：导入完成直达对应包详情页并高亮新装的内容——
    // 包有了自己的页面,回跳有了天然落点,不再连续 push 两个管理页。
    // 极端情况下（素材全部被尺寸闸拦下）没有落位包,留在当前页即可。
    if (result.packId != null) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PackDetailPage.pack(
            result.packId!,
            highlightTemplateIds: result.templateIds,
            highlightStickerIds: result.stickerIds,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
