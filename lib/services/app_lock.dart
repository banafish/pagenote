import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// PIN 加盐哈希（REQ-08）：随机盐 + 多轮 SHA-256。
class PinHasher {
  PinHasher._();

  static const _rounds = 5000;

  static String newSalt() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => rand.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hash(String pin, String salt) {
    var digest = '$salt:$pin';
    for (var i = 0; i < _rounds; i++) {
      digest = sha256.convert(digest.codeUnits).toString();
    }
    return digest;
  }

  static bool verify(String pin, String salt, String expected) {
    if (salt.isEmpty || expected.isEmpty) return false;
    final h = hash(pin, salt);
    // 常量时间比较，避免时序侧信道。
    var diff = 0;
    for (var i = 0; i < h.length && i < expected.length; i++) {
      diff |= h.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    diff |= h.length ^ expected.length;
    return diff == 0;
  }
}

/// PIN 错误次数守卫（REQ-08.3）：连续错 5 次锁定 30 秒。
class PinAttemptGuard extends ChangeNotifier {
  PinAttemptGuard([this._clock]);

  static const maxAttempts = 5;
  static const lockoutDuration = Duration(seconds: 30);

  final DateTime Function()? _clock;
  int _attempts = 0;
  DateTime? _lockedUntil;

  DateTime get _now => _clock?.call() ?? DateTime.now();

  int get attempts => _attempts;

  /// 是否处于锁定状态。
  bool get isLocked {
    final until = _lockedUntil;
    return until != null && _now.isBefore(until);
  }

  /// 剩余锁定秒数（向上取整）。
  int get lockRemainingSeconds {
    if (!isLocked) return 0;
    final ms = _lockedUntil!.difference(_now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// 记录一次失败；达到 5 次进入锁定。返回是否触发锁定。
  bool registerFailure() {
    _attempts++;
    if (_attempts >= maxAttempts) {
      _lockedUntil = _now.add(lockoutDuration);
      _attempts = 0;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// 记录成功，清空计数。
  void registerSuccess() {
    _attempts = 0;
    _lockedUntil = null;
    notifyListeners();
  }
}
