import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/pin_lock_page.dart';
import '../providers/settings_provider.dart';

/// 应用锁门禁（REQ-08.2）：挂在 app 根部。
/// 冷启动、以及从后台返回超过设定时长时进入锁屏。
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _showing = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷启动：开启应用锁时先锁。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<SettingsProvider>().lockEnabled) {
        setState(() => _locked = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = context.read<SettingsProvider>();
    if (!settings.lockEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final elapsed = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (elapsed >= settings.lockDelay) {
        setState(() => _locked = true);
      }
    }
  }

  Future<void> _showLock() async {
    if (_showing) return;
    _showing = true;
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: PinLockPage(transparentBackground: true),
      ),
    );
    _showing = false;
    if (unlocked == true) {
      setState(() => _locked = false);
    } else if (mounted && _locked) {
      // 锁屏被意外关闭时再次拉起，确保内容不裸露。
      _showLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked && context.watch<SettingsProvider>().lockEnabled;
    if (locked) {
      // 冷启动 / 超时返回：直接展示锁屏，不露出内容。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _locked) _showLock();
      });
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        body: const SizedBox.shrink(),
      );
    }
    return widget.child;
  }
}

/// 敏感操作前的二次验证（REQ-08.5）：应用锁开启时验证 PIN，否则直接放行。
Future<bool> verifyAppLock(BuildContext context, {String? reason}) async {
  final settings = context.read<SettingsProvider>();
  if (!settings.lockEnabled) return true;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('身份验证'),
      content: Text(reason ?? '此操作需要验证 PIN'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final unlocked = await showDialog<bool>(
              context: dialogContext,
              barrierDismissible: false,
              builder: (_) => Dialog.fullscreen(
                backgroundColor: Colors.transparent,
                child: PinLockPage(transparentBackground: true),
              ),
            );
            if (unlocked == true && dialogContext.mounted) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: const Text('验证'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
