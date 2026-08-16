import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/app_lock.dart';
import '../services/biometric_service.dart';
import '../widgets/pin_pad.dart';

/// 锁屏页（REQ-08）：进入应用 / 后台返回超时后展示。
/// PIN 连续错 5 次锁定 30 秒（REQ-08.3）。
class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key, this.transparentBackground = false});

  final bool transparentBackground;

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> {
  final _guard = PinAttemptGuard();
  String _digits = '';
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 生物识别开启时自动拉起一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.lockBiometric || _guard.isLocked) return;
    final ok = await BiometricService.authenticate('验证身份以解锁拾页');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_guard.isLocked) {
        _ticker?.cancel();
        setState(() => _error = null);
      } else {
        setState(() {});
      }
    });
  }

  void _input(String digit) {
    if (_guard.isLocked) return;
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == 4) {
      final pin = _digits;
      _digits = '';
      _verify(pin);
    }
  }

  Future<void> _verify(String pin) async {
    final settings = context.read<SettingsProvider>();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    if (PinHasher.verify(pin, settings.lockSalt, settings.pinHash)) {
      _guard.registerSuccess();
      Navigator.of(context).pop(true);
      return;
    }
    final locked = _guard.registerFailure();
    setState(() {
      _error = locked
          ? '错误次数过多，请等待 ${_guard.lockRemainingSeconds} 秒'
          : 'PIN 不正确，还可尝试 ${PinAttemptGuard.maxAttempts - _guard.attempts} 次';
    });
    if (locked) _startTicker();
  }

  void _backspace() {
    if (_digits.isNotEmpty) {
      setState(() {
        _digits = _digits.substring(0, _digits.length - 1);
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = _guard.isLocked;

    return PopScope(
      canPop: false, // 锁屏不可返回
      child: Scaffold(
        backgroundColor: widget.transparentBackground
            ? scheme.surface
            : scheme.surfaceContainerLow,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 40, color: scheme.primary),
                  const SizedBox(height: 10),
                  Text(
                    '拾页已锁定',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (locked)
                    Column(
                      children: [
                        Text(
                          '已锁定，${_guard.lockRemainingSeconds} 秒后可重试',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE57373),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    )
                  else
                    PinPad(
                      length: 4,
                      digits: _digits,
                      onDigit: _input,
                      onBackspace: _backspace,
                      errorText: _error,
                      hint: '输入 PIN 解锁',
                    ),
                  if (context.watch<SettingsProvider>().lockBiometric &&
                      !locked) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      icon: Icon(Icons.fingerprint_rounded,
                          color: scheme.primary),
                      label: const Text('使用生物识别'),
                      onPressed: _tryBiometric,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
