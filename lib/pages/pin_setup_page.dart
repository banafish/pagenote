import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/app_lock.dart';
import '../services/biometric_service.dart';
import '../widgets/pin_pad.dart';

/// 应用锁开启流程（REQ-08.1）：
/// 风险确认 → 设置 PIN（两次）→ 可选开启生物识别。
/// 也可用于修改 PIN（跳过风险确认步骤）。
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key, this.skipRiskNotice = false});

  /// 修改 PIN 时已通过验证，跳过风险告知。
  final bool skipRiskNotice;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  int _step = 0; // 0 风险确认 → 1 输入新 PIN → 2 确认 PIN → 3 生物识别
  String _first = '';
  String _second = '';
  String? _error;
  bool _riskAck = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.skipRiskNotice) _step = 1;
    BiometricService.isAvailable.then(
      (v) => mounted ? setState(() => _biometricAvailable = v) : null,
    );
  }

  void _input(String digit) {
    setState(() => _error = null);
    final current = _step == 1 ? _first : _second;
    final next = current + digit;
    if (_step == 1) {
      _first = next;
      if (next.length == 4) {
        setState(() => _step = 2);
      }
    } else {
      _second = next;
      if (next.length == 4) {
        if (_second == _first) {
          setState(() => _step = 3);
        } else {
          setState(() {
            _error = '两次输入不一致，请重新设置';
            _first = '';
            _second = '';
            _step = 1;
          });
        }
      }
    }
  }

  void _backspace() {
    setState(() => _error = null);
    if (_step == 2 && _second.isNotEmpty) {
      _second = _second.substring(0, _second.length - 1);
      return;
    }
    if (_step == 2 && _second.isEmpty) {
      setState(() => _step = 1);
      return;
    }
    if (_first.isNotEmpty) {
      _first = _first.substring(0, _first.length - 1);
    }
  }

  Future<void> _finish({bool enableBiometric = false}) async {
    final settings = context.read<SettingsProvider>();
    final salt = PinHasher.newSalt();
    await settings.setPin(salt, PinHasher.hash(_first, salt));
    await settings.setLockBiometric(enableBiometric && _biometricAvailable);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用锁已开启 🔒')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _step == 0 || _step == 3,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.skipRiskNotice ? '修改 PIN' : '开启应用锁')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _step == 0
                  ? _riskStep(scheme)
                  : _step == 3
                  ? _biometricStep(scheme)
                  : PinPad(
                      length: 4,
                      digits: _step == 1 ? _first : _second,
                      onDigit: _input,
                      onBackspace: _backspace,
                      errorText: _error,
                      hint: _step == 1 ? '设置 4 位数字 PIN' : '再次输入以确认',
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _riskStep(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 44, color: scheme.primary),
        const SizedBox(height: 18),
        const Text(
          '开启应用锁前请知悉',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          '· 进入拾页需要验证 PIN 或生物识别\n'
          '· 拾页没有账号体系，PIN 不设找回渠道\n'
          '· 忘记 PIN 将无法找回，只能清除应用数据，'
          '所有手账与图片会被一并清除',
          style: TextStyle(height: 1.9, fontSize: 14),
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          value: _riskAck,
          onChanged: (v) => setState(() => _riskAck = v ?? false),
          title: const Text('我已了解风险并确认开启', style: TextStyle(fontSize: 14)),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _riskAck
                ? () => setState(() {
                    _step = 1;
                    _first = '';
                    _second = '';
                  })
                : null,
            child: const Text('继续'),
          ),
        ),
      ],
    );
  }

  Widget _biometricStep(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fingerprint_rounded, size: 44, color: scheme.primary),
        const SizedBox(height: 18),
        const Text(
          'PIN 已设置',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _biometricAvailable ? '要开启指纹 / 面容解锁吗？' : '当前设备不支持生物识别',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_biometricAvailable) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.fingerprint_rounded, size: 20),
              label: const Text('开启生物识别'),
              onPressed: () => _finish(enableBiometric: true),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _finish(),
            child: const Text('暂不开启，仅用 PIN'),
          ),
        ),
      ],
    );
  }
}
